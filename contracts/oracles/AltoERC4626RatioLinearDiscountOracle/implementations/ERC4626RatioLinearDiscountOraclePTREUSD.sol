// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AltoERC4626RatioLinearDiscountOracle} from "../AltoERC4626RatioLinearDiscountOracle.sol";
import {ERC4626RatioNode, LinearDiscountNode} from "@alto/oracles/interfaces/IModuleNode.sol";

interface ISharePriceCalculator {
    /// @notice USD value of 1e18 reUSD shares
    /// @return Share price in 18 decimals (USD)
    function getSharePrice() external view returns (uint256);
}

/// @title ERC4626RatioLinearDiscountOraclePTREUSD
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice PT-reUSD oracle: growth-capped reUSD share price discounted linearly toward maturity
contract ERC4626RatioLinearDiscountOraclePTREUSD is AltoERC4626RatioLinearDiscountOracle {
    /// @notice The address of the reUSD share price calculator contract
    address public immutable REUSD_SHARE_PRICE_CALCULATOR;

    /// @notice Error thrown when the input is invalid
    error ERC4626RatioLinearDiscountOraclePTREUSDInvalidInput();

    /// @notice Constructor
    /// @param _owner The owner of the contract
    /// @param _reUSDSharePriceCalculator The address of the reUSD share price calculator contract
    /// @param _erc4626RatioNode Initial ERC4626 ratio node (initialRatio, initialTimestamp, maxYearlyGrowthRatioWad)
    /// @param _linearDiscountNode Initial linear discount node (maturity, baseDiscountPerYear, inDecimals, outDecimals)
    constructor(
        address _owner,
        address _reUSDSharePriceCalculator,
        ERC4626RatioNode memory _erc4626RatioNode,
        LinearDiscountNode memory _linearDiscountNode
    ) AltoERC4626RatioLinearDiscountOracle(_owner, _erc4626RatioNode, _linearDiscountNode) {
        if (_reUSDSharePriceCalculator == address(0)) {
            revert ERC4626RatioLinearDiscountOraclePTREUSDInvalidInput();
        }

        REUSD_SHARE_PRICE_CALCULATOR = _reUSDSharePriceCalculator;
    }

    /// @inheritdoc AltoERC4626RatioLinearDiscountOracle
    function _getRatioOfWrappedAssetToUnderlyingAsset() internal view override returns (uint256) {
        return ISharePriceCalculator(REUSD_SHARE_PRICE_CALCULATOR).getSharePrice();
    }
}
