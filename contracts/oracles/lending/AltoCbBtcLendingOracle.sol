// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ModuleChainlink} from "@alto/oracles/lending/modules/ModuleChainlink.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IAltoCbBtcLendingOracleStaticTypes,
    IAltoCbBtcLendingOracleBase
} from "@alto/oracles/interfaces/IAltoCbBtcLendingOracle.sol";

/// @title AltoCbBtcLendingOracle
/// @author Pearl Labs
/// @notice Oracle contract that is used to get the price of cbBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
/// @dev assumes that the invariant of cbBTC pegged to BTC always holds
contract AltoCbBtcLendingOracle is Ownable2Step, ModuleChainlink, IAltoCbBtcLendingOracleStaticTypes {
    /// @inheritdoc IAltoCbBtcLendingOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNode The chainlink node configuration
    constructor(address _owner, ChainlinkNode memory _chainlinkNode) Ownable(_owner) {
        _validateChainlinkParams(_chainlinkNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(ChainlinkNode(AggregatorV3Interface(address(0)), 0, 0, 0, 0), _chainlinkNode);
    }

    /// @inheritdoc IAltoCbBtcLendingOracleBase
    function getPrice() external view returns (uint256) {
        // fetches the price of BTC in USD from chainlink in chainlinkNode.outDecimals decimals
        uint256 chainlinkPrice = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);

        // converts the price from chainlinkNode.outDecimals to ORACLE_PRICE_PRECISION
        uint256 price = FixedPointMath.divideWithRounding(
            chainlinkPrice, ORACLE_PRICE_PRECISION, 10 ** chainlinkNode.outDecimals, false
        );
        // decimals of cbBTC is 8, so we need to multiply by 1e10 to price it in DUSD(18 decimals)
        return price * 1e10;
    }

    /// @inheritdoc IAltoCbBtcLendingOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }
}
