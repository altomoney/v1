// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUsmPriceStrategy} from "./interfaces/IUsmPriceStrategy.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title FixedPriceStrategy
 * @author Aave
 * @notice Price strategy involving a fixed-rate conversion from an underlying asset to stability token
 */
contract FixedPriceStrategy is IUsmPriceStrategy, Ownable2Step {
    using Math for uint256;

    /// @inheritdoc IUsmPriceStrategy
    uint256 public constant STABLE_TOKEN_DECIMALS = 18;

    /// @inheritdoc IUsmPriceStrategy
    address public immutable UNDERLYING_ASSET;

    /// @inheritdoc IUsmPriceStrategy
    uint256 public immutable UNDERLYING_ASSET_DECIMALS;

    /// @dev The price ratio from underlying asset to stability token (expressed in WAD), e.g. a ratio of 2e18 means 2 stability token per 1 underlying asset
    uint256 public PRICE_RATIO;

    /// @dev Underlying asset units represent units for the underlying asset
    uint256 internal immutable _underlyingAssetUnits;

    /**
     * @dev Constructor
     * @param priceRatio The price ratio from underlying asset to stability token (expressed in WAD)
     * @param underlyingAsset The address of the underlying asset
     * @param underlyingAssetDecimals The number of decimals of the underlying asset
     */
    constructor(uint256 priceRatio, address underlyingAsset, uint8 underlyingAssetDecimals, address owner)
        Ownable(owner)
    {
        require(priceRatio > 0, "INVALID_PRICE_RATIO");
        PRICE_RATIO = priceRatio;
        UNDERLYING_ASSET = underlyingAsset;
        UNDERLYING_ASSET_DECIMALS = underlyingAssetDecimals;
        _underlyingAssetUnits = 10 ** underlyingAssetDecimals;
    }

    /// @inheritdoc IUsmPriceStrategy
    function setPriceRatio(uint256 newPriceRatio) external onlyOwner {
        require(newPriceRatio > 0, "INVALID_PRICE_RATIO");
        PRICE_RATIO = newPriceRatio;
    }

    /// @inheritdoc IUsmPriceStrategy
    function getAssetPriceInStableToken(uint256 assetAmount, bool roundUp) external view returns (uint256) {
        return
            assetAmount.mulDiv(PRICE_RATIO, _underlyingAssetUnits, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }

    /// @inheritdoc IUsmPriceStrategy
    function getStableTokenPriceInAsset(uint256 stabilityTokenAmount, bool roundUp) external view returns (uint256) {
        return stabilityTokenAmount.mulDiv(
            _underlyingAssetUnits, PRICE_RATIO, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }
}
