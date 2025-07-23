// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice The pending root struct for a merkle tree distribution during the timelock.
struct PendingMerkleRoot {
    /// @dev The submitted pending root.
    bytes32 merkleRoot;
    /// @dev The timestamp from which the pending root can be accepted.
    uint256 validFrom;
}

/// @notice The reward token struct of the token to be distributed
struct RewardToken {
    /// @dev The reward token address
    address token;
    /// @dev The cached reward token decimals
    uint8 decimals;
}

/// @dev Payment token configuration struct
struct PaymentToken {
    /// @dev The USD oracle address
    address oracle;
    /// @dev The cached payment token decimals
    uint8 decimals;
}

/// @dev temporary before we have staking contract
interface ILock {
    function lock(uint256 amount, address to) external;
}

/// @title IRewardsErrors
/// @notice Interface containing all error definitions for the RewardsDistributor
interface IRewardsErrors {
    /// @notice Error thrown when executor is not allowed to perform the action on behalf of another user
    error AltoRewardsDistributorUnauthorized();
    /// @notice Error thrown when executor does not have the merkle root updater role
    error AltoRewardsDistributorNotMerkleRootUpdater();
    /// @notice Error thrown when the input is invalid
    error AltoRewardsDistributorInvalidInput();
    /// @notice Error thrown when the input is invalid
    error AltoRewardsDistributorInvalidAdapterPaymentTokenShare();
    /// @notice Error thrown when the merkle root is not set and user is trying to claim rewards
    error AltoRewardsDistributorMerkleRootNotSet();
    /// @notice Error thrown when the lock contract is not set and user is trying to lock rewards
    error AltoRewardsDistributorLockContractNotSet();
    /// @notice Error thrown when the lock rewards oracle is not set and user is trying to lock rewards
    error AltoRewardsDistributorLockRewardsOracleNotSet();
    /// @notice Error thrown when the oracle returns an invalid price (0)
    error AltoRewardsDistributorLockInvalidOraclePrice();
    /// @notice Error thrown when a pending root already exists with the same values
    error AltoRewardsDistributorAlreadyPending();
    /// @notice Error thrown when the timelock has not expired yet
    error AltoRewardsDistributorTimelockNotExpired();
    /// @notice Error thrown when the pending root is not set
    error AltoRewardsDistributorPendingRootNotSet();
}

/// @title IRewardsEvents
/// @notice Interface containing all event definitions for the RewardsDistributor
interface IRewardsEvents {
    /// @notice Emitted when a user claims and purchases reward tokens
    /// @param caller The account that called the claimPurchase function
    /// @param onBehalf The account on behalf of whom the purchase is being made
    /// @param paymentToken The payment token address
    /// @param paymentTokenAmount The amount of payment tokens used
    /// @param rewardTokenAmount The amount of reward tokens purchased
    event ClaimRewardTokens(
        address indexed caller,
        address indexed onBehalf,
        address paymentToken,
        uint256 paymentTokenAmount,
        uint256 rewardTokenAmount,
        uint256 discount
    );

    /// @notice Emitted when a pending root is submitted
    /// @param updater The address that submitted the pending root
    /// @param root The new merkle root
    event SubmitPendingMerkleRoot(address indexed updater, bytes32 indexed root);

    /// @notice Emitted when a root is accepted and set
    /// @param root The new merkle root
    event AcceptPendingMerkleRoot(address indexed executor, bytes32 indexed root);

    /// @notice Emitted when a pending root is revoked
    /// @param updater The address that revoked the pending root
    /// @param root The revoked merkle root
    event RevokePendingMerkleRoot(address indexed updater, bytes32 indexed root);

    /// @notice Emitted when a payment token is configured
    /// @param token The payment token address
    /// @param oracle The oracle address for the token
    event SetPaymentToken(address indexed token, address indexed oracle);

    /// @notice Emitted when the reward oracle is set
    /// @param oracle The new reward price oracle address
    event SetRewardTokenUsdOracle(address indexed oracle);

    /// @notice Emitted when the lock bonus discount is updated
    /// @param lockBonusDiscount The new lock bonus discount percentage
    /// @dev The lock bonus discount is in MATH_PRECISION precision. It does not have
    /// to be higher than discount (even if it doesn't make sense for user to lock to get
    /// lower discount). This gives some flexiblity to the initial release of the
    /// protocol.
    event SetLockBonusDiscount(uint256 lockBonusDiscount);

    /// @notice Emitted when the lock contract is set
    /// @param lockContract The lock contract address
    /// @dev setting this to 0 will disable the lock functionality when claiming rewards.
    event SetLockContract(address lockContract);

    /// @notice Emitted when the timelock is updated
    /// @param timelock The new timelock duration in seconds
    event SetMerkleRootTimelock(uint256 timelock);

    /// @notice Emitted when a root updater is added or removed
    /// @param updater The updater address
    /// @param active Whether the updater is active or not
    event SetMerkleRootUpdater(address indexed updater, bool active);

    /// @notice Emitted when tokens are withdrawn
    /// @param token The token address
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event WithdrawContractTokens(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when an adapter is whitelisted
    /// @param adapter The adapter address
    event WhitelistAdapter(address indexed adapter);

    /// @notice Emitted when an adapter is revoked
    /// @param adapter The adapter address
    event RevokeAdapter(address indexed adapter);
}

interface IRewardsDistributorBase is IRewardsErrors, IRewardsEvents {
    /// @notice The merkle root used for rewards distribution
    function merkleRoot() external view returns (bytes32);

    /// @notice Returns whether an address is allowed to submit a new merkle root
    /// @param updater The address to check
    /// @return true if the address is allowed to submit a new merkle root
    function isMerkleRootUpdater(address updater) external view returns (bool);

