// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioChainlinkOracle} from "../AltoERC4626RatioChainlinkOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626RatioChainlinkOracleSUSDS
/// @author GPM
/// @notice An oracle that gets the price of sUSDS using the ERC4626 ratio of sUSDS to its underlying and a Chainlink feed
contract ERC4626RatioChainlinkOracleSUSDS is AltoERC4626RatioChainlinkOracle {
    /// @notice The address of the sUSDS ERC4626 vault
    address public immutable SUSDS;

    /// @notice Thrown when constructor arguments are invalid
    error ERC4626RatioChainlinkOracleSUSDSInvalidInput();

    /// @param _owner Owner of the oracle
    /// @param _susds Address of the sUSDS vault
    /// @param _erc4626RatioNode Ratio node configuration
    /// @param _chainlinkNode Chainlink node configuration
    constructor(
        address _owner,
        address _susds,
        ERC4626RatioNode memory _erc4626RatioNode,
        ChainlinkNode memory _chainlinkNode
    ) AltoERC4626RatioChainlinkOracle(_owner, _erc4626RatioNode, _chainlinkNode) {
        if (_susds == address(0)) {
            revert ERC4626RatioChainlinkOracleSUSDSInvalidInput();
        }
        SUSDS = _susds;
    }

    /// @inheritdoc AltoERC4626RatioChainlinkOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return IERC4626(SUSDS).convertToAssets(1 ether);
    }
}

