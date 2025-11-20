// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IRsmPriceStrategy} from "./interfaces/IRsmPriceStrategy.sol";

/**
 * @title FixedPriceStrategy
 * @author Aave
 * @notice Price strategy involving a fixed-rate conversion from an underlying asset to GHO
 */
contract FixedPriceStrategy is IRsmPriceStrategy {
    using Math for uint256;

    /// @inheritdoc IRsmPriceStrategy
    uint256 public constant GHO_DECIMALS = 18;

    /// @inheritdoc IRsmPriceStrategy
    address public immutable UNDERLYING_ASSET;

    /// @inheritdoc IRsmPriceStrategy
    uint256 public immutable UNDERLYING_ASSET_DECIMALS;

    /// @dev The price ratio from underlying asset to GHO (expressed in WAD), e.g. a ratio of 2e18 means 2 GHO per 1 underlying asset
    uint256 public immutable PRICE_RATIO;

    /// @dev Underlying asset units represent units for the underlying asset
    uint256 internal immutable _underlyingAssetUnits;

    /**
     * @dev Constructor
     * @param priceRatio The price ratio from underlying asset to GHO (expressed in WAD)
     * @param underlyingAsset The address of the underlying asset
     * @param underlyingAssetDecimals The number of decimals of the underlying asset
     */
    constructor(uint256 priceRatio, address underlyingAsset, uint8 underlyingAssetDecimals) {
        require(priceRatio > 0, "INVALID_PRICE_RATIO");
        PRICE_RATIO = priceRatio;
        UNDERLYING_ASSET = underlyingAsset;
        UNDERLYING_ASSET_DECIMALS = underlyingAssetDecimals;
        _underlyingAssetUnits = 10 ** underlyingAssetDecimals;
    }

    /// @inheritdoc IRsmPriceStrategy
    function getAssetPriceInGho(uint256 assetAmount, bool roundUp) external view returns (uint256) {
        return
            assetAmount.mulDiv(PRICE_RATIO, _underlyingAssetUnits, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }

    /// @inheritdoc IRsmPriceStrategy
    function getGhoPriceInAsset(uint256 ghoAmount, bool roundUp) external view returns (uint256) {
        return ghoAmount.mulDiv(_underlyingAssetUnits, PRICE_RATIO, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }
}
