// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ERC4626RatioChainlinkOracleSUSDE is AltoERC4626RatioChainlinkOracle {
    address public immutable SUSDE;

    error ERC4626RatioChainlinkOracleSUSDEInvalidInput();

    constructor(
        address _owner,
        address _susde,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_susde == address(0)) {
            revert ERC4626RatioChainlinkOracleSUSDEInvalidInput();
        }

        SUSDE = _susde;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return IERC4626(SUSDE).convertToAssets(1 ether);
    }
}
