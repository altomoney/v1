// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IStableTokenFacilitator} from "./IStableTokenFacilitator.sol";

/// @notice The access mode of the USM
/// @dev Anyone can swap if the access mode is PERMISSIONLESS
/// @dev Only addresses with the SWAPPER_ROLE can swap if the access mode is PERMISSIONED
enum AccessMode {
    PERMISSIONLESS,
    PERMISSIONED
}

/**
 * @title IUsm
 * @author GPM
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Defines the behaviour of a Universal Stability Module
 */
interface IUsm is IAccessControl, IStableTokenFacilitator {
    /**
     * @dev Emitted when a user buys an asset (selling Stable Token) in the USM
     * @param originator The address of the buyer originating the request
     * @param receiver The address of the receiver of the underlying asset
     * @param underlyingAmount The amount of the underlying asset bought
     * @param stableTokenAmount The amount of Stable Token sold, inclusive of fee
     * @param fee The fee paid by the buyer, in Stable Token
     */
    event BuyAsset(
        address indexed originator,
        address indexed receiver,
        uint256 underlyingAmount,
        uint256 stableTokenAmount,
        uint256 fee
    );

    /**
     * @dev Emitted when a user sells an asset (buying Stable Token) in the USM
     * @param originator The address of the seller originating the request
     * @param receiver The address of the receiver of Stable Token
     * @param underlyingAmount The amount of the underlying asset sold
     * @param stableTokenAmount The amount of Stable Token bought, inclusive of fee
     * @param fee The fee paid by the buyer, in Stable Token
     */
    event SellAsset(
        address indexed originator,
        address indexed receiver,
        uint256 underlyingAmount,
        uint256 stableTokenAmount,
        uint256 fee
    );

    /**
     * @dev Emitted when the Swap Freezer freezes buys/sells
     * @param freezer The address of the Swap Freezer
     * @param enabled True if swap functions are frozen, False otherwise
     */
    event SwapFreeze(address indexed freezer, bool enabled);

    /**
     * @dev Emitted when a Liquidator seizes USM funds
     * @param seizer The address originating the seizure request
     * @param recipient The address of the recipient of seized funds
     * @param underlyingAmount The amount of the underlying asset seized
     * @param stableTokenOutstanding The amount of remaining Stable Token that the USM had minted
     */
    event Seized(
        address indexed seizer, address indexed recipient, uint256 underlyingAmount, uint256 stableTokenOutstanding
    );

    /**
     * @dev Emitted when burning Stable Token after a seizure of USM funds
     * @param burner The address of the burner
     * @param amount The amount of Stable Token burned
     * @param stableTokenOutstanding The amount of remaining Stable Token that the USM had minted
     */
    event BurnAfterSeize(address indexed burner, uint256 amount, uint256 stableTokenOutstanding);

    /**
     * @dev Emitted when the Fee Strategy is updated
     * @param oldFeeStrategy The address of the old Fee Strategy
     * @param newFeeStrategy The address of the new Fee Strategy
     */
    event FeeStrategyUpdated(address indexed oldFeeStrategy, address indexed newFeeStrategy);

    /**
     * @dev Emitted when the Price Strategy is updated
     * @param oldPriceStrategy The address of the old Price Strategy
     * @param newPriceStrategy The address of the new Price Strategy
     */
    event PriceStrategyUpdated(address indexed oldPriceStrategy, address indexed newPriceStrategy);

    /**
     * @dev Emitted when the USM underlying asset Exposure Cap is updated
     * @param oldExposureCap The amount of the old Exposure Cap
     * @param newExposureCap The amount of the new Exposure Cap
     */
    event ExposureCapUpdated(uint256 oldExposureCap, uint256 newExposureCap);

    /**
     * @dev Emitted when the Access Mode is updated
     * @param accessMode The new access mode
     */
    event AccessModeUpdated(AccessMode accessMode);

    /**
     * @dev Emitted when tokens are rescued from the USM
     * @param tokenRescued The address of the rescued token
     * @param recipient The address that received the rescued tokens
     * @param amountRescued The amount of token rescued
     */
    event TokensRescued(address indexed tokenRescued, address indexed recipient, uint256 amountRescued);

