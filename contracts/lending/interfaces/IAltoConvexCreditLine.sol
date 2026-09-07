// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreditMarketInitParams, IAltoCreditMarket} from "./IAltoCreditMarket.sol";

/// @notice Struct that represents the parameters for initializing a Convex credit line
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

interface IAltoConvexCreditLineErrors {
    /// @notice Error thrown when the Convex strategy is inactive
    error AltoConvexCreditLineStrategyInactive();

    /// @notice Error thrown when a Convex interaction changes balances unexpectedly
    error AltoConvexCreditLineUnexpectedAssetDelta();

    /// @notice Error thrown when a Convex call reports failure
    error AltoConvexCreditLineExternalCallFailed();

    /// @notice Error thrown when an emergency exit is attempted while the market is not paused
    error AltoConvexCreditLineMustBePaused();
}

interface IAltoConvexCreditLineEvents {
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
    /// @param assets The amount of collateral withdrawn from Convex
    event ConvexEmergencyExit(uint256 assets);
}

/// @title Alto Convex Credit Line
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for a Curve-LP-backed credit line staked through Convex
interface IAltoConvexCreditLine is IAltoCreditMarket, IAltoConvexCreditLineErrors, IAltoConvexCreditLineEvents {
    /// @notice The Convex Booster used to deposit collateral
    function convexBooster() external view returns (address);

    /// @notice The Convex pool identifier used by the market
    function convexPoolId() external view returns (uint256);

    /// @notice The Convex reward pool holding the market's staked position
    function convexRewardPool() external view returns (address);

    /// @notice The Convex deposit token associated with the reward pool
    function convexDepositToken() external view returns (address);

    /// @notice The account that receives claimed Convex rewards
    function rewardRecipient() external view returns (address);

    /// @notice Whether new collateral can be deposited into Convex
    function convexActive() external view returns (bool);

    /// @notice The number of configured reward tokens
    function rewardTokenCount() external view returns (uint256);

    /// @notice Returns a reward token by index
    /// @param index The index of the reward token
    function rewardToken(uint256 index) external view returns (address);

    /// @notice Returns whether a token is configured as a reward token
    /// @param token The token to query
    function isRewardToken(address token) external view returns (bool);

    /// @notice The amount of collateral currently staked in Convex
    function stakedCollateralAssets() external view returns (uint256);

    /// @notice The amount of collateral held directly by the market
    function idleCollateralAssets() external view returns (uint256);

    /// @notice Claims and forwards every configured Convex reward token
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

    /// @notice Permanently withdraws all staked collateral from Convex
    function emergencyExitConvex() external returns (uint256 assets);
}
