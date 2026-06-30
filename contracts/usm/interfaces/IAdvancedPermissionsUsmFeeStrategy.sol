// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAdvancedPermissionsUsmFeeStrategy
 * @author GPM
 * @custom:contact security@altofoundation.org
 * @notice Defines the behaviour of Advanced Permissions USM Fee Strategies
 * @dev Functions' logic must be invertible, being possible to calculate the fee amount based on the gross amount, and
 * the other way round.
 * @dev All math operations must round up, favoring the protocol.
 */
interface IAdvancedPermissionsUsmFeeStrategy {
    /**
     * @notice Data structure for overridden fee data
     * @dev If the fee is overridden, the fee will be used instead of the default fee
     * @dev isOverridden flag is needed because we can also override fee to 0
     * @param isOverridden Whether the fee is overridden
     * @param fee The fee, expressed in bps
     */
    struct OverriddenFeeData {
        bool isOverridden;
        uint16 fee;
    }

    /**
     * @notice Emitted when the buy fee for a specific role hash is set
     * @param roleHash The hash of the role
     * @param overriddenFeeData The data of the overridden fee
     */
    event BuyFeeByRoleHashSet(bytes32 indexed roleHash, OverriddenFeeData overriddenFeeData);

    /**
     * @notice Emitted when the sell fee for a specific role hash is set
     * @param roleHash The hash of the role
     * @param overriddenFeeData The data of the overridden fee
     */
    event SellFeeByRoleHashSet(bytes32 indexed roleHash, OverriddenFeeData overriddenFeeData);

    /**
     * @notice Emitted when the buy fee for a specific originator is overridden
     * @param originator The address of the originator
     * @param overriddenFeeData The data of the overridden fee
     */
    event OverrideBuyFeeSet(address indexed originator, OverriddenFeeData overriddenFeeData);

    /**
     * @notice Emitted when the sell fee for a specific originator is overridden
     * @param originator The address of the originator
     * @param overriddenFeeData The data of the overridden fee
     */
    event OverrideSellFeeSet(address indexed originator, OverriddenFeeData overriddenFeeData);

    /**
     * @notice Emitted when the buy and sell fees are set
     * @param oldBuyFee The old buy fee
     * @param newBuyFee The new buy fee
     * @param oldSellFee The old sell fee
     * @param newSellFee The new sell fee
     */
    event FeeSet(uint16 oldBuyFee, uint16 newBuyFee, uint16 oldSellFee, uint16 newSellFee);

    /**
     * @notice Emitted when a buy fee-only role is assigned to an originator
     * @dev This role is purely for buy fee-tier selection and has no access-control effect
     * @param originator The address of the originator
     * @param feeRole The role hash assigned for fee purposes (bytes32(0) to clear)
     */
    event UserBuyFeeRoleSet(address indexed originator, bytes32 indexed feeRole);

    /**
     * @notice Emitted when a sell fee-only role is assigned to an originator
     * @dev This role is purely for sell fee-tier selection and has no access-control effect
     * @param originator The address of the originator
     * @param feeRole The role hash assigned for fee purposes (bytes32(0) to clear)
     */
    event UserSellFeeRoleSet(address indexed originator, bytes32 indexed feeRole);

    /**
     * @notice Sets the buy and sell fees, expressed in bps
     * @param buyFee The new buy fee, expressed in bps
     * @param sellFee The new sell fee, expressed in bps
     */
    function setFee(uint256 buyFee, uint256 sellFee) external;

    /**
     * @notice Overrides the buy fee for a specific originator
     * @param originator The address of the originator
     * @param overriddenFeeData The data of the overridden fee
     */
    function overrideBuyFee(address originator, OverriddenFeeData memory overriddenFeeData) external;

    /**
     * @notice Overrides the sell fee for a specific originator
     * @param originator The address of the originator
     * @param overriddenFeeData The data of the overridden fee
     */
    function overrideSellFee(address originator, OverriddenFeeData memory overriddenFeeData) external;

    /**
     * @notice Sets the buy fee for a specific role hash
     * @param roleHash The hash of the role
     * @param overriddenFeeData The data of the overridden fee
     */
    function setBuyFeeByRoleHash(bytes32 roleHash, OverriddenFeeData memory overriddenFeeData) external;

