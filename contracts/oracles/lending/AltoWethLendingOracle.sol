// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IAltoWethLendingOracleStaticTypes,
    IAltoWethLendingOracleBase
} from "@alto/oracles/interfaces/IAltoWethLendingOracle.sol";
import {IAltoWethLendingOracleErrors} from "@alto/oracles/interfaces/IAltoWethLendingOracle.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ChainlinkRedstoneNode, ChainlinkNode, RedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";

/// @title AltoWethLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of WETH in USD
/// @dev Uses Chainlink and Redstone to get the price of WETH in USD from ETH/USD feed and combines them using a weighted average

contract AltoWethLendingOracle is Ownable2Step, ModuleChainlink, ModuleRedstone, IAltoWethLendingOracleStaticTypes {
    /// @inheritdoc IAltoWethLendingOracleStaticTypes
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkRedstoneNode The chainlink and redstone node configuration
    constructor(address _owner, ChainlinkRedstoneNode memory _chainlinkRedstoneNode) Ownable(_owner) {
        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoWethLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoWethLendingOracleInvalidInput();
        }
        ChainlinkNode memory chainlinkNode = _chainlinkRedstoneNode.chainlinkNode;
        RedstoneNode memory redstoneNode = _chainlinkRedstoneNode.redstoneNode;
        // validating the chainlink node config
        _validateChainlinkParams(chainlinkNode);
        // validating the redstone node config
        _validateRedstoneParams(redstoneNode);

        // validates whether the chainlink and redstone node have the same out decimals
        if (chainlinkNode.outDecimals != redstoneNode.outDecimals) {
            revert AltoWethLendingOracleInvalidInput();
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
    }

    /// @inheritdoc IAltoWethLendingOracleBase
    function getPrice() external view returns (uint256) {
        // outDecimals are the same for chainlink and redstone nodes
        // the chainlink price and redstone price will be in chainlinkNode.outDecimals
        ChainlinkNode memory chainlinkNode = chainlinkRedstoneNode.chainlinkNode;
        RedstoneNode memory redstoneNode = chainlinkRedstoneNode.redstoneNode;

        uint256 chainlinkPrice = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
        uint256 redstonePrice = readRedstoneFeed(10 ** redstoneNode.inDecimals, redstoneNode);

        uint256 price;
        // returns the chainlink price if the price from chainlink and redstone is outside the allowed deviation
        // otherwise returns the weighted average of the chainlink and redstone prices
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                chainlinkPrice, redstonePrice, chainlinkRedstoneNode.maxAllowedDeviationWad
            )
        ) {
            revert AltoWethLendingOracleInvalidPrice();
        } else {
            // calculates the weighted average of the chainlink and redstone prices
            // the decimals of price will be in chainlinkNode.outDecimals
            price = (
                chainlinkPrice * chainlinkRedstoneNode.chainlinkWeightWad
                    + redstonePrice * chainlinkRedstoneNode.redstoneWeightWad
            ) / MATH_PRECISION;
        }
        // converts the price from chainlinkNode.outDecimals to ORACLE_PRICE_PRECISION
        price = FixedPointMath.divideWithRounding(
            price, ORACLE_PRICE_PRECISION, 10 ** chainlinkRedstoneNode.chainlinkNode.outDecimals, false
        );
        return price;
    }

    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external onlyOwner {
        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoWethLendingOracleInvalidInput();
        }

        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoWethLendingOracleInvalidInput();
        }

        ChainlinkNode memory chainlinkNode = _chainlinkRedstoneNode.chainlinkNode;
        RedstoneNode memory redstoneNode = _chainlinkRedstoneNode.redstoneNode;

        _validateChainlinkParams(chainlinkNode);
        _validateRedstoneParams(redstoneNode);

        if (chainlinkNode.outDecimals != redstoneNode.outDecimals) {
            revert AltoWethLendingOracleInvalidInput();
        }

        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
    }
}
