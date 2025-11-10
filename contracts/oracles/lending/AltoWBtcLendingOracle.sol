// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {
    IAltoWbtcLendingOracleStaticTypes,
    IAltoWbtcLendingOracleBase
} from "@alto/oracles/interfaces/IAltoWbtcLendingOracle.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title AltoWBtcLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of WBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
contract AltoWBtcLendingOracle is Ownable2Step, ModuleChainlink, IAltoWbtcLendingOracleStaticTypes {
    /// @inheritdoc IAltoWbtcLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode1;

    /// @inheritdoc IAltoWbtcLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode2;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNode1 The chainlink node 1 configuration
    /// @param _chainlinkNode2 The chainlink node 2 configuration
    constructor(address _owner, ChainlinkNode memory _chainlinkNode1, ChainlinkNode memory _chainlinkNode2)
        Ownable(_owner)
    {
        _validateChainlinkParams(_chainlinkNode1);
        _validateChainlinkParams(_chainlinkNode2);

        chainlinkNode1 = _chainlinkNode1;
        emit SetChainlinkNode1(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode1);

        chainlinkNode2 = _chainlinkNode2;
        emit SetChainlinkNode2(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode2);
    }

    function getPrice() external view returns (uint256) {
        // fetches the ratio of WBTC to BTC from chainlink in chainlinkNode1.inDecimals decimals
        uint256 oneUnitWbtcInBtc = readChainlinkFeed(10 ** chainlinkNode1.inDecimals, chainlinkNode1);

        // fetches the price of BTC in USD from chainlink in chainlinkNode2.inDecimals decimals
        return readChainlinkFeed(oneUnitWbtcInBtc, chainlinkNode2);
    }

    /// @inheritdoc IAltoWbtcLendingOracleBase
    function updateChainlinkNode(uint256 _index, ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        if (_index == 1) {
            emit SetChainlinkNode1(chainlinkNode1, _chainlinkNode);
            chainlinkNode1 = _chainlinkNode;
        } else if (_index == 2) {
            emit SetChainlinkNode2(chainlinkNode2, _chainlinkNode);
            chainlinkNode2 = _chainlinkNode;
        } else {
            revert AltoWbtcLendingOracleInvalidInput();
        }
    }
}
