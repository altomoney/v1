// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IWstEth {
    function stEthPerToken() external view returns (uint256);
}

/// @title ERC4626RatioChainlinkOracleWSTETH
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An oracle that gets the price of WSTETH using the ERC4626 ratio of WSTETH to stETH and Chainlink price feed
contract ERC4626RatioChainlinkOracleWSTETH is AltoERC4626RatioChainlinkOracle {
    /// @notice The address of the WSTETH contract
    address public immutable WSTETH;

    /// @notice Error thrown when the input is invalid
    error ERC4626RatioChainlinkOracleWSTETHInvalidInput();

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _wstEth The address of the WSTETH contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The Chainlink node
    constructor(
        address _owner,
        address _wstEth,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_wstEth == address(0)) {
            revert ERC4626RatioChainlinkOracleWSTETHInvalidInput();
        }

        WSTETH = _wstEth;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return IWstEth(WSTETH).stEthPerToken();
    }
}
