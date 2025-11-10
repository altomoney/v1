// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
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
contract AltoTbtcLendingOracle is Ownable2Step, ModuleChainlink, IAltoTbtcLendingOracleStaticTypes {
    /// @inheritdoc IAltoTbtcLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNode The chainlink node configuration
    constructor(address _owner, ChainlinkNode memory _chainlinkNode) Ownable(_owner) {
        _validateChainlinkParams(_chainlinkNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0), _chainlinkNode
        );
    }

    /// @inheritdoc IAltoTbtcLendingOracleBase
    function getPrice() external view returns (uint256) {
        return readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
    }

    /// @inheritdoc IAltoTbtcLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);
        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
