// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreditMarketInitParams, IAltoCreditMarket} from "@alto/lending/interfaces/IAltoCreditMarket.sol";

/// @notice Parameters used to initialize a Curve-LP-backed Convex credit line.
struct ConvexCreditLineInitParams {
    /// @dev Credit-market, risk, ownership, and fee configuration.
    CreditMarketInitParams market;

    /// @dev Convex Booster through which Curve LP collateral is deposited.
    address convexBooster;

    /// @dev Convex pool identifier associated with the collateral LP token.
    uint256 convexPoolId;

    /// @dev Account that receives all claimed Convex rewards.
    address rewardRecipient;

    /// @dev Initial allowlist of reward tokens forwarded after a claim; must
    /// include the primary reward.
    address[] rewardTokens;
}

/// @title Alto Convex Credit Line
///
/// @notice Interface for an Alto credit facility whose Curve LP collateral is
/// staked through Convex.
interface IAltoConvexCreditLine is IAltoCreditMarket {
    /// @notice An operation requiring the Convex strategy was attempted after
    /// the strategy became inactive.
    error AltoConvexCreditLine__StrategyInactive();

    /// @notice A Convex interaction changed an LP-token or staked balance by an
    /// unexpected amount.
    error AltoConvexCreditLine__UnexpectedAssetDelta();

    /// @notice A Convex Booster or reward-pool call reported failure.
    error AltoConvexCreditLine__ExternalCallFailed();

    /// @notice The owner attempted an emergency Convex exit before fully
    /// pausing the market.
    error AltoConvexCreditLine__MustBePaused();

    /// @notice Emitted when the market is initialized with a validated Convex
    /// pool.
    ///
    /// @param booster          Convex Booster used to deposit Curve LP collateral.
    /// @param poolId           Convex pool identifier selected for the facility.
    /// @param rewardPool       Convex reward pool in which the market's position is staked.
    /// @param depositToken     Convex deposit token registered as the reward pool's staking token.
    /// @param rewardRecipient  Initial recipient of claimed rewards.
    event ConvexConfigured(
        address indexed booster,
        uint256 indexed poolId,
        address indexed rewardPool,
        address depositToken,
        address rewardRecipient
    );

    /// @notice Emitted after Curve LP collateral is deposited and staked in
    /// Convex.
    ///
    /// @param caller Account that supplied the Curve LP tokens.
    /// @param assets Amount staked, denominated in collateral-token units.
    event CollateralStaked(address indexed caller, uint256 assets);

    /// @notice Emitted after Curve LP collateral is unstaked or released from
    /// idle custody and transferred out.
    ///
    /// @param receiver Account that received the Curve LP tokens.
    /// @param assets   Amount transferred, denominated in collateral-token units.
    event CollateralUnstaked(address indexed receiver, uint256 assets);

    /// @notice Emitted once for each configured reward token processed during a
    /// reward claim.
    ///
    /// @param caller       Account that initiated the permissionless claim.
    /// @param recipient    Account that received the reward token.
    /// @param token        Reward token processed by the claim.
    /// @param amount       Entire market balance of the token forwarded to the recipient.
    event RewardsClaimed(address indexed caller, address indexed recipient, address indexed token, uint256 amount);

