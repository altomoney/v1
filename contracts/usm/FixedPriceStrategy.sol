// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUsmPriceStrategy} from "./interfaces/IUsmPriceStrategy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title FixedPriceStrategy
 * @author Aave
 * @notice Price strategy involving a fixed-rate conversion from an underlying asset to stability token
 */
contract FixedPriceStrategy is IUsmPriceStrategy, AccessControl {
    using Math for uint256;

    /// @inheritdoc IUsmPriceStrategy
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @inheritdoc IUsmPriceStrategy
    uint256 public constant STABLE_TOKEN_DECIMALS = 18;

    /// @inheritdoc IUsmPriceStrategy
    address public immutable UNDERLYING_ASSET;

    /// @inheritdoc IUsmPriceStrategy
    uint256 public immutable UNDERLYING_ASSET_DECIMALS;

    /// @dev The price ratio from underlying asset to stability token (expressed in WAD), e.g. a ratio of 2e18 means 2 stability token per 1 underlying asset
    uint256 public priceRatio;

    /// @dev Underlying asset units represent units for the underlying asset
    uint256 internal immutable _underlyingAssetUnits;

    /**
     * @dev Constructor
     * @param initialPriceRatio The price ratio from underlying asset to stability token (expressed in WAD)
     * @param underlyingAsset The address of the underlying asset
     * @param underlyingAssetDecimals The number of decimals of the underlying asset
     */
    constructor(uint256 initialPriceRatio, address underlyingAsset, uint8 underlyingAssetDecimals, address admin) {
        require(initialPriceRatio > 0, "INVALID_PRICE_RATIO");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIGURATOR_ROLE, admin);
        priceRatio = initialPriceRatio;
        UNDERLYING_ASSET = underlyingAsset;
        UNDERLYING_ASSET_DECIMALS = underlyingAssetDecimals;
        _underlyingAssetUnits = 10 ** underlyingAssetDecimals;
    }

    /// @inheritdoc IUsmPriceStrategy
    function setPriceRatio(uint256 newPriceRatio) external onlyRole(CONFIGURATOR_ROLE) {
        require(newPriceRatio > 0, "INVALID_PRICE_RATIO");
        priceRatio = newPriceRatio;
    }

    /// @inheritdoc IUsmPriceStrategy
    function getAssetPriceInStableToken(uint256 assetAmount, bool roundUp) external view returns (uint256) {
        return assetAmount.mulDiv(priceRatio, _underlyingAssetUnits, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor);
    }

    /// @inheritdoc IUsmPriceStrategy
    function getStableTokenPriceInAsset(uint256 stabilityTokenAmount, bool roundUp) external view returns (uint256) {
        return stabilityTokenAmount.mulDiv(
            _underlyingAssetUnits, priceRatio, roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }
}
