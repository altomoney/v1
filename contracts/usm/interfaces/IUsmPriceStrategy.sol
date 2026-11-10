// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IUsmPriceStrategy
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Defines the behaviour of Price Strategies
 */
interface IUsmPriceStrategy {
    /**
     * @notice Emitted when the price ratio is set
     * @param oldPriceRatio The old price ratio
     * @param newPriceRatio The new price ratio
     */
    event PriceRatioSet(uint256 oldPriceRatio, uint256 newPriceRatio);

    /**
     * @notice Sets The price ratio from underlying asset to stability token (expressed in WAD),
     * @dev e.g. a ratio of 2e18 means 2 stability token per 1 underlying asset
     * @param newPriceRatio The new price ratio from underlying asset to stability token (expressed in WAD)
     */
    function setPriceRatio(uint256 newPriceRatio) external;

    /**
     * @notice Returns the identifier of the Configurator Role
     * @return The bytes32 id hash of the Configurator role
     */
    function CONFIGURATOR_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the number of decimals of Stable Token
     * @return The number of decimals of Stable Token
     */
    function STABLE_TOKEN_DECIMALS() external view returns (uint256);

    /**
     * @notice Returns the address of the underlying asset being priced
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET() external view returns (address);

    /**
     * @notice Returns the decimals of the underlying asset being priced
     * @return The number of decimals of the underlying asset
     */
    function UNDERLYING_ASSET_DECIMALS() external view returns (uint256);

    /**
     * @notice Returns the price of the underlying asset (Stable Token denominated)
     * @param assetAmount The amount of the underlying asset to calculate the price of
     * @param roundUp True if the price should be rounded up, false if rounded down
     * @return The price of the underlying asset (expressed in Stable Token units)
     */
    function getAssetPriceInStableToken(uint256 assetAmount, bool roundUp) external view returns (uint256);

    /**
     * @notice Returns the price of Stable Token (denominated in the underlying asset)
     * @param stableTokenAmount The amount of Stable Token to calculate the price of
     * @param roundUp True if the price should be rounded up, false if rounded down
     * @return The price of the Stable Token amount (expressed in underlying asset units)
     */
    function getStableTokenPriceInAsset(uint256 stableTokenAmount, bool roundUp) external view returns (uint256);
}
