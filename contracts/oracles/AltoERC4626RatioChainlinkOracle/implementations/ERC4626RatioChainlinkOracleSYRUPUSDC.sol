// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ISyrupAsset
/// @notice Interface for Syrup assets that support exit asset conversion
interface ISyrupAsset {
    /// @notice Converts a given amount of shares to the equivalent exit assets
    /// @param shares The amount of shares to convert
    /// @return assets The equivalent amount of exit assets
    function convertToExitAssets(uint256 shares) external view returns (uint256 assets);
}

/// @title ERC4626RatioChainlinkOracleSYRUPUSDC
/// @notice An oracle that gets the price of SyrupUSDC using the ERC4626 ratio and a Chainlink feed
contract ERC4626RatioChainlinkOracleSYRUPUSDC is AltoERC4626RatioChainlinkOracle {
    /// @notice SyrupUSDC ERC4626 vault
    address public immutable SYRUP_USDC;

    /// @notice Thrown when constructor args are invalid
    error ERC4626RatioChainlinkOracleSYRUPUSDCInvalidInput();

    /// @param _owner Owner of the oracle
    /// @param _syrupUsdc Address of the SyrupUSDC vault
    /// @param _erc4626RatioNode Ratio node config
    /// @param _chainlinkNode Chainlink node config
    constructor(
        address _owner,
        address _syrupUsdc,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_syrupUsdc == address(0)) {
            revert ERC4626RatioChainlinkOracleSYRUPUSDCInvalidInput();
        }
        SYRUP_USDC = _syrupUsdc;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        // SYRUP_USDC vault has 6 decimals
        return ISyrupAsset(SYRUP_USDC).convertToExitAssets(1e6);
    }
}

