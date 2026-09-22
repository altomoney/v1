// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseMarketInitParams, IMarket, IMarketStaticTypes} from "./IMarket.sol";

/// @notice Struct that represents the parameters for initializing a credit market
struct CreditMarketInitParams {
    /// @notice The parameters for initializing the base market.
    BaseMarketInitParams baseMarketInitParams;
    /// @notice The sole account permitted to own collateral and debt.
    address creditAccount;
    /// @notice The maximum credit capacity; used capacity is `totalBorrowed.assets + badDebtAssets`.
    uint256 creditLimit;
    /// @notice The LTV above which governance may foreclose.
    uint256 foreclosureLtv;
    /// @notice The initial borrow opening fee.
    uint256 initialBorrowOpeningFee;
}

/// @notice Struct that represents the parameters for initializing a Convex credit line market
struct ConvexCreditLineInitParams {
    /// @notice The credit market initialization parameters.
    CreditMarketInitParams creditMarketInitParams;
    /// @notice The address of the Convex Booster.
    address convexBooster;
    /// @notice The Convex pool identifier.
    uint256 convexPoolId;
    /// @notice The account that receives Convex rewards.
    address rewardRecipient;
    /// @notice The initial list of reward tokens to forward.
    address[] rewardTokens;
}

interface IAltoConvexCreditLineMarketErrors {
    /// @notice Error thrown when a required address is the zero address
    error AltoCreditMarketZeroAddress();

    /// @notice Error thrown when the input is invalid
    error AltoCreditMarketInvalidInput();

    /// @notice Error thrown when an account is unauthorized
    error AltoCreditMarketUnauthorizedAccount();

    /// @notice Error thrown when changing a credit account that still has debt or collateral
    error AltoCreditMarketPositionNotEmpty();

    /// @notice Error thrown when callback data is provided
    error AltoCreditMarketCallbacksUnsupported();

    /// @notice Error thrown when the oracle returns a zero price
    error AltoCreditMarketInvalidOraclePrice();

    /// @notice Error thrown when a position is not eligible for foreclosure
    error AltoCreditMarketPositionNotForeclosable();

    /// @notice Error thrown when a standard market operation is unsupported
    error AltoCreditMarketUnsupportedOperation();

    /// @notice Error thrown when public liquidation is attempted
    error AltoCreditMarketNonLiquidatable();

    /// @notice Error thrown when the Convex strategy is inactive
    error AltoConvexCreditLineStrategyInactive();

    /// @notice Error thrown when a Convex call reports failure
    error AltoConvexCreditLineExternalCallFailed();

    /// @notice Error thrown when an emergency exit is attempted while the market is not paused
    error AltoConvexCreditLineMustBePaused();
}

interface IAltoConvexCreditLineMarketEvents {
    /// @notice Emitted when the credit account is initialized or changed
    /// @param oldCreditAccount The previous credit account, or zero during initialization
    /// @param newCreditAccount The new credit account
    event SetCreditAccount(address indexed oldCreditAccount, address indexed newCreditAccount);

    /// @notice Emitted when the credit limit is set
    /// @param oldCreditLimit The old credit limit
    /// @param newCreditLimit The new credit limit
    event SetCreditLimit(uint256 oldCreditLimit, uint256 newCreditLimit);

    /// @notice Emitted when the foreclosure LTV is set
    /// @param oldForeclosureLtv The old foreclosure LTV
    /// @param newForeclosureLtv The new foreclosure LTV
    event SetForeclosureLtv(uint256 oldForeclosureLtv, uint256 newForeclosureLtv);

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when interest and fees are claimed
    /// @param recipient The account that received the borrow tokens
    /// @param amount The amount of borrow tokens minted
    event InterestClaimed(address indexed recipient, uint256 amount);

    /// @notice Emitted when debt is written off during foreclosure
    /// @param badDebtAmount The amount of bad debt accrued
    event BadDebtAccrued(uint256 badDebtAmount);

