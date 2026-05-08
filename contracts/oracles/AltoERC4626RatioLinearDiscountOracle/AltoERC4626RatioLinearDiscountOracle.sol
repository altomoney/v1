// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ModuleERC4626Ratio} from "@alto/oracles/modules/ModuleERC4626Ratio.sol";
import {ModuleLinearDiscount} from "@alto/oracles/modules/ModuleLinearDiscount.sol";
import {
    IAltoERC4626RatioLinearDiscountOracleStaticTypes,
    IAltoERC4626RatioLinearDiscountOracleBase
} from "@alto/oracles/interfaces/IAltoERC4626RatioLinearDiscountOracle.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";

/// @title AltoERC4626RatioLinearDiscountOracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Abstract oracle that prices PT (Principal Token) positions backed by a yield-bearing asset.
/// @notice Combines two modules in sequence:
///   1. ModuleERC4626Ratio - caps the yield-bearing asset ratio to prevent manipulation impact.
///   2. ModuleLinearDiscount - applies a time-based discount to price the PT before maturity.
/// @dev Data flow for getPrice():
///   rawRatio  = _getRatioOfWrappedAssetToUnderlyingAsset()   (implementation-specific)
///   cappedRatio = readLatestRatio(rawRatio, erc4626RatioNode) (growth-capped ratio)
///   price       = readLinearDiscount(cappedRatio, linearDiscountNode) (discounted PT price)
/// @dev IMPORTANT: linearDiscountNode.inDecimals MUST match the decimals of the value returned
/// by _getRatioOfWrappedAssetToUnderlyingAsset(). This is implementation-specific - typically
/// 18 decimals for ERC4626 vaults using convertToAssets(1e18). There is no on-chain enforcement
/// because ERC4626RatioNode carries no outDecimals field
/// @custom:audit Pending
abstract contract AltoERC4626RatioLinearDiscountOracle is
    AltoOwnable2Step,
    ModuleERC4626Ratio,
    ModuleLinearDiscount,
    IAltoERC4626RatioLinearDiscountOracleStaticTypes
{
    /// @inheritdoc IAltoERC4626RatioLinearDiscountOracleStaticTypes
    ERC4626RatioNode public erc4626RatioNode;

    /// @inheritdoc IAltoERC4626RatioLinearDiscountOracleStaticTypes
    LinearDiscountNode public linearDiscountNode;

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _erc4626RatioNode Initial ERC4626 ratio node (initialRatio, initialTimestamp, maxYearlyGrowthRatioWad)
    /// @param _linearDiscountNode Initial linear discount node (maturity, baseDiscountPerYear, inDecimals, outDecimals)
    /// @dev _linearDiscountNode.inDecimals must match the decimals of _getRatioOfWrappedAssetToUnderlyingAsset()
    constructor(
        address _owner,
        ERC4626RatioNode memory _erc4626RatioNode,
        LinearDiscountNode memory _linearDiscountNode
    ) Ownable(_owner) {
        _validateERC4626RatioParams(_erc4626RatioNode);
        _validateLinearDiscountParams(_linearDiscountNode);

        erc4626RatioNode = _erc4626RatioNode;
        emit SetERC4626RatioNode(ERC4626RatioNode(0, 0, 0), _erc4626RatioNode);

        linearDiscountNode = _linearDiscountNode;
        emit SetLinearDiscountNode(LinearDiscountNode(address(0), 0, 0, 0, 0), _linearDiscountNode);
    }

    /// @inheritdoc IOracle
    function getPrice() external view returns (uint256) {
        uint256 ratio = _getRatioOfWrappedAssetToUnderlyingAsset();
        ratio = readLatestRatio(ratio, erc4626RatioNode);
        return readLinearDiscount(ratio, linearDiscountNode);
    }

    /// @inheritdoc IAltoERC4626RatioLinearDiscountOracleBase
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external onlyOwner {
        _validateERC4626RatioParams(_erc4626RatioNode);

        emit SetERC4626RatioNode(erc4626RatioNode, _erc4626RatioNode);
        erc4626RatioNode = _erc4626RatioNode;
    }

    /// @inheritdoc IAltoERC4626RatioLinearDiscountOracleBase
    function updateLinearDiscountNode(LinearDiscountNode memory _linearDiscountNode) external onlyOwner {
        _validateLinearDiscountParams(_linearDiscountNode);

        emit SetLinearDiscountNode(linearDiscountNode, _linearDiscountNode);
        linearDiscountNode = _linearDiscountNode;
    }

    /// @notice Returns the raw ratio of the yield-bearing asset to its underlying asset
    /// @return The ratio in implementation-specific units; decimals must match linearDiscountNode.inDecimals
    /// @dev Implemented by concrete contracts (e.g. IERC4626.convertToAssets(1e18), LST exchange rate)
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view virtual returns (uint256);
}
