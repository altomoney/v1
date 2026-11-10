// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IUsmFeeStrategy
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Defines the behaviour of Fee Strategies
 * @dev Functions' logic must be invertible, being possible to calculate the fee amount based on the gross amount, and
 * the other way round.
 * @dev All math operations must round up, favoring the protocol.
 */
interface IUsmFeeStrategy {
    /**
     * @notice Emitted when the buy and sell fees are set
     * @param oldBuyFee The old buy fee
     * @param newBuyFee The new buy fee
     * @param oldSellFee The old sell fee
     * @param newSellFee The new sell fee
     */
    event FeeSet(uint256 oldBuyFee, uint256 newBuyFee, uint256 oldSellFee, uint256 newSellFee);

    /**
     * @notice Sets the buy and sell fees, expressed in bps
     * @param buyFee The new buy fee, expressed in bps
     * @param sellFee The new sell fee, expressed in bps
     */
    function setFee(uint256 buyFee, uint256 sellFee) external;

    /**
     * @notice Returns the fee to be applied when buying an underlying asset in exchange for Stable Token
     * @param grossAmount The amount of Stable Token being sold for the underlying asset
     * @return The fee amount of Stable Token
     */
    function getBuyFee(uint256 grossAmount) external view returns (uint256);

    /**
     * @notice Returns the fee to be applied when buying Stable Token in exchange for an underlying asset
     * @param grossAmount The amount of underlying, converted to Stable Token, being sold
     * @return The fee amount of Stable Token
     */
    function getSellFee(uint256 grossAmount) external view returns (uint256);

    /**
     * @notice Returns the gross amount of Stable Token being bought based on the total bought amount
     * @param totalAmount The total amount of Stable Token being bought (gross amount, Stable Token bought plus fee)
     * @return The gross amount of Stable Token being bought (total amount minus fee)
     */
    function getGrossAmountFromTotalBought(uint256 totalAmount) external view returns (uint256);

    /**
     * @notice Returns the amount of Stable Token being sold based on the total sold amount
     * @param totalAmount The total amount of Stable Token being sold (gross amount, Stable Token sold minus fee)
     * @return The gross amount of Stable Token being sold (total amount plus fee)
     */
    function getGrossAmountFromTotalSold(uint256 totalAmount) external view returns (uint256);
}
