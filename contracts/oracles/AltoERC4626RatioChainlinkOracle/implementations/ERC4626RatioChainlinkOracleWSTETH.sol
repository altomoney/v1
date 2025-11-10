// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IWstEth {
    function stEthPerToken() external view returns (uint256);
}

contract ERC4626RatioChainlinkOracleWSTETH is AltoERC4626RatioChainlinkOracle {
    address public immutable WSTETH;

    error ERC4626RatioChainlinkOracleWSTETHInvalidInput();

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
