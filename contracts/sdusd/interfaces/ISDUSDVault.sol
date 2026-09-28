// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Initialization parameters for the sDUSD vault
struct SDUSDInitParams {
    /// @notice Address that becomes the initial owner and is also authorized to freeze, unfreeze, pause, and unpause the vault
    address admin;
    /// @notice Additional address authorized to freeze, unfreeze, pause, and unpause the vault
    address pauser;
    /// @notice Address of the DUSD token used as the ERC-4626 underlying asset
    address dusd;
    /// @notice Address authorized to supply protocol rewards through `notifyRewardAmount`
    address rewarder;
    /// @notice Expected number of permanently locked sDUSD shares created by the deployment's seed deposit
    /// @dev Initialization only records this non-zero threshold; it does not transfer DUSD or mint shares.
    ///      After initialization, deployment must deposit the same amount of DUSD into the empty vault with
    ///      `address(1)` as receiver. At the initial 1:1 exchange rate this mints exactly `seedShares`, which
    ///      are treated as irrecoverably locked. The seed prevents supply from returning to zero. New rewards
    ///      require shares held outside address(1), excluding its full balance rather than just the original seed.
    ///      Its value should be chosen against the maximum expected reward batch and minimum supported deposit
    ///      so that a supported deposit still mints at least one share.
    ///      A larger value improves that rounding bound but permanently locks more DUSD.
    uint256 seedShares;
    /// @notice DUSD asset limit for new deposits, excluding the fixed initial seed amount
    /// @dev Released rewards consume capacity but may grow assets beyond the cap. Locked rewards and raw
    ///      donations are excluded. The owner may later update this limit with `setDepositCap`.
    uint256 depositCap;
    /// @notice Duration over which each notified reward amount is released linearly, from 1 to 30 days
    uint256 rewardDuration;
}

/// @title ISDUSDVaultErrors
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Errors for the sDUSD vault
interface ISDUSDVaultErrors {
    /// @notice Thrown when a provided address is the zero address
    error SDUSDZeroAddress();

    /// @notice Thrown when a setter is called with a value equal to the current one
    error SDUSDNoStateChange();

    /// @notice Thrown when `notifyRewardAmount` is called by an address other than the configured rewarder
    error SDUSDNotRewarder();

    /// @notice Thrown when `notifyRewardAmount` is called before the active reward release period has finished
    error SDUSDRewardPeriodNotFinished();

    /// @notice Thrown when `notifyRewardAmount` is called with a zero amount
    error SDUSDZeroAmount();

    /// @notice Thrown when a non-zero asset deposit would mint zero shares
    error SDUSDZeroShares();

    /// @notice Thrown when the reward duration is set outside of the allowed bounds
    error SDUSDInvalidRewardDuration();

    /// @notice Thrown when the permanent lock address holds fewer shares than the configured seed requirement
    error SDUSDNotSeeded();

    /// @notice Thrown when `notifyRewardAmount` is called while all shares are held by address(1),
    ///         including any shares deposited or transferred there after the initial seed
    error SDUSDNoActiveStakers();
}

/// @title ISDUSDVaultEvents
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Events for the sDUSD vault
interface ISDUSDVaultEvents {
    /// @notice Emitted when a new reward amount is notified and a fresh linear release period starts
    /// @param amount The amount of DUSD added as rewards
    /// @param periodFinish The timestamp at which the new release period ends
    event RewardAdded(uint256 amount, uint256 periodFinish);

    /// @notice Emitted when unaccounted DUSD is recovered to the configured rewarder
    /// @param receiver The configured rewarder that received the recovered DUSD
    /// @param amount The amount of unaccounted DUSD recovered
    event UnaccountedAssetsRecovered(address indexed receiver, uint256 amount);

    /// @notice Emitted when the rewarder address is updated
    event RewarderUpdated(address indexed oldRewarder, address indexed newRewarder);

    /// @notice Emitted when the reward duration is updated
    event RewardDurationUpdated(uint256 oldDuration, uint256 newDuration);

    /// @notice Emitted when the DUSD asset deposit cap is updated
    event DepositCapUpdated(uint256 oldDepositCap, uint256 newDepositCap);
}

/// @title ISDUSDVaultBase
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice State-changing and view functions of the sDUSD vault beyond ERC-4626
interface ISDUSDVaultBase is ISDUSDVaultErrors, ISDUSDVaultEvents {
    /// @notice Initializes the UUPS-upgradeable sDUSD vault
    function initialize(SDUSDInitParams calldata params) external;

    /// @notice Notifies the vault of a new DUSD reward amount to release linearly
    /// @param amount The amount of DUSD reward being added
    /// @dev Callable only by the configured rewarder while reward notification is not paused. `amount` must be nonzero,
    ///      the previous period must have fully finished, address(1) must hold at least `seedShares`, and total supply
    ///      must exceed the full balance of address(1) so at least one share exists outside the permanent lock.
    ///      This participation condition is evaluated only when the period starts; it does not require any holder to
    ///      remain until the period finishes. When shares are redeemed during an active period, rewards that have not
    ///      yet unlocked continue releasing to the remaining supply. If all shares outside address(1) are redeemed,
    ///      the remaining rewards increase the assets backing only address(1)'s irrecoverably locked shares.
    ///      The vault pulls `amount` DUSD from the rewarder via `transferFrom`, so the rewarder must approve the vault
    ///      beforehand. A successful call starts a fresh release period. Rewards from an active period are never
    ///      rolled over or retroactively diluted.
    function notifyRewardAmount(uint256 amount) external;

