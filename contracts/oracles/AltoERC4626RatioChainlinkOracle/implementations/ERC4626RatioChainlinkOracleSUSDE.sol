// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626RatioChainlinkOracleSUSDE
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An oracle that gets the price of SUSDE using the ERC4626 ratio of SUSDE to ETH and Chainlink price feed
contract ERC4626RatioChainlinkOracleSUSDE is AltoERC4626RatioChainlinkOracle {
    /// @notice The address of the SUSDE contract
    address public immutable SUSDE;

    /// @notice Error thrown when the input is invalid
    error ERC4626RatioChainlinkOracleSUSDEInvalidInput();

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _susde The address of the SUSDE contract
    /// @param _erc4626RatioNode The ERC4626 ratio node
    /// @param _chainlinkNode The Chainlink node
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
