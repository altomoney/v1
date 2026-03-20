// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {
    ChainlinkNode,
    ERC4626RatioNode,
    MultiplierNode,
    ConversionDirection
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {ModuleMultiplier} from "@alto/oracles/modules/ModuleMultiplier.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IAltoChainlinkERC4626RatioMultiplierOracleStaticTypes
} from "@alto/oracles/interfaces/IAltoChainlinkERC4626RatioMultiplierOracle.sol";

/// @title AltoChainlinkERC4626RatioMultiplierOracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Oracle that pipelines three modules in sequence:
///         1. Chainlink  — converts 1 unit of input into an intermediate price
///         2. ERC4626 ratio — caps the intermediate price against a max allowed growth rate
///         3. Multiplier — scales the capped price by a fixed factor
/// @dev The out decimals of chainlink node should be the same as decimals of values used in initialRatio of erc4626RatioNode
contract AltoChainlinkERC4626RatioMultiplierOracle is
    AltoOwnable2Step,
    ModuleChainlink,
    ModuleERC4626Ratio,
    ModuleMultiplier,
    IAltoChainlinkERC4626RatioMultiplierOracleStaticTypes
{
    /// @inheritdoc IAltoChainlinkERC4626RatioMultiplierOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @inheritdoc IAltoChainlinkERC4626RatioMultiplierOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoChainlinkERC4626RatioMultiplierOracleStaticTypes
    MultiplierNode public multiplierNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _chainlinkNode The Chainlink node configuration
    /// @param _erc4626RatioNode The ERC4626 ratio node configuration
    /// @param _multiplierNode The multiplier node configuration
    constructor(
        address _owner,
        ChainlinkNode memory _chainlinkNode,
        ERC4626RatioNode memory _erc4626RatioNode,
        MultiplierNode memory _multiplierNode
    ) Ownable(_owner) {
        _validateChainlinkParams(_chainlinkNode);
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateMultiplierNode(_multiplierNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0, 0), _chainlinkNode
        );

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        multiplierNode = _multiplierNode;
        emit SetMultiplierNode(MultiplierNode(0), _multiplierNode);
    }

    /// @inheritdoc IOracle
    function getPrice() external view returns (uint256) {
        uint256 price = readChainlinkFeed(10 ** chainlinkNode.inDecimals, chainlinkNode);
        price = readLatestRatio(price, erc4626RatioNode);
        return readMultipliedInput(price, multiplierNode);
    }

    /// @notice Updates the Chainlink node
    /// @param _chainlinkNode The new Chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }

    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node configuration
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @notice Updates the multiplier node
    /// @param _multiplierNode The new multiplier node configuration
    function updateMultiplierNode(MultiplierNode memory _multiplierNode) external onlyOwner {
        _validateMultiplierNode(_multiplierNode);

        emit SetMultiplierNode(multiplierNode, _multiplierNode);
        multiplierNode = _multiplierNode;
    }
}