    /**
     * @dev Emitted when Stable Token Treasury address is updated
     * @param oldStableTokenTreasury The address of the old Stable Token Treasury contract
     * @param newStableTokenTreasury The address of the new Stable Token Treasury contract
     */
    event StableTokenTreasuryUpdated(address indexed oldStableTokenTreasury, address indexed newStableTokenTreasury);

    /**
     * @notice Buys the USM underlying asset in exchange for selling Stable Token
     * @dev Use `getAssetAmountForBuyAsset` function to calculate the amount based on the Stable Token amount to sell
     * @param minAmount The minimum amount of the underlying asset to buy
     * @param receiver Recipient address of the underlying asset being purchased
     * @return The amount of underlying asset bought
     * @return The amount of Stable Token sold by the user
     */
    function buyAsset(uint256 minAmount, address receiver) external returns (uint256, uint256);

    /**
     * @notice Sells the USM underlying asset in exchange for buying Stable Token
     * @dev Use `getAssetAmountForSellAsset` function to calculate the amount based on the Stable Token amount to buy
     * @param maxAmount The maximum amount of the underlying asset to sell
     * @param receiver Recipient address of the Stable Token being purchased
     * @return The amount of underlying asset sold
     * @return The amount of Stable Token bought by the user
     */
    function sellAsset(uint256 maxAmount, address receiver) external returns (uint256, uint256);

    /**
     * @notice Rescue and transfer tokens locked in this contract
     * @param token The address of the token
     * @param to The address of the recipient
     * @param amount The amount of token to transfer
     */
    function rescueTokens(address token, address to, uint256 amount) external;

    /**
     * @notice Enable or disable the swap freeze
     * @param enable True to freeze swap functions, false otherwise
     */
    function setSwapFreeze(bool enable) external;

    /**
     * @notice Seizes all of the underlying asset from the USM, sending to the Treasury
     * @dev Seizing is a last resort mechanism to provide the Treasury with the entire amount of underlying asset
     * so it can be used to backstop any potential event impacting the functionality of the USM.
     * @dev Seizing disables the swap feature
     * @return The amount of underlying asset seized and transferred to Treasury
     */
    function seize() external returns (uint256);

    /**
     * @notice Burns an amount of Stable Token after seizure reducing the facilitator bucket level effectively
     * @dev Passing an amount higher than the facilitator bucket level will result in burning all minted Stable Token
     * @dev Only callable if the USM has assets seized, helpful to wind down the facilitator
     * @param amount The amount of Stable Token to burn
     * @return The amount of Stable Token burned
     */
    function burnAfterSeize(uint256 amount) external returns (uint256);

    /**
     * @notice Updates the address of the Fee Strategy
     * @param feeStrategy The address of the new FeeStrategy
     */
    function updateFeeStrategy(address feeStrategy) external;

    /**
     * @notice Updates the access mode of the USM
     * @param accessMode The new access mode
     */
    function updateAccessMode(AccessMode accessMode) external;

    /**
     * @notice Updates the exposure cap of the underlying asset
     * @param exposureCap The new value for the exposure cap (in underlying asset terms)
     */
    function updateExposureCap(uint128 exposureCap) external;

    /*
     * @notice Updates the address of the Price Strategy
     * @param priceStrategy The address of the new Price Strategy
     */
    function updatePriceStrategy(address priceStrategy) external;

    /**
     * @notice Updates the address of the Stable Token Treasury
     * @dev WARNING: The Stable Token Treasury is where revenue fees are sent to. Update carefully
     * @param newStableTokenTreasury The address of the Stable Token Treasury
     */
    function updateStableTokenTreasury(address newStableTokenTreasury) external;

    /**
     * @notice Returns the address of the Stable Token Treasury
     * @return The address of the Stable Token Treasury contract
     */
    function getStableTokenTreasury() external view returns (address);

