// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ModuleRedstone} from "@alto/oracles/lending/modules/ModuleRedstone.sol";
import {ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IAltoTbtcLendingOracleStaticTypes,
    IAltoTbtcLendingOracleBase
} from "@alto/oracles/interfaces/IAltoTbtcLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoTbtcLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of tBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
/// @dev assumes that the invariant of tBTC pegged to BTC alwaus holds
contract AltoTbtcLendingOracle is Ownable2Step, ModuleChainlink, ModuleRedstone, IAltoTbtcLendingOracleStaticTypes {
    /// @inheritdoc IAltoTbtcLendingOracleStaticTypes
    ChainlinkRedstoneNode public chainlinkRedstoneNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkRedstoneNode The chainlink and redstone node configuration
    constructor(address _owner, ChainlinkRedstoneNode memory _chainlinkRedstoneNode) Ownable(_owner) {
        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoTbtcLendingOracleInvalidInput();
        }

        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoTbtcLendingOracleInvalidInput();
        }
        // validates whether the chainlink and redstone node have the same in and out decimals
        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoTbtcLendingOracleInvalidInput();
        }

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

    /// @inheritdoc IAltoTbtcLendingOracleBase
    function getPrice() external view returns (uint256) {
        // fetches the price of BTC in USD from chainlink and redstone in chainlinkNode.outDecimals decimals
        // the chainlink price and redstone price will be in chainlinkNode.outDecimals
        uint256 chainlinkPrice =
            readChainlinkFeed(10 ** chainlinkRedstoneNode.chainlinkNode.inDecimals, chainlinkRedstoneNode.chainlinkNode);
        uint256 redstonePrice =
            readRedstoneFeed(10 ** chainlinkRedstoneNode.redstoneNode.inDecimals, chainlinkRedstoneNode.redstoneNode);

        uint256 price;
        // checks whether the price from chainlink and redstone is within the allowed deviation
        if (
            !OracleValidation.isPriceWithinAllowedDeviation(
                chainlinkPrice, redstonePrice, chainlinkRedstoneNode.maxAllowedDeviationWad
            )
        ) {
            revert AltoTbtcLendingOracleInvalidPrice();
        } else {
            // uses weighted average of the chainlink and redstone prices
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

    /// @inheritdoc IAltoTbtcLendingOracleBase
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkRedstoneNode.chainlinkNode);
        _validateRedstoneParams(_chainlinkRedstoneNode.redstoneNode);
        if (_chainlinkRedstoneNode.chainlinkWeightWad + _chainlinkRedstoneNode.redstoneWeightWad != MATH_PRECISION) {
            revert AltoTbtcLendingOracleInvalidInput();
        }
        if (
            _chainlinkRedstoneNode.maxAllowedDeviationWad == 0
                || _chainlinkRedstoneNode.maxAllowedDeviationWad > MATH_PRECISION
        ) {
            revert AltoTbtcLendingOracleInvalidInput();
        }
        // validates whether the chainlink and redstone node have the same out decimals
        if (_chainlinkRedstoneNode.chainlinkNode.outDecimals != _chainlinkRedstoneNode.redstoneNode.outDecimals) {
            revert AltoTbtcLendingOracleInvalidInput();
        }
        emit SetChainlinkRedstoneNode(chainlinkRedstoneNode, _chainlinkRedstoneNode);
        chainlinkRedstoneNode = _chainlinkRedstoneNode;
    }
}
