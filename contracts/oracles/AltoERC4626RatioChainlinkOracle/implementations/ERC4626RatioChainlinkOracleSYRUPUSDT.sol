// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ISyrupAsset} from "@alto/deployments/interfaces/ISyrupAsset.sol";

/// @title ERC4626RatioChainlinkOracleSYRUPUSDT
/// @notice An oracle that gets the price of SyrupUSDT using the ERC4626 ratio and a Chainlink feed
contract ERC4626RatioChainlinkOracleSYRUPUSDT is AltoERC4626RatioChainlinkOracle {
    /// @notice SyrupUSDT ERC4626 vault
    address public immutable SYRUP_USDT;

    /// @notice Thrown when constructor args are invalid
    error ERC4626RatioChainlinkOracleSYRUPUSDTInvalidInput();

    /// @param _owner Owner of the oracle
    /// @param _syrupUsdt Address of the SyrupUSDT vault
    /// @param _erc4626RatioNode Ratio node config
    /// @param _chainlinkNode Chainlink node config
    constructor(
        address _owner,
        address _syrupUsdt,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_syrupUsdt == address(0)) {
            revert ERC4626RatioChainlinkOracleSYRUPUSDTInvalidInput();
        }
        SYRUP_USDT = _syrupUsdt;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        // SYRUP_USDT vault has 6 decimals
        return ISyrupAsset(SYRUP_USDT).convertToExitAssets(1e6);
    }
}