    /// @notice Recovers all DUSD received outside the vault's accounted deposit and reward flows
    /// @dev Only callable by the owner. Always sends recovered DUSD to the configured rewarder.
    ///      The recoverable amount is `DUSD.balanceOf(address(this)) - accountedAssets`; using `accountedAssets`
    ///      rather than `totalAssets()` prevents locked rewards from being recovered during an active period.
    /// @return recoveredAssets The amount of unaccounted DUSD sent to the configured rewarder
    function recoverUnaccountedAssets() external returns (uint256 recoveredAssets);

    /// @notice Updates the rewarder allowed to call `notifyRewardAmount`
    function setRewarder(address newRewarder) external;

    /// @notice Updates the linear reward release duration used for the next reward period
    /// @dev May be updated while a reward period is active. The update does not alter the active period's
    ///      `periodStart`, `rewardPeriodFinish`, locked rewards, or release rate; it is read only when the next
    ///      successful `notifyRewardAmount` call starts a new period.
    function setRewardDuration(uint256 newRewardDuration) external;

    /// @notice Updates the DUSD asset limit for new deposits, excluding the fixed initial seed amount
    /// @dev Only callable by the owner. May be set to zero or below current usage, immediately preventing new
    ///      deposits and mints without affecting withdrawals, redemptions, or reward accrual.
    function setDepositCap(uint256 newDepositCap) external;

    /// @notice The amount of reward DUSD still locked and not yet counted in `totalAssets`
    function lockedRewardsRemaining() external view returns (uint256);

    /// @notice The reward amount notified at the start of the current release period
    function rewardsForPeriod() external view returns (uint256);

    /// @notice The timestamp at which the current release period started
    function periodStart() external view returns (uint256);

    /// @notice Timestamp at which the current linear reward release period ends
    function rewardPeriodFinish() external view returns (uint256);

    /// @notice The configured linear release duration that will be applied to the next reward period
    /// @dev During an active period this value may differ from `rewardPeriodFinish() - periodStart()`. The
    ///      active period's duration must be derived from those two timestamps.
    function rewardDuration() external view returns (uint256);

    /// @notice The address allowed to call `notifyRewardAmount`
    function rewarder() external view returns (address);

    /// @notice DUSD accounted as belonging to the vault, excluding raw token donations
    /// @dev Includes staked principal (deposits minus withdrawals) and all reward DUSD received through
    ///      `notifyRewardAmount`, whether locked or already released. Raw DUSD transfers are deliberately not
    ///      tracked, so donations cannot inflate `totalAssets` outside the linear release schedule and may be
    ///      returned to the configured rewarder through `recoverUnaccountedAssets`.
    function accountedAssets() external view returns (uint256);

    /// @notice The minimum share amount deployment must mint to address(1) through an explicit seed deposit
    /// @dev Deployment must deposit this amount of DUSD with address(1) as the receiver. Those shares are
    ///      irrecoverably locked, so `totalSupply()` can never fall below this value. A new reward release is
    ///      only permitted while shares exist outside address(1). This condition is checked at period start,
    ///      and does not prevent holders from exiting during the release. Any rewards still locked when all
    ///      outside shares exit will release solely to the shares held by address(1), permanently increasing
    ///      the assets represented by those inaccessible shares.
    function seedShares() external view returns (uint256);

    /// @notice DUSD asset limit for new deposits, excluding the fixed initial seed amount
    /// @dev Released rewards consume capacity. This limit applies only to deposits and mints, so rewards
    ///      may increase usage beyond it without affecting withdrawals or redemptions.
    function depositCap() external view returns (uint256);

    /// @notice Current accounted asset value counted against `depositCap`
    /// @dev Equals `totalAssets()` minus the fixed DUSD amount of the exact initial seed deposit, floored at zero.
    ///      Only an initial deposit of exactly `seedShares` DUSD minting that many shares to address(1) receives
    ///      the exemption. Other deposits, later deposits to address(1), and all released rewards consume capacity.
    ///      Locked rewards and raw donations are excluded, and share transfers do not change usage.
    ///      Withdrawals and redemptions reduce usage by the DUSD paid out. No principal basis is tracked.
    function depositCapUsage() external view returns (uint256);

    /// @notice The minimum allowed reward release duration
    function MIN_REWARD_DURATION() external view returns (uint256);

    /// @notice The maximum allowed reward release duration
    function MAX_REWARD_DURATION() external view returns (uint256);
}

/// @title ISDUSDVault
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Full non-ERC4626 interface of the sDUSD vault
interface ISDUSDVault is ISDUSDVaultBase {}

/// @title ISDUSDVaultStaticTypes
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Static-typed view of the sDUSD vault contract
interface ISDUSDVaultStaticTypes is ISDUSDVaultBase {}
