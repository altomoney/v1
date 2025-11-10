// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {ModuleChainlink} from "@alto/oracles/modules/ModuleChainlink.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {
    IAltoERC4626RatioChainlinkOracleStaticTypes,
    IAltoERC4626RatioChainlinkOracleBase
} from "@alto/oracles/interfaces/IAltoERC4626RatioChainlinkOracle.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";

/// @title AltoERC4626RatioChainlinkOracle
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice An oracle that gets the price of a wrapped asset using the ERC4626 ratio of the wrapped asset
/// to the underlying asset and Chainlink price feed
abstract contract AltoERC4626RatioChainlinkOracle is
    Ownable2Step,
    ModuleERC4626Ratio,
    ModuleChainlink,
    IAltoERC4626RatioChainlinkOracleStaticTypes
{
    /// @inheritdoc IAltoERC4626RatioChainlinkOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoERC4626RatioChainlinkOracleStaticTypes
    ChainlinkNode public chainlinkNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The Chainlink node
    constructor(address _owner, ERC4626RatioNode memory _erc4626RatioNode, ChainlinkNode memory _chainlinkNode)
        Ownable(_owner)
    {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateChainlinkParams(_chainlinkNode);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        chainlinkNode = _chainlinkNode;
        emit SetChainlinkNode(
            ChainlinkNode(AggregatorV3Interface(address(0)), ConversionDirection.IN_TO_OUT, 0, 0, 0), _chainlinkNode
        );
    }

    /// @inheritdoc IOracle
    function getPrice() external view returns (uint256) {
        // gets the ratio of the wrapped asset to the underlying asset
        uint256 ratio = _getRatioOfWrappedAssetToUnderlyingAsset();

        // the ratio returned may be capped to the maximum allowed growth rate
        ratio = readLatestRatio(ratio, erc4626RatioNode);

        // gets the price of the wrapped asset from Chainlink in chainlinkNode.outDecimals decimals
        return readChainlinkFeed(ratio, chainlinkNode);
    }

    /// @inheritdoc IAltoERC4626RatioChainlinkOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoERC4626RatioChainlinkOracleBase
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external onlyOwner {
        _validateChainlinkParams(_chainlinkNode);

        emit SetChainlinkNode(chainlinkNode, _chainlinkNode);
        chainlinkNode = _chainlinkNode;
    }

    /// @notice Gets the ratio of the wrapped asset to the underlying asset
    /// @return The ratio of the wrapped asset to the underlying asset
    /// @dev This function is implemented in the child contract
    /// @dev This function is used to get the ratio of the wrapped asset to the underlying asset
    /// @dev For example, for wstETH, this function should return the ratio of wstETH to stETH
    /// by calling IwstEth.stEthPerToken()
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view virtual returns (uint256);
}
