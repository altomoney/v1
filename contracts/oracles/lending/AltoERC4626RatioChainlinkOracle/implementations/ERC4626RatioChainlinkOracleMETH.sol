// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IMethStaking {
    function mETHToETH(uint256 _mETHAmount) external view returns (uint256);
}

contract ERC4626RatioChainlinkOracleMETH is AltoERC4626RatioChainlinkOracle {
    address public immutable METH_STAKING;

    error ERC4626RatioChainlinkOracleMETHInvalidInput();

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
