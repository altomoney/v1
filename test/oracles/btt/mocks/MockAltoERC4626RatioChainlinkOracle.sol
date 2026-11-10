// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {
    AltoERC4626RatioChainlinkOracle
} from "@alto/oracles/AltoERC4626RatioChainlinkOracle/AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract MockAltoERC4626RatioChainlinkOracle is AltoERC4626RatioChainlinkOracle {
    uint256 ratio;

    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode,
        uint256 _ratio
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        ratio = _ratio;
    }

    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return ratio;
    }

    function setRatio(uint256 _ratio) external {
        ratio = _ratio;
    }
}