    /// @notice Emitted when recovered borrow tokens are burned to settle bad debt
    /// @param settledAssets The amount of bad debt settled
    event BadDebtSettled(uint256 settledAssets);

    /// @notice Emitted when the Convex pool is configured
    /// @param booster The address of the Convex Booster
    /// @param poolId The Convex pool identifier
    /// @param rewardPool The address of the Convex reward pool
    /// @param depositToken The address of the Convex deposit token
    /// @param rewardRecipient The account that receives Convex rewards
    event ConvexConfigured(
        address indexed booster,
        uint256 indexed poolId,
        address indexed rewardPool,
        address depositToken,
        address rewardRecipient
    );

    /// @notice Emitted when collateral is deposited and staked in Convex
    /// @param caller The account that deposited the collateral
    /// @param assets The amount of collateral deposited
    event CollateralStaked(address indexed caller, uint256 assets);

    /// @notice Emitted when collateral is unstaked and transferred
    /// @param receiver The account that received the collateral
    /// @param assets The amount of collateral withdrawn
    event CollateralUnstaked(address indexed receiver, uint256 assets);

    /// @notice Emitted for each reward token processed during a claim
    /// @param caller The account that claimed the rewards
    /// @param recipient The account that received the rewards
    /// @param token The reward token processed
    /// @param amount The amount of reward tokens transferred
    event RewardsClaimed(address indexed caller, address indexed recipient, address indexed token, uint256 amount);

    /// @notice Emitted when the reward recipient is set
    /// @param oldRecipient The old reward recipient
    /// @param newRecipient The new reward recipient
    event SetRewardRecipient(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Emitted when a reward token is added
    /// @param token The reward token added
    event RewardTokenAdded(address indexed token);

    /// @notice Emitted when a reward token is removed
    /// @param token The reward token removed
    event RewardTokenRemoved(address indexed token);

    /// @notice Emitted when governance exits the Convex strategy
    /// @param assets The reward-pool stake balance requested for withdrawal from Convex
    event ConvexEmergencyExit(uint256 assets);
}

/// @dev This interface is used for factorizing IAltoConvexCreditLineMarketStaticTypes and
/// IAltoConvexCreditLineMarket.
/// @dev Consider using the IAltoConvexCreditLineMarket interface instead of this one.
interface IAltoConvexCreditLineMarketBase is IAltoConvexCreditLineMarketErrors, IAltoConvexCreditLineMarketEvents {
    /// @notice The sole account permitted to own market collateral and debt
    /// @return The configured credit-account address
    function creditAccount() external view returns (address);

    /// @notice The LTV above which governance may foreclose
    /// @return The foreclosure LTV in `MATH_PRECISION`
    function foreclosureLtv() external view returns (uint256);

    /// @notice The opening fees and accrued interest available to claim
    /// @return The claimable amount in borrow-token assets
    function claimableFeesAssets() external view returns (uint128);

    /// @notice The debt written off during foreclosures that has not been settled
    /// @return The unsettled bad debt in borrow-token assets
    function badDebtAssets() external view returns (uint256);

    /// @notice Sets the credit account when the current account has no debt or collateral
    /// @dev Only the owner may change the account. The reward recipient and account-specific authorizations
    /// retain their configured values; the new credit account may update its reward recipient and authorizations.
    /// @param newCreditAccount The nonzero account permitted to own market collateral and debt
    function setCreditAccount(address newCreditAccount) external;

    /// @notice Sets the maximum credit capacity; used capacity is `totalBorrowed.assets + badDebtAssets`
    /// @dev Zero is allowed when active debt and bad debt are both zero after any interest accrual.
    /// @param newCreditLimit The new credit limit
    function setCreditLimit(uint256 newCreditLimit) external;

    /// @notice Sets the LTV above which governance may foreclose
    /// @param newForeclosureLtv The new foreclosure LTV
    function setForeclosureLtv(uint256 newForeclosureLtv) external;

    /// @notice Sets the borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 newBorrowOpeningFee) external;

