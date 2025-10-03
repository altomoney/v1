// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleCurve} from "@alto/oracles/lending/modules/ModuleCurve.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {CurveNode, ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
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
/// @notice An oracle that gets the price of PXETH in USD using the curve and chainlink and redstone prices
/// @dev uses the average of curve pool PXETH/WETH and PXETH/STETH to get the price of PXETH in ETH. Assumes that steth is pegged to eth
/// @dev uses chainlink and redstone to get the price of ETH in USD
contract AltoPxEthLendingOracle is
    Ownable2Step,
    ModuleCurve,
    ModuleChainlink,
    ModuleRedstone,
    IAltoPxEthLendingOracleStaticTypes
{
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
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _curveNode1 The curve node for curve pool 1
    /// @param _minAllowedLiquidityPool1 The minimum allowed liquidity pool for curve pool 1
    /// @param _curveNode2 The curve node for curve pool 2
    /// @param _minAllowedLiquidityPool2 The minimum allowed liquidity pool for curve pool 2
    /// @param _maxAllowedDeviation The maximum allowed deviation
    /// @param _chainlinkRedstoneNode The chainlink and redstone node
    constructor(
        address _owner,
        CurveNode memory _curveNode1,
        uint256[] memory _minAllowedLiquidityPool1,
        CurveNode memory _curveNode2,
        uint256[] memory _minAllowedLiquidityPool2,
        uint256 _maxAllowedDeviation,
        ChainlinkRedstoneNode memory _chainlinkRedstoneNode
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

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoPxEthLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        // validates the chainlink node parameters
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        chainlinkRedstoneNode = _chainlinkRedstoneNode;
        emit SetChainlinkRedstoneNode(
            ChainlinkRedstoneNode(
                ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0),
                RedstoneNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0),
                0,
                0,
                0
            ),
            _chainlinkRedstoneNode
        );
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

        // gets the price of eth in usd from chainlink and redstone
        // the price is in chainlinkNode.outDecimals
        uint256 ethUsdChainlinkPrice =
            readChainlinkFeed(10 ** chainlinkRedstoneNode.chainlinkNode.inDecimals, chainlinkRedstoneNode.chainlinkNode);
        uint256 ethUsdRedstonePrice =
            readRedstoneFeed(10 ** chainlinkRedstoneNode.redstoneNode.inDecimals, chainlinkRedstoneNode.redstoneNode);

        uint256 ethUsdPrice;

        // returns the chainlink price if the price from chainlink and redstone is outside the allowed deviation
        // otherwise returns the weighted average of the chainlink and redstone prices
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                ethUsdChainlinkPrice, ethUsdRedstonePrice, chainlinkRedstoneNode.maxAllowedDeviationWad
            )
        ) {
            ethUsdPrice = ethUsdChainlinkPrice;
        } else {
            // calculates the weighted average of the chainlink and redstone prices
            // the decimals of price will be in chainlinkRedstoneNode.chainlinkNode.outDecimals
            ethUsdPrice = (
                ethUsdChainlinkPrice * chainlinkRedstoneNode.chainlinkWeightWad
                    + ethUsdRedstonePrice * chainlinkRedstoneNode.redstoneWeightWad
            ) / MATH_PRECISION;
        }

        // converts the price from chainlinkRedstoneNode.chainlinkNode.outDecimals to MATH_PRECISION
        ethUsdPrice = FixedPointMath.divideWithRounding(
            ethUsdPrice, MATH_PRECISION, 10 ** chainlinkRedstoneNode.chainlinkNode.outDecimals, false
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
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) public onlyOwner {
        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoPxEthLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoPxEthLendingOracleInvalidInput();
        }

        // validates the chainlink node parameters
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
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
