// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IAltoCappedChainlinkOracleStaticTypes} from "@alto/oracles/interfaces/IAltoCappedChainlinkOracle.sol";

/// @title AltoCappedChainlinkOracle
/// @author GPM
/// @custom:contact security@altofoundation.org
contract AltoCappedChainlinkOracle is
    AltoOwnable2Step,
    ModuleChainlink,
    ModuleERC4626Ratio,
    IAltoCappedChainlinkOracleStaticTypes
{
    /// @inheritdoc IAltoCappedChainlinkOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @inheritdoc IAltoCappedChainlinkOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @param _owner The owner of the contract
    /// @param _chainlinkNode The Chainlink node configuration
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @dev The initialRatio must match the chainlink output decimals!
    constructor(address _owner, ChainlinkNode memory _chainlinkNode, ERC4626RatioNode memory _erc4626RatioNode)
        Ownable(_owner)
    {
        _validateChainlinkParams(_chainlinkNode);
        _validateERC4626RatioParams(_erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0, 0), _chainlinkNode
        );

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);
    }

    /// @inheritdoc IOracle
    function getPrice() external view returns (uint256) {
        uint256 price = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
        return readLatestRatio(price, erc4626RatioNode);
    }

    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }

    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }
}