    /**
     * @notice Sets the sell fee for a specific role hash
     * @param roleHash The hash of the role
     * @param overriddenFeeData The data of the overridden fee
     */
    function setSellFeeByRoleHash(bytes32 roleHash, OverriddenFeeData memory overriddenFeeData) external;

    /**
     * @notice Assigns a buy fee-only role to a specific originator
     * @dev The role is used purely for buy fee-tier lookup via setBuyFeeByRoleHash.
     *      It has no effect on swap access. Pass bytes32(0) to clear the assignment.
     * @param originator The address of the originator
     * @param feeRole The role hash to assign (bytes32(0) to remove)
     */
    function setUserBuyFeeRole(address originator, bytes32 feeRole) external;

    /**
     * @notice Assigns a sell fee-only role to a specific originator
     * @dev The role is used purely for sell fee-tier lookup via setSellFeeByRoleHash.
     *      It has no effect on swap access. Pass bytes32(0) to clear the assignment.
     * @param originator The address of the originator
     * @param feeRole The role hash to assign (bytes32(0) to remove)
     */
    function setUserSellFeeRole(address originator, bytes32 feeRole) external;

    /**
     * @notice Returns the buy fee-only role assigned to a specific originator
     * @param originator The address of the originator
     * @return The fee role hash, or bytes32(0) if none is assigned
     */
    function getUserBuyFeeRole(address originator) external view returns (bytes32);

    /**
     * @notice Returns the sell fee-only role assigned to a specific originator
     * @param originator The address of the originator
     * @return The fee role hash, or bytes32(0) if none is assigned
     */
    function getUserSellFeeRole(address originator) external view returns (bytes32);

    /**
     * @notice Returns the default buy fee applied when no per-address or role override exists
     * @return The default buy fee, expressed in bps
     */
    function getDefaultBuyFee() external view returns (uint256);

    /**
     * @notice Returns the default sell fee applied when no per-address or role override exists
     * @return The default sell fee, expressed in bps
     */
    function getDefaultSellFee() external view returns (uint256);

    /**
     * @notice Returns the buy fee for a specific originator
     * @dev Precedence (highest to lowest):
     *      1. Per-address override (overrideBuyFee)
     *      2. Buy fee-only role assigned via setUserBuyFeeRole
     *      3. Default fee
     * @param originator The address of the originator
     * @return The buy fee, expressed in bps
     */
    function getBuyFeeForUser(address originator) external view returns (uint256);

    /**
     * @notice Returns the sell fee for a specific originator
     * @dev Precedence (highest to lowest):
     *      1. Per-address override (overrideSellFee)
     *      2. Sell fee-only role assigned via setUserSellFeeRole
     *      3. Default fee
     * @param originator The address of the originator
     * @return The sell fee, expressed in bps
     */
    function getSellFeeForUser(address originator) external view returns (uint256);

    /**
     * @notice Returns the fee to be applied when buying an underlying asset in exchange for Stable Token
     * @param grossAmount The amount of Stable Token being sold for the underlying asset
     * @param originator The address of the originator of the buy request
     * @return The fee amount of Stable Token
     */
    function getBuyFee(uint256 grossAmount, address originator) external view returns (uint256);

    /**
     * @notice Returns the fee to be applied when buying Stable Token in exchange for an underlying asset
     * @param grossAmount The amount of underlying, converted to Stable Token, being sold
     * @param originator The address of the originator of the sell request
     * @return The fee amount of Stable Token
     */
    function getSellFee(uint256 grossAmount, address originator) external view returns (uint256);

    /**
     * @notice Returns the gross amount of Stable Token being bought based on the total bought amount
     * @param totalAmount The total amount of Stable Token being bought (gross amount, Stable Token bought plus fee)
     * @param originator The address of the originator of the buy request
     * @return The gross amount of Stable Token being bought (total amount minus fee)
     */
    function getGrossAmountFromTotalBought(uint256 totalAmount, address originator) external view returns (uint256);

    /**
     * @notice Returns the amount of Stable Token being sold based on the total sold amount
     * @param totalAmount The total amount of Stable Token being sold (gross amount, Stable Token sold minus fee)
     * @param originator The address of the originator of the sell request
     * @return The gross amount of Stable Token being sold (total amount plus fee)
     */
    function getGrossAmountFromTotalSold(uint256 totalAmount, address originator) external view returns (uint256);
}
