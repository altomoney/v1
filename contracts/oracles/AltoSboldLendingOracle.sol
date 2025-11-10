// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {CurveNode, ChainlinkNode, ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ModuleCurve} from "@alto/oracles/modules/ModuleCurve.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {
    IAltoSboldLendingOracleStaticTypes,
    IAltoSboldLendingOracleBase
} from "@alto/oracles/interfaces/IAltoSboldLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoSboldLendingOracle
/// @author Pearl Labs
/// @notice An oracle that gets the price of SBOLD in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
/// @dev uses the SBOLD -> BOLD fundamental ratio. Uses ERC4626 ratio to cap the ratio of SBOLD/BOLD at max allowed ratio
/// @dev uses the curve pool to get the price of BOLD in USDC
/// @dev uses the chainlink and redstone USDC/USD price feed to get the price of USDC in USD
contract AltoSboldLendingOracle is
    Ownable2Step,
    ModuleCurve,
    ModuleChainlink,
    ModuleERC4626Ratio,
    IAltoSboldLendingOracleStaticTypes
{
    /// @inheritdoc IAltoSboldLendingOracleBase
    address public immutable SBOLD;

    /// @inheritdoc IAltoSboldLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoSboldLendingOracleStaticTypes
    CurveNode public curveNode;

    /// @inheritdoc IAltoSboldLendingOracleStaticTypes
    uint256[] public minAllowedLiquidityPool;

    /// @inheritdoc IAltoSboldLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _sbold The address of the SBOLD token
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @param _curveNode The curve node configuration
    /// @param _minAllowedLiquidityPool The minimum allowed liquidity pool
    /// @param _chainlinkNode The chainlink node config
    constructor(
        address _owner,
        address _sbold,
        ERC4626RatioNode memory _erc4626RatioNode,
        CurveNode memory _curveNode,
        uint256[] memory _minAllowedLiquidityPool,
        ChainlinkNode memory _chainlinkNode
    ) Ownable(_owner) {
        if (_sbold == address(0)) {
            revert AltoSboldLendingOracleInvalidInput();
        }

        if (_minAllowedLiquidityPool.length == 0) {
            revert AltoSboldLendingOracleInvalidInput();
        }

        if (_chainlinkNode.outDecimals != 18) {
            revert AltoSboldLendingOracleInvalidInput();
        }

        SBOLD = _sbold;
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateCurveParams(_curveNode);
        _validateChainlinkParams(_chainlinkNode);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        curveNode = _curveNode;
        emit SetCurveNode(CurveNode(ICurvePool(address(0)), 0, 0, 0, 0, 0, 0), _curveNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);

        minAllowedLiquidityPool = _minAllowedLiquidityPool;
        emit SetMinAllowedLiquidityPool(new uint256[](0), _minAllowedLiquidityPool);
    }

    /// @inheritdoc IAltoSboldLendingOracleBase
    function getPrice() external view returns (uint256) {
        // gets the ratio of SBOLD to BOLD
        uint256 sboldBoldRatio = IERC4626(SBOLD).convertToAssets(10 ** IERC20Metadata(SBOLD).decimals());

        // caps the bold amount to the maximum allowed growth rate
        uint256 boldAmount = readLatestRatio(sboldBoldRatio, erc4626RatioNode);

        // gets the balances of assets in the curve pool
        uint256[] memory balancesInPool = ICurvePool(curveNode.pool).get_balances();

        // validates that the liquidity pool has enough liquidity as defined
        for (uint256 i = 0; i < balancesInPool.length; i++) {
            if (balancesInPool[i] < minAllowedLiquidityPool[i]) {
                revert AltoSboldLendingOracleInsufficientLiquidity();
            }
        }

        // gets the price of sBOLD in USDC
        // this will be in curveNode.outdecimals decimals
        uint256 sboldUsdcPrice = readCurvePool(boldAmount, curveNode);

        // converts the price from curveNode.outdecimals to MATH_PRECISION(i.e. 1e18) decimals
        sboldUsdcPrice =
            FixedPointMath.divideWithRounding(sboldUsdcPrice, MATH_PRECISION, 10 ** curveNode.outDecimals, false);

        // gets the price of USDC in USD from chainlink
        // this will be in chainlinkNode.outdecimals decimals
        uint256 usdcUsdChainlinkPrice = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);

        // calculates the price of SBOLD in USD in ORACLE_PRICE_PRECISION(i.e. 1e36) decimals
        // boldUsdcPrice is in MATH_PRECISION(i.e. 1e18) decimals and usdcUsdPrice is in MATH_PRECISION(i.e. 1e18) decimals
        uint256 sboldUsdPrice = sboldUsdcPrice * usdcUsdChainlinkPrice;

        return sboldUsdPrice;
    }

    /// @inheritdoc IAltoSboldLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoSboldLendingOracleBase
    function updateCurveNode(CurveNode memory _curveNode) external onlyOwner {
        _validateCurveParams(_curveNode);

        emit SetCurveNode(curveNode, _curveNode);
        curveNode = _curveNode;
    }

    /// @inheritdoc IAltoSboldLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
