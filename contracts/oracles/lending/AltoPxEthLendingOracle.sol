// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleCurve} from "@alto/oracles/lending/modules/ModuleCurve.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {CurveNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";
import {
    IAltoPxEthLendingOracleStaticTypes,
    IAltoPxEthLendingOracleBase
} from "@alto/oracles/interfaces/IAltoPxEthLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoPxEthLendingOracle
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An oracle that gets the price of PXETH in USD using the curve and chainlink
/// @dev uses the average of curve pool PXETH/WETH and PXETH/STETH to get the price of PXETH in ETH. Assumes that steth is pegged to eth
/// @dev uses chainlink to get the price of ETH in USD
contract AltoPxEthLendingOracle is Ownable2Step, ModuleCurve, ModuleChainlink, IAltoPxEthLendingOracleStaticTypes {
    /// @inheritdoc IAltoPxEthLendingOracleStaticTypes
    CurveNode public curveNode1;

    /// @inheritdoc IAltoPxEthLendingOracleStaticTypes
    uint256[] public minAllowedLiquidityPool1;

    /// @inheritdoc IAltoPxEthLendingOracleStaticTypes
    CurveNode public curveNode2;

    /// @inheritdoc IAltoPxEthLendingOracleStaticTypes
    uint256[] public minAllowedLiquidityPool2;

    /// @inheritdoc IAltoPxEthLendingOracleBase
    uint256 public maxAllowedDeviation;

    /// @inheritdoc IAltoPxEthLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _curveNode1 The curve node for curve pool 1
    /// @param _minAllowedLiquidityPool1 The minimum allowed liquidity pool for curve pool 1
    /// @param _curveNode2 The curve node for curve pool 2
    /// @param _minAllowedLiquidityPool2 The minimum allowed liquidity pool for curve pool 2
    /// @param _maxAllowedDeviation The maximum allowed deviation
    /// @param _chainlinkNode The chainlink node
    constructor(
        address _owner,
        CurveNode memory _curveNode1,
        uint256[] memory _minAllowedLiquidityPool1,
        CurveNode memory _curveNode2,
        uint256[] memory _minAllowedLiquidityPool2,
        uint256 _maxAllowedDeviation,
        ChainlinkNode memory _chainlinkNode
    ) Ownable(_owner) {
        if (_maxAllowedDeviation == 0 || _maxAllowedDeviation > MATH_PRECISION) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        // validates that out decimals of curveNode1, curveNode2 are the same
        if (_curveNode1.outDecimals != _curveNode2.outDecimals) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        // validates that the minimum allowed liquidity pool is not 0
        for (uint256 i = 0; i < _minAllowedLiquidityPool1.length; i++) {
            if (_minAllowedLiquidityPool1[i] == 0) {
                revert AltoPxEthLendingOracleInvalidInput();
            }
        }
        for (uint256 i = 0; i < _minAllowedLiquidityPool2.length; i++) {
            if (_minAllowedLiquidityPool2[i] == 0) {
                revert AltoPxEthLendingOracleInvalidInput();
            }
        }
        // validates the curve node parameters
        _validateCurveParams(_curveNode1);
        _validateCurveParams(_curveNode2);

        minAllowedLiquidityPool1 = _minAllowedLiquidityPool1;
        emit SetMinAllowedLiquidityPool1(new uint256[](0), _minAllowedLiquidityPool1);

        minAllowedLiquidityPool2 = _minAllowedLiquidityPool2;
        emit SetMinAllowedLiquidityPool2(new uint256[](0), _minAllowedLiquidityPool2);

        curveNode1 = _curveNode1;
        emit SetCurveNode1(CurveNode(ICurvePool(address(0)), 0, 0, 0, 0, 0, 0), _curveNode1);

        curveNode2 = _curveNode2;
        emit SetCurveNode2(CurveNode(ICurvePool(address(0)), 0, 0, 0, 0, 0, 0), _curveNode2);

        maxAllowedDeviation = _maxAllowedDeviation;
        emit SetMaxAllowedDeviation(0, _maxAllowedDeviation);

        _validateChainlinkParams(_chainlinkNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode);
    }

    /// @inheritdoc IAltoPxEthLendingOracleBase
    function getPrice() public view returns (uint256) {
        // get the balances of assets in pool  without admin balances
        uint256[] memory balancesInPool1 = ICurvePool(curveNode1.pool).get_balances();
        uint256[] memory balancesInPool2 = ICurvePool(curveNode2.pool).get_balances();

        // validates that the liquidity pool has enough liquidity as defined
        for (uint256 i = 0; i < balancesInPool1.length; i++) {
            if (balancesInPool1[i] < minAllowedLiquidityPool1[i]) {
                revert AltoPxEthLendingOracleInsufficientLiquidity();
            }
        }
        for (uint256 i = 0; i < balancesInPool2.length; i++) {
            if (balancesInPool2[i] < minAllowedLiquidityPool2[i]) {
                revert AltoPxEthLendingOracleInsufficientLiquidity();
            }
        }

        // gets the price from both curve pools
        // the price is in curveNode1.outDecimals
        uint256 pxEthPricePool1 = readCurvePool(10 ** curveNode1.inDecimals, curveNode1);
        uint256 pxEthPricePool2 = readCurvePool(10 ** curveNode2.inDecimals, curveNode2);

        // validates that the price from both curve pools is within the allowed deviation
        if (!OracleValidation.isPriceWithinAllowedDeviation(pxEthPricePool1, pxEthPricePool2, maxAllowedDeviation)) {
            revert AltoPxEthLendingOracleInvalidPrice();
        }

        // gets the price of eth in usd from chainlink
        // the price is in chainlinkNode.outDecimals
        uint256 ethUsdChainlinkPrice = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
        // converts the price from chainlinkNode.outDecimals to MATH_PRECISION
        uint256 ethUsdPrice = FixedPointMath.divideWithRounding(
            ethUsdChainlinkPrice, MATH_PRECISION, 10 ** chainlinkNode.outDecimals, false
        );

        // calculates the average price from both curve pools
        // the price is in curveNode1.outDecimals
        uint256 averagePxEthPriceFromPool = (pxEthPricePool1 + pxEthPricePool2) / 2;

        // converts the price from curveNode1.outDecimals to MATH_PRECISION
        averagePxEthPriceFromPool = FixedPointMath.divideWithRounding(
            averagePxEthPriceFromPool, MATH_PRECISION, 10 ** curveNode1.outDecimals, false
        );

        // calculates the price of pxeth in usd
        // the price is in ORACLE_PRICE_PRECISION(i.e. 1e36) because
        // averagePxEthPriceFromPool is in 18 decimals and ethUsdPrice is in 18 decimals
        uint256 pxEthUsdPrice = averagePxEthPriceFromPool * ethUsdPrice;

        return pxEthUsdPrice;
    }

    /// @inheritdoc IAltoPxEthLendingOracleBase
    function updateCurveNode(bool _isNode1, CurveNode memory _curveNode1, bool _isNode2, CurveNode memory _curveNode2)
        public
        onlyOwner
    {
        if (_isNode1) {
            emit SetCurveNode1(curveNode1, _curveNode1);
            curveNode1 = _curveNode1;
        } else if (_isNode2) {
            emit SetCurveNode2(curveNode2, _curveNode2);
            curveNode2 = _curveNode2;
        }

        if (curveNode1.outDecimals != curveNode2.outDecimals) {
            revert AltoPxEthLendingOracleInvalidInput();
        }
    }

    /// @inheritdoc IAltoPxEthLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) public onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }

    /// @inheritdoc IAltoPxEthLendingOracleBase
    function updateMaxAllowedDeviation(uint256 _maxAllowedDeviation) public onlyOwner {
        emit SetMaxAllowedDeviation(maxAllowedDeviation, _maxAllowedDeviation);
        maxAllowedDeviation = _maxAllowedDeviation;
    }

    /// @inheritdoc IAltoPxEthLendingOracleBase
    function updateMinAllowedLiquidityPoo1(bool _isForPool1, uint256[] memory _minAllowedLiquidityPool)
        public
        onlyOwner
    {
        if (_isForPool1) {
            emit SetMinAllowedLiquidityPool1(minAllowedLiquidityPool1, _minAllowedLiquidityPool);
            minAllowedLiquidityPool1 = _minAllowedLiquidityPool;
        } else {
            emit SetMinAllowedLiquidityPool2(minAllowedLiquidityPool2, _minAllowedLiquidityPool);
            minAllowedLiquidityPool2 = _minAllowedLiquidityPool;
        }
    }
}
