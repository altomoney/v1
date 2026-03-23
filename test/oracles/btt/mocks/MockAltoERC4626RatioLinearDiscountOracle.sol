// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {
    AltoERC4626RatioLinearDiscountOracle
} from "@alto/oracles/AltoERC4626RatioLinearDiscountOracle/AltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

contract MockAltoERC4626RatioLinearDiscountOracle is AltoERC4626RatioLinearDiscountOracle {
    uint256 private ratio;

    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        LinearDiscountNode memory _linearDiscountNode,
        uint256 _ratio
    ) AltoERC4626RatioLinearDiscountOracle(_owner, _erc4626RatioNode, _linearDiscountNode) {
        ratio = _ratio;
    }

    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return ratio;
    }

    function setRatio(uint256 _ratio) external {
        ratio = _ratio;
    }
}