    /// @notice Emitted when the credit account changes the reward recipient.
    ///
    /// @param oldRecipient Previous reward recipient.
    /// @param newRecipient New reward recipient.
    event SetRewardRecipient(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Emitted when governance adds a token to the reward-forwarding
    /// list.
    ///
    /// @param token Reward token added to the list.
    event RewardTokenAdded(address indexed token);

    /// @notice Emitted when governance removes an inactive extra-reward token
    /// from the forwarding list.
    ///
    /// @param token Reward token removed from the list.
    event RewardTokenRemoved(address indexed token);

    /// @notice Emitted when governance permanently exits the Convex strategy
    /// into idle Curve LP custody.
    ///
    /// @param assets Amount withdrawn from Convex, denominated in collateral-token units.
    event ConvexEmergencyExit(uint256 assets);

    /// @notice Returns the Convex Booster used to deposit collateral.
    ///
    /// @return booster Configured Booster address.
    function convexBooster() external view returns (address booster);

    /// @notice Returns the Convex pool identifier used by the facility.
    ///
    /// @return poolId Configured Convex pool identifier.
    function convexPoolId() external view returns (uint256 poolId);

    /// @notice Returns the Convex reward pool holding the market's staked
    /// position.
    ///
    /// @return rewardPool Configured reward-pool address.
    function convexRewardPool() external view returns (address rewardPool);

    /// @notice Returns the Convex deposit token registered as the reward pool's
    /// staking token.
    ///
    /// @return depositToken Configured Convex deposit-token address.
    function convexDepositToken() external view returns (address depositToken);

    /// @notice Returns the account that receives claimed Convex rewards.
    ///
    /// @return recipient Current reward recipient.
    function rewardRecipient() external view returns (address recipient);

    /// @notice Reports whether new collateral can still be deposited into Convex.
    ///
    /// @return active True while the Convex strategy remains active.
    ///
    /// @dev An emergency exit permanently sets this value to false. Existing
    /// idle LP can still be repaid against and, after debt is cleared, withdrawn.
    function convexActive() external view returns (bool active);

    /// @notice Returns the number of reward tokens in the forwarding list.
    ///
    /// @return count Number of configured reward tokens.
    function rewardTokenCount() external view returns (uint256 count);

    /// @notice Returns a reward token by its current forwarding-list index.
    ///
    /// @param index Index into the current reward-token list.
    ///
    /// @return token Reward token stored at `index`.
    ///
    /// @dev Indices are not stable because removal uses swap-and-pop.
    function rewardToken(uint256 index) external view returns (address token);

    /// @notice Reports whether a token is currently included in reward
    /// forwarding.
    ///
    /// @param token Token to query.
    ///
    /// @return configured True if the token is currently configured as a reward
    /// token.
    function isRewardToken(address token) external view returns (bool configured);

    /// @notice Returns Curve LP collateral currently staked in the Convex
    /// reward pool.
    ///
    /// @return assets Staked amount denominated in collateral-token units.
    function stakedCollateralAssets() external view returns (uint256 assets);

    /// @notice Returns Curve LP collateral held directly by the market.
    ///
    /// @return assets Idle amount denominated in collateral-token units.
    function idleCollateralAssets() external view returns (uint256 assets);

    /// @notice Claims Convex rewards and forwards every configured reward-token
    /// balance to the reward recipient.
    ///
    /// @return claimedAmounts Amount forwarded for each token, ordered according
    /// to the current reward-token list.
    ///
    /// @dev Permissionless and available while paused. The call requests both
    /// primary and extra rewards from Convex, then forwards each token's entire
    /// market balance. Tokens not in the forwarding list remain in the market.
    function claimRewards() external returns (uint256[] memory claimedAmounts);

    /// @notice Changes the account that receives future reward claims.
    ///
    /// @param newRecipient Nonzero account that will receive claimed rewards.
    ///
    /// @dev Callable only by the exact credit account, not its delegates or
    /// market governance. Rewards already held by the market follow the
    /// recipient configured when `claimRewards()` executes.
    function setRewardRecipient(address newRecipient) external;

    /// @notice Adds a token to the reward-forwarding list.
    ///
    /// @param token Reward token to add.
    ///
    /// @dev Callable only by the owner. The token must not be the collateral,
    /// borrow, or Convex deposit token; must not already be configured; and
    /// must fit within the fixed list cap.
    function addRewardToken(address token) external;

    /// @notice Removes an inactive extra-reward token from the forwarding list.
    ///
    /// @param token Configured extra-reward token to remove.
    ///
    /// @dev Callable only by the owner. The primary reward-pool token and tokens
    /// already held by the market cannot be removed. Removal changes list
    /// ordering via swap-and-pop. Governance must independently confirm that
    /// Convex will not distribute the token again; if emissions resume, the
    /// token must be re-added before rewards can be forwarded.
    function removeRewardToken(address token) external;

    /// @notice Permanently withdraws all staked collateral from Convex into
    /// idle market custody.
    ///
    /// @return assets Amount withdrawn from Convex, denominated in
    /// collateral-token units.
    ///
    /// @dev Callable only by the owner while the market is fully paused and the
    /// strategy is active. The exit does not claim rewards or change
    /// credit-account collateral accounting. It clears the Booster allowance
    /// and permanently disables new Convex deposits, while preserving repayment
    /// and eventual LP withdrawal or foreclosure paths.
    function emergencyExitConvex() external returns (uint256 assets);
}
