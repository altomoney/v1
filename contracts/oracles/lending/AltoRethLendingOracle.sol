// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {
    ERC4626RatioNode,
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IAltoRethLendingOracleStaticTypes,
    IAltoRethLendingOracleBase
} from "@alto/oracles/interfaces/IAltoRethLendingOracle.sol";
import {IReth} from "@alto/oracles/interfaces/IReth.sol";

/// @title AltoRethLendingOracle
/// @author Pearl Labs
/// @notice An oracle that gets the price of RETH in USD using the ERC4626 ratio of RETH to ETH and chainlink and redstone ETH/USD price feed
contract AltoRethLendingOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    ModuleRedstone,
    IAltoRethLendingOracleStaticTypes
{
    /// @inheritdoc IAltoRethLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoRethLendingOracleStaticTypes
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @inheritdoc IAltoRethLendingOracleBase
    address public immutable RETH;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkRedstoneNode The chainlink and redstone node
    /// @param _reth The address of the RETH token
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkRedstoneNode memory _chainlinkRedstoneNode,
        address _reth
    ) Ownable(_owner) {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoRethLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoRethLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoRethLendingOracleInvalidInput();
        }

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
        if (_reth == address(0)) {
            revert AltoRethLendingOracleInvalidInput();
        }
        RETH = _reth;
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function getPrice() external view returns (uint256) {
        // gets the ratio of RETH to ETH in 18 decimals
        uint256 rETHToETHRatio = IReth(RETH).getExchangeRate();

        // the ratio returned may be capped to the maximum allowed growth rate
        rETHToETHRatio = readLatestRatio(rETHToETHRatio, erc4626RatioNode);

        // gets the price of ETH in USD from chainlink and redstone in chainlinkNode.outDecimals decimals
        uint256 ethUsdPriceChainlink =
            readChainlinkFeed(10 ** chainlinkRedstoneNode.chainlinkNode.inDecimals, chainlinkRedstoneNode.chainlinkNode);
        uint256 ethUsdPriceRedstone =
            readRedstoneFeed(10 ** chainlinkRedstoneNode.redstoneNode.inDecimals, chainlinkRedstoneNode.redstoneNode);

        uint256 ethUsdPrice;
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                ethUsdPriceChainlink, ethUsdPriceRedstone, chainlinkRedstoneNode.maxAllowedDeviationWad
            )
        ) {
            revert AltoRethLendingOracleInvalidPrice();
        } else {
            // calculates the weighted average of the chainlink and redstone prices
            // the decimals of price will be in chainlinkRedstoneNode.chainlinkNode.outDecimals
            ethUsdPrice = (
                ethUsdPriceChainlink * chainlinkRedstoneNode.chainlinkWeightWad
                    + ethUsdPriceRedstone * chainlinkRedstoneNode.redstoneWeightWad
            ) / MATH_PRECISION;
        }

        // converts the price from chainlinkRedstoneNode.chainlinkNode.outDecimals to MATH_PRECISION
        ethUsdPrice = FixedPointMath.divideWithRounding(
            ethUsdPrice, MATH_PRECISION, 10 ** chainlinkRedstoneNode.chainlinkNode.outDecimals, false
        );

        // calculates the price of RETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36) decimals
        // rETHToETHRatio is in MATH_PRECISION(i.e. 1e18) decimals and ethUsdPrice is in MATH_PRECISION(i.e. 1e18) decimals
        uint256 rETHUsdPrice = rETHToETHRatio * ethUsdPrice;

        return rETHUsdPrice;
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoRethLendingOracleBase
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoRethLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoRethLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoRethLendingOracleInvalidInput();
        }

        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
    }
}