    /// @notice Claims interest and fees for the fee recipient
    /// @param interest The amount to claim, or zero to claim all
    /// @return claimed The amount minted to the fee recipient
    function claimInterest(uint256 interest) external returns (uint256 claimed);

    /// @notice Burns recovered borrow tokens from the owner and reduces recorded bad debt
    /// @dev Available while paused or frozen. The amount must be positive and cannot exceed bad debt, the owner's
    /// token balance or DUSD's minted balance for this market. Unminted fees may need to be claimed before settlement.
    /// @param assets The amount of bad debt to settle in borrow-token assets
    function settleBadDebt(uint256 assets) external;

    /// @notice The Convex Booster used to deposit collateral
    function convexBooster() external view returns (address);

    /// @notice The Convex pool identifier used by the market
    function convexPoolId() external view returns (uint256);

    /// @notice The Convex reward pool holding the market staked position
    function convexRewardPool() external view returns (address);

    /// @notice The account that receives claimed Convex rewards
    function rewardRecipient() external view returns (address);

    /// @notice Whether the Convex strategy is active for collateral deposits and withdrawals
    /// @dev When false, new collateral additions revert, while removals and governance foreclosure transfer LP tokens
    /// recovered into idle market custody by the emergency exit.
    function convexActive() external view returns (bool);

    /// @notice Returns a reward token by index
    /// @param index The index of the reward token
    function rewardToken(uint256 index) external view returns (address);

    /// @notice Returns whether a token is configured as a reward token
    /// @param token The token to query
    function isRewardToken(address token) external view returns (bool);

    /// @notice Claims and forwards every configured Convex reward token
    /// @return claimedAmounts The amount forwarded for each configured reward token
    function claimRewards() external returns (uint256[] memory claimedAmounts);

    /// @notice Sets the account that receives future reward claims
    /// @param newRecipient The new reward recipient
    function setRewardRecipient(address newRecipient) external;

    /// @notice Adds a token to the reward forwarding list
    /// @param token The token to add
    function addRewardToken(address token) external;

    /// @notice Removes a token from the reward forwarding list
    /// @param token The token to remove
    function removeRewardToken(address token) external;

    /// @notice Withdraws the reported Convex stake and permanently deactivates the strategy
    /// @dev Once inactive, new collateral additions revert. After unpausing, collateral removals and governance
    /// foreclosure transfer the recovered LP tokens directly from idle market custody.
    /// @return assets The reward-pool stake balance requested for withdrawal
    function emergencyExitConvex() external returns (uint256 assets);
}

/// @title Alto Convex Credit Line Market
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for a Curve-LP-backed credit line market staked through Convex
interface IAltoConvexCreditLineMarket is IMarket, IAltoConvexCreditLineMarketBase {
    /// @notice Adds collateral to the credit account's position and deposits it into Convex
    /// @dev Only the exact `creditAccount` may call this function and `onBehalf` must equal `creditAccount`.
    /// Authorized delegates and unrelated accounts cannot add collateral.
    /// @param assets The amount of collateral to add
    /// @param onBehalf The configured credit account
    /// @return assets The amount of collateral added
    function addCollateral(uint256 assets, address onBehalf) external override returns (uint256);

    /// @notice Sets a nonzero IRM for the market
    /// @param irm The address of the new IRM implementing IIrm
    /// @param skipAccrueInterest Whether to skip accrual with the current IRM before updating it
    function setIrm(address irm, bool skipAccrueInterest) external override;

    /// @notice Accrues interest into active debt and claimable fees
    /// @dev The IRM receives the credit limit as total supply and active debt as total borrowed, excluding bad debt.
    /// The credit limit stored in `totalSupply.assets` remains unchanged.
    function accrueInterest() external override;
}

/// @dev This interface is inherited by the implementation so public struct getters are type checked.
/// @dev Consider using the IAltoConvexCreditLineMarket interface instead of this one.
interface IAltoConvexCreditLineMarketStaticTypes is IMarketStaticTypes, IAltoConvexCreditLineMarketBase {}
