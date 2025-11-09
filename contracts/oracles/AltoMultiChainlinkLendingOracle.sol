// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {
    IAltoMultiChainlinkLendingOracleStaticTypes,
    IAltoMultiChainlinkLendingOracleBase,
    IAltoMultiChainlinkLendingOracleErrors
} from "@alto/oracles/interfaces/IAltoMultiChainlinkLendingOracle.sol";

/// @title AltoMultiChainlinkLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of the asset in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
/// @dev Uses the multiple chainlink nodes to get the price of the asset in USD
contract AltoMultiChainlinkLendingOracle is Ownable2Step, ModuleChainlink, IAltoMultiChainlinkLendingOracleStaticTypes {
    /// @inheritdoc IAltoMultiChainlinkLendingOracleStaticTypes
    ChainlinkNode[] public chainlinkNodes;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNodes The chainlink nodes configuration
    constructor(address _owner, ChainlinkNode[] memory _chainlinkNodes) Ownable(_owner) {
        if (_chainlinkNodes.length == 0) {
            revert AltoMultiChainlinkLendingOracleInvalidInput();
        }
        for (uint256 i = 0; i < _chainlinkNodes.length; i++) {
            _validateChainlinkParams(_chainlinkNodes[i]);
            chainlinkNodes.push(_chainlinkNodes[i]);
        }
        emit SetChainlinkNodes(new ChainlinkNode[](0), _chainlinkNodes);
    }

    /// @inheritdoc IAltoMultiChainlinkLendingOracleBase
    function getPrice() external view returns (uint256) {
        uint256 price = 10 ** chainlinkNodes[0].inDecimals;
        for (uint256 i = 0; i < chainlinkNodes.length; i++) {
            price = readChainlinkFeed(price, chainlinkNodes[i]);
        }
        return price;
    }

    /// @inheritdoc IAltoMultiChainlinkLendingOracleBase
    function updateChainlinkNodes(ChainlinkNode[] memory _chainlinkNodes) external onlyOwner {
        if (_chainlinkNodes.length == 0) {
            revert AltoMultiChainlinkLendingOracleInvalidInput();
        }
        emit SetChainlinkNodes(chainlinkNodes, _chainlinkNodes);
        delete chainlinkNodes;
        for (uint256 i = 0; i < _chainlinkNodes.length; i++) {
            _validateChainlinkParams(_chainlinkNodes[i]);
            chainlinkNodes.push(_chainlinkNodes[i]);
        }
    }
}
