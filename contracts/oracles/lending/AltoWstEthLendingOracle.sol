// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/lending/modules/ModuleERC4626Ratio.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {
    ChainlinkNode,
    RedstoneNode,
    ERC4626RatioNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IWstEth} from "@alto/oracles/interfaces/IWstEth.sol";
import {
    IAltoWstEthLendingOracleStaticTypes,
    IAltoWstEthLendingOracleBase
} from "@alto/oracles/interfaces/IAltoWstEthLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @title AltoWstEthLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of WSTETH in USD
/// @dev Uses ERC4626Ratio to cap the ratio of wsteth/steth and chainlink ETH/USD feed
/// @dev also checks the max allowed deviation with redstone WSTETH/USD feed
/// @dev this contract uses the invariant that stEth and Eth is pegged at 1:1
contract AltoWstEthLendingOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    ModuleRedstone,
    IAltoWstEthLendingOracleStaticTypes
{
    /// @inheritdoc IAltoWstEthLendingOracleBase
    address public immutable WSTETH;

    /// @inheritdoc IAltoWstEthLendingOracleBase
    uint256 public maxAllowedDeviation;

    /// @inheritdoc IAltoWstEthLendingOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoWstEthLendingOracleStaticTypes
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @inheritdoc IAltoWstEthLendingOracleStaticTypes
    RedstoneNode public redstoneNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _wstEth The address of the WSTETH token
    /// @param _maxAllowedDeviation The maximum allowed deviation between the chainlink and redstone prices
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @param _chainlinkRedstoneNode The chainlink redstone node configuration
    /// @param _redstoneNode The redstone node configuration
    constructor(
        address _owner,
        address _wstEth,
        uint256 _maxAllowedDeviation,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkRedstoneNode memory _chainlinkRedstoneNode,
        RedstoneNode memory _redstoneNode
    ) Ownable(_owner) {
        if (_maxAllowedDeviation == 0 || _maxAllowedDeviation > MATH_PRECISION) {
            revert AltoWstEthLendingOracleInvalidInput();
        }
        if (_wstEth == address(0)) {
            revert AltoWstEthLendingOracleInvalidInput();
        }
        // validates whether the chainlink and redstone node have the same out decimals
        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoWstEthLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoWstEthLendingOracleInvalidInput();
        }

        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoWstEthLendingOracleInvalidInput();
        }
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);
        _validateRedstoneParams(_redstoneNode);

        WSTETH = _wstEth;

        maxAllowedDeviation = _maxAllowedDeviation;
        emit SetMaxAllowedDeviation(0, _maxAllowedDeviation);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

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

        redstoneNode = _redstoneNode;
        emit SetRedstoneNode(RedstoneNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _redstoneNode);
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function getPrice() external view returns (uint256) {
        // getting the latest ratio of wsteth/steth.
        uint256 stEthPerWstEthWad = IWstEth(WSTETH).stEthPerToken();

        // the ratio returned may be capped to the maximum allowed growth rate
        uint256 wstEthStEthRatioWad = readLatestRatio(stEthPerWstEthWad, erc4626RatioNode);

        // getting the price of eth in usd from chainlink and redstone in chainlinkNode.outDecimals decimals
        // the chainlink price and redstone price will be in chainlinkNode.outDecimals
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
            revert AltoWstEthLendingOracleInvalidPrice();
        } else {
            // calculates the weighted average of the chainlink and redstone prices
            // the decimals of price will be in chainlinkRedstoneNode.chainlinkNode.outDecimals
            ethUsdPrice = (
                ethUsdChainlinkPrice * chainlinkRedstoneNode.chainlinkWeightWad
                    + ethUsdRedstonePrice * chainlinkRedstoneNode.redstoneWeightWad
            ) / MATH_PRECISION;
        }

        // converts the ethUsd price from chainlinkNode.outDecimals to MATH_PRECISION(i.e. 1e18) decimals
        ethUsdPrice = FixedPointMath.divideWithRounding(
            ethUsdPrice, MATH_PRECISION, 10 ** chainlinkRedstoneNode.chainlinkNode.outDecimals, false
        );

        // calculates the price of wsteth in usd from fundamental rate in ORACLE_PRICE_PRECISION(i.e. 1e36) decimals
        // wstEthStEthRatioWad is in MATH_PRECISION(i.e. 1e18) decimals and ethUsdPrice is in MATH_PRECISION(i.e. 1e18) decimals
        uint256 wstEthUsdPriceFundamentalRate = wstEthStEthRatioWad * ethUsdPrice;

        // getting the price of wsteth in usd from redstone in redstoneNode.outDecimals decimals
        uint256 wstEthUsdRedstonePrice = readRedstoneFeed(10 ** redstoneNode.inDecimals, redstoneNode);

        // converts the wstEthUsdRedstonePrice from redstoneNode.outDecimals to ORACLE_PRICE_PRECISION(i.e. 1e36) decimals
        wstEthUsdRedstonePrice = FixedPointMath.divideWithRounding(
            wstEthUsdRedstonePrice, ORACLE_PRICE_PRECISION, 10 ** redstoneNode.outDecimals, false
        );

        // validates that the price from chainlink and redstone is within the allowed deviation
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                wstEthUsdPriceFundamentalRate, wstEthUsdRedstonePrice, maxAllowedDeviation
            )
        ) {
            revert AltoWstEthLendingOracleInvalidPrice();
        }

        return wstEthUsdPriceFundamentalRate;
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);

        // validates whether the chainlink and redstone node have the same out decimals
        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoWstEthLendingOracleInvalidInput();
        }

        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoWstEthLendingOracleInvalidInput();
        }

        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoWstEthLendingOracleInvalidInput();
        }

        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateRedstoneNode(RedstoneNode memory _redstoneNode) external onlyOwner {
        _validateRedstoneParams(_redstoneNode);

        emit SetRedstoneNode(redstoneNode, _redstoneNode);
        redstoneNode = _redstoneNode;
    }

    /// @inheritdoc IAltoWstEthLendingOracleBase
    function updateMaxAllowedDeviation(uint256 _maxAllowedDeviation) external onlyOwner {
        if (_maxAllowedDeviation == 0 || _maxAllowedDeviation > MATH_PRECISION) {
            revert AltoWstEthLendingOracleInvalidInput();
        }
        emit SetMaxAllowedDeviation(maxAllowedDeviation, _maxAllowedDeviation);
        maxAllowedDeviation = _maxAllowedDeviation;
    }
}
