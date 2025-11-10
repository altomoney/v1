// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    IAltoWethLendingOracleStaticTypes,
    IAltoWethLendingOracleBase
} from "@alto/oracles/interfaces/IAltoWethLendingOracle.sol";
import {IAltoWethLendingOracleErrors} from "@alto/oracles/interfaces/IAltoWethLendingOracle.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {OracleValidation} from "@alto/oracles/lending/libraries/OracleValidation.sol";

/// @title AltoWethLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of WETH in USD
/// @dev Uses Chainlink to get the price of WETH in USD from ETH/USD feed
contract AltoWethLendingOracle is Ownable2Step, ModuleChainlink, IAltoWethLendingOracleStaticTypes {
    /// @inheritdoc IAltoWethLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNode The chainlink node configuration
    constructor(address _owner, ChainlinkNode memory _chainlinkNode) Ownable(_owner) {
        // validating the chainlink node config
        _validateChainlinkParams(_chainlinkNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode);
    }

    /// @inheritdoc IAltoWethLendingOracleBase
    function getPrice() external view returns (uint256) {
        return readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
    }

    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);
        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
