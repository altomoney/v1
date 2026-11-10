// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IReth {
    function getExchangeRate() external view returns (uint256);
}

/// @title ERC4626RatioChainlinkOracleRETH
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An oracle that gets the price of RETH using the ERC4626 ratio of RETH to ETH and Chainlink price feed
contract ERC4626RatioChainlinkOracleRETH is AltoERC4626RatioChainlinkOracle {
    /// @notice The address of the RETH contract
    address public immutable RETH;

    /// @notice Error thrown when the input is invalid
    error ERC4626RatioChainlinkOracleRETHInvalidInput();

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _reth The address of the RETH contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The Chainlink node
    constructor(
        address _owner,
        address _reth,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_reth == address(0)) {
            revert ERC4626RatioChainlinkOracleRETHInvalidInput();
        }

        RETH = _reth;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return IReth(RETH).getExchangeRate();
    }
}
