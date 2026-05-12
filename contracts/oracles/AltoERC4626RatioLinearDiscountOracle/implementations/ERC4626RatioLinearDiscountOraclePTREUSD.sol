// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioLinearDiscountOracle} from "../AltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ERC4626RatioLinearDiscountOraclePTREUSD
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice PT-reUSD oracle: linearly discounted 1:1 peg toward maturity, bounded by the ERC4626 ratio cap.
/// @dev The ratio is fixed at 1e6 (matching PT-reUSD's 6 decimals). At maturity 1 PT-reUSD = 1 DUSD.
/// The ERC4626 ratio cap acts as a safety ceiling only; it does not incorporate the reUSD NAV because
/// the PT market prices against the token peg, not the internal share price.
/// @dev linearDiscountNode.inDecimals must be set to 6 to match this ratio.
contract ERC4626RatioLinearDiscountOraclePTREUSD is AltoERC4626RatioLinearDiscountOracle {
    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode Initial ERC4626 ratio node (initialRatio, initialTimestamp, maxYearlyGrowthRatioWad)
    /// @param _linearDiscountNode Initial linear discount node (maturity, baseDiscountPerYear, inDecimals, outDecimals)
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        LinearDiscountNode memory _linearDiscountNode
    ) AltoERC4626RatioLinearDiscountOracle(_owner, _erc4626RatioNode, _linearDiscountNode) {}

    /// @inheritdoc AltoERC4626RatioLinearDiscountOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal pure override returns (uint256) {
        return 1e6;
    }
}
