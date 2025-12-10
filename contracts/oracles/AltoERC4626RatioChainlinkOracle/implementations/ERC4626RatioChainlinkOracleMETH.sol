// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IMethStaking {
    function mETHToETH(uint256 _mETHAmount) external view returns (uint256);
}

/// @title ERC4626RatioChainlinkOracleMETH
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An oracle that gets the price of mETH using the ERC4626 ratio of mETH to ETH and Chainlink price feed
contract ERC4626RatioChainlinkOracleMETH is AltoERC4626RatioChainlinkOracle {
    /// @notice The address of the mETH staking contract
    address public immutable METH_STAKING;

    /// @notice Error thrown when the input is invalid
    error ERC4626RatioChainlinkOracleMETHInvalidInput();

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _methStaking The address of the mETH staking contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The Chainlink node
    constructor(
        address _owner,
        address _methStaking,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_methStaking == address(0)) {
            revert ERC4626RatioChainlinkOracleMETHInvalidInput();
        }

        METH_STAKING = _methStaking;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return IMethStaking(METH_STAKING).mETHToETH(1 ether);
    }
}