    /// @notice The time after which a pending root can be accepted since it was submitted
    function merkleRootTimelock() external view returns (uint256);

    /// @notice Returns the amount of reward tokens already purchased by an account
    /// @param account The account to check
    /// @return The amount purchased
    function purchasedRewardTokenUser(address account) external view returns (uint256);

    /// @notice The reward token oracle address
    /// @dev The oracle is used to get the price of the reward token in USD when claiming
    /// the rewards
    /// @dev it returns price with 8 decimals
    function rewardTokenUsdOracle() external view returns (address);

    /// @notice The maximum discount that can be applied
    function MAX_DISCOUNT() external view returns (uint256);

    /// @notice The additional discount when locking (in MATH_PRECISION)
    function lockBonusDiscount() external view returns (uint256);

    /// @notice The lock contract address
    function lockContract() external view returns (address);

    /// @notice The maximum number of adapters that can be whitelisted
    function MAX_ADAPTERS_WHITELIST() external view returns (uint256);

    /// @notice Claims and purchases reward tokens
    /// @param totalRewardsForUser The overall available amount of token rewards to purchase
    /// @param proof The merkle proof that validates this claim
    /// @param rewardsPurchaseAmount The amount to purchase (must be <= available - purchased)
    /// @param discount The discount percentage (in MATH_PRECISION)
    /// @param paymentToken The token to use for payment
    /// @param lockPurchasedRewards Whether to lock the purchased tokens for extra discount
    /// @param onBehalf The address on behalf of whom the claim is being made
    /// @return amount The amount of payment tokens used
    function claimRewardTokens(
        uint256 totalRewardsForUser,
        bytes32[] calldata proof,
        uint256 rewardsPurchaseAmount,
        uint256 discount,
        address paymentToken,
        bool lockPurchasedRewards,
        address onBehalf
    ) external returns (uint256 amount);

    /// @notice Submits a new merkle root
    /// @param newMerkleRoot The new merkle root
    function submitNewPendingRoot(bytes32 newMerkleRoot) external;

    /// @notice Accepts and sets the current pending merkle root
    /// @param merkleRootToAccept The root to accept (0 to accept the pending root)
    /// @dev Can only be called after the timelock has expired
    function acceptPendingRoot(bytes32 merkleRootToAccept) external;

    /// @notice Revokes the pending root
    /// @param merkleRootToRevoke The root to revoke (0 to revoke the pending root)
    /// @dev Can be frontrun with acceptPendingRoot if timelock has passed
    function revokePendingRoot(bytes32 merkleRootToRevoke) external;

    /// @notice Sets a payment token and its oracle
    /// @param token The payment token address
    /// @param oracle The oracle address (0 to remove)
    function setPaymentToken(address token, address oracle) external;

    /// @notice Sets the reward price oracle
    /// @param newOracle The new oracle address
    function setRewardTokenUsdOracle(address newOracle) external;

    /// @notice Sets the lock bonus discount
    /// @param newLockBonusDiscount The new lock bonus discount (in MATH_PRECISION)
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external;

    /// @notice Sets the lock contract address
    /// @param newLockContract The new lock contract address
    function setLockContract(address newLockContract) external;

    /// @notice Sets the timelock duration for root updates
    /// @param newTimelock The new timelock duration in seconds
    function setMerkleRootTimelock(uint256 newTimelock) external;

    /// @notice Sets or removes a root updater
    /// @param updater The address of the root updater
    /// @param active Whether the root updater should be active
    function setMerkleRootUpdater(address updater, bool active) external;

    /// @notice Withdraws tokens from the contract
    /// @param token The token to withdraw
    /// @param to The recipient address
    /// @param amount The amount to withdraw
    /// @dev This function is used to withdraw tokens from the contract.
    /// @dev It is used primarily to withdraw the payment tokens and secondarily
    /// to withdraw the reward token in case of contract change or other reasons.
    function withdrawContractTokens(address token, address to, uint256 amount) external;

    /// @notice Whitelists an adapter
    /// @param adapter The adapter to whitelist
    function whitelistAdapter(address adapter) external;

    /// @notice Removes an adapter from the whitelist
    /// @param adapter The adapter to remove from the whitelist
    function revokeAdapter(address adapter) external;
}

/// @dev This interface is inherited by the RewardsDistributor so that function signatures are checked by the
/// @dev Consider using the IRewardsDistributor interface instead of this one.
interface IRewardsDistributorStaticTypes is IRewardsDistributorBase {
    /// @notice Returns the pending merkle root and the timestamp from which it can be accepted
    function pendingMerkleRoot() external view returns (bytes32 root, uint256 validFrom);

    /// @notice The reward token configuration
    /// @dev IMMUTABLE!
    function REWARD_TOKEN() external view returns (address token, uint8 decimals);

    /// @notice Returns the approved payment token configuration for specific token
    /// @param token The payment token address
    /// @dev Payment token is used to pay for the reward token
    function paymentTokens(address token) external view returns (address oracle, uint8 decimals);
}

/// @title IRewardsDistributor
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree
/// @dev Use this interface for RewardsDistributor to have access to all the functions with the appropriate
/// function signatures.
interface IRewardsDistributor is IRewardsDistributorBase {
    function pendingMerkleRoot() external view returns (PendingMerkleRoot memory);

    /// @notice The reward token configuration
    /// @dev IMMUTABLE!
    function REWARD_TOKEN() external view returns (RewardToken memory);

    /// @notice Returns the payment token configuration
    /// @param token The payment token address
    /// @return PaymentToken struct composed by oracle address and token decimals
    function paymentTokens(address token) external view returns (PaymentToken memory);
}