    /**
     * @notice Returns the total amount of Stable Token, gross amount and fee result of buying assets
     * @param minAssetAmount The minimum amount of underlying asset to buy
     * @return The exact amount of underlying asset to be bought
     * @return The total amount of Stable Token the user sells (gross amount in Stable Token plus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied on top of gross amount of Stable Token
     */
    function getStableTokenAmountForBuyAsset(uint256 minAssetAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /**
     * @notice Returns the total amount of Stable Token, gross amount and fee result of selling assets
     * @param maxAssetAmount The maximum amount of underlying asset to sell
     * @return The exact amount of underlying asset to sell
     * @return The total amount of Stable Token the user buys (gross amount in Stable Token minus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied to the gross amount of Stable Token
     */
    function getStableTokenAmountForSellAsset(uint256 maxAssetAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /**
     * @notice Returns the amount of underlying asset, gross amount of Stable Token and fee result of buying assets
     * @param maxStableTokenAmount The maximum amount of Stable Token the user provides for buying underlying asset
     * @return The amount of underlying asset the user buys
     * @return The exact amount of Stable Token the user provides
     * @return The gross amount of Stable Token corresponding to the given total amount of Stable Token
     * @return The fee amount in Stable Token, charged for buying assets
     */
    function getAssetAmountForBuyAsset(uint256 maxStableTokenAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /**
     * @notice Returns the amount of underlying asset, gross amount of Stable Token and fee result of selling assets
     * @param minStableTokenAmount The minimum amount of Stable Token the user must receive for selling underlying asset
     * @return The amount of underlying asset the user sells
     * @return The exact amount of Stable Token the user receives in exchange
     * @return The gross amount of Stable Token corresponding to the given total amount of Stable Token
     * @return The fee amount in Stable Token, charged for selling assets
     */
    function getAssetAmountForSellAsset(uint256 minStableTokenAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /**
     * @notice Returns the remaining USM exposure capacity
     * @return The amount of underlying asset that can be sold to the USM
     */
    function getAvailableUnderlyingExposure() external view returns (uint256);

    /**
     * @notice Returns the exposure limit to the underlying asset
     * @return The maximum amount of underlying asset that can be sold to the USM
     */
    function getExposureCap() external view returns (uint128);

    /**
     * @notice Returns the actual underlying asset balance immediately available in the USM
     * @return The amount of underlying asset that can be bought from the USM
     */
    function getAvailableLiquidity() external view returns (uint256);

    /**
     * @notice Returns the Fee Strategy for the USM
     * @dev It returns 0x0 in case of no fee strategy
     * @return The address of the FeeStrategy
     */
    function getFeeStrategy() external view returns (address);

    /**
     * @notice Returns the amount of current accrued fees
     * @dev It does not factor in potential fees that can be accrued upon distribution of fees
     * @return The amount of accrued fees
     */
    function getAccruedFees() external view returns (uint256);

    /**
     * @notice Returns the freeze status of the USM
     * @return True if frozen, false if not
     */
    function getIsFrozen() external view returns (bool);

    /**
     * @notice Returns the access mode of the USM
     * @return The access mode
     */
    function getAccessMode() external view returns (AccessMode);

    /**
     * @notice Returns the current seizure status of the USM
     * @return True if the USM has been seized, false if not
     */
    function getIsSeized() external view returns (bool);

    /**
     * @notice Returns whether or not swaps via buyAsset/sellAsset are currently possible
     * @return True if the USM has swapping enabled, false otherwise
     */
    function canSwap() external view returns (bool);

    /**
     * @notice Returns the USM revision number
     * @return The revision number
     */
    function USM_REVISION() external pure returns (uint256);

    /**
     * @notice Returns the address of the Stable Token token
     * @return The address of Stable Token token contract
     */
    function STABLE_TOKEN() external view returns (address);

    /**
     * @notice Returns the underlying asset of the USM
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET() external view returns (address);

    /**
     * @notice Returns the price strategy of the USM
     * @return The address of the price strategy
     */
    function priceStrategy() external view returns (address);

    /**
     * @notice Returns the identifier of the Configurator Role
     * @return The bytes32 id hash of the Configurator role
     */
    function CONFIGURATOR_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the identifier of the Token Rescuer Role
     * @return The bytes32 id hash of the TokenRescuer role
     */
    function TOKEN_RESCUER_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the identifier of the Swap Freezer Role
     * @return The bytes32 id hash of the SwapFreezer role
     */
    function SWAP_FREEZER_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the identifier of the Liquidator Role
     * @return The bytes32 id hash of the Liquidator role
     */
    function LIQUIDATOR_ROLE() external pure returns (bytes32);

    /**
     * @notice Returns the identifier of the Swapper Role
     * @return The bytes32 id hash of the Swapper role
     */
    function SWAPPER_ROLE() external pure returns (bytes32);
}
