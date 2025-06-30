// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice The pending root struct for a merkle tree distribution during the timelock.
struct PendingRoot {
    /// @dev The submitted pending root.
    bytes32 root;
    /// @dev The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    bytes32 ipfsHash;
    /// @dev The timestamp at which the pending root can be accepted.
    uint256 validAt;
}

/// @dev Payment token configuration struct
struct PaymentToken {
    address oracle;
    uint8 decimals;
}


interface IOracle {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

interface ILock {
    function lock(uint256 amount, address to) external;
}

/// @title IRewardsErrors
/// @notice Interface containing all error definitions for the RewardsDistributor
interface IRewardsErrors {
    /// @notice Thrown when the caller is not the owner
    error NotOwner();
    /// @notice Thrown when the caller does not have the updater role
    error NotUpdaterRole();
    /// @notice Thrown when the caller is not the AltoRewardsOptions contract
    error NotAltoRewardsOptions();
    /// @notice Thrown when a pending root already exists with the same values
    error AlreadyPending();
    /// @notice Thrown when there is no pending root to accept or revoke
    error NoPendingRoot();
    /// @notice Thrown when attempting to accept a root before the timelock expires
    error TimelockNotExpired();
    /// @notice Thrown when the merkle root is not set
    error RootNotSet();
    /// @notice Thrown when the merkle proof is invalid or the claim has expired
    error InvalidProofOrExpired();
    /// @notice Thrown when a value is already set to the requested value
    error AlreadySet();
    /// @notice Thrown when attempting unauthorized root changes
    error UnauthorizedRootChange();
    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();
    /// @notice Thrown when a claim has expired
    error ExpiredClaim();
    /// @notice Thrown when the purchase amount is invalid (zero or exceeds available)
    error InvalidPurchaseAmount();
    /// @notice Thrown when the payment token is not configured
    error InvalidPaymentToken();
    /// @notice Thrown when the oracle has invalid decimals (not 8)
    error InvalidOracleDecimals();
    /// @notice Thrown when the reward price is not set
    error PriceNotSet();
    /// @notice Thrown when the oracle returns an invalid price (<=0)
    error InvalidOraclePrice();
    /// @notice Thrown when a price parameter is invalid
    error InvalidPrice();
    /// @notice Thrown when a discount exceeds the maximum allowed (100%)
    error InvalidDiscount();
    /// @notice Thrown when the lock contract is not set but locking is requested
    error LockNotSet();
}

/// @title IRewardsEvents
/// @notice Interface containing all event definitions for the RewardsDistributor
interface IRewardsEvents {
    /// @notice Emitted when a pending root is submitted
    /// @param updater The address that submitted the pending root
    /// @param root The new merkle root
    /// @param ipfsHash The IPFS hash containing metadata about the root
    event PendingRootSet(address indexed updater, bytes32 indexed root, bytes32 ipfsHash);
    
    /// @notice Emitted when a root is accepted and set
    /// @param root The new merkle root
    /// @param ipfsHash The IPFS hash containing metadata about the root
    event RootSet(bytes32 indexed root, bytes32 ipfsHash);
    
    /// @notice Emitted when a pending root is revoked
    /// @param updater The address that revoked the pending root
    event PendingRootRevoked(address indexed updater);
    
    /// @notice Emitted when a user claims and purchases reward tokens
    /// @param caller The account that called the claimPurchase function
    /// @param onBehalf The account on behalf of whom the purchase is being made
    /// @param reward The reward token address
    /// @param amount The amount of reward tokens purchased
    event PurchaseClaimed(address indexed caller, address indexed onBehalf, address indexed reward, uint256 amount);
    
    /// @notice Emitted when the owner is set
    /// @param owner The new owner address
    event OwnerSet(address indexed owner);
    
    /// @notice Emitted when the timelock is updated
    /// @param timelock The new timelock duration in seconds
    event TimelockSet(uint256 timelock);
    
    /// @notice Emitted when a root updater is added or removed
    /// @param updater The updater address
    /// @param active Whether the updater is active or not
    event RootUpdaterSet(address indexed updater, bool active);
    
    /// @notice Emitted when the AltoRewardsOptions contract is set
    /// @param altoRewardsOptions The AltoRewardsOptions contract address
    event AltoRewardsOptionsSet(address indexed altoRewardsOptions);
    
    /// @notice Emitted when a payment token is configured
    /// @param token The payment token address
    /// @param oracle The oracle address for the token
    event PaymentTokenSet(address indexed token, address indexed oracle);
    
    /// @notice Emitted when the reward oracle is set
    /// @param oracle The new reward price oracle address
    event RewardOracleSet(address indexed oracle);
    
    /// @notice Emitted when the reward price is updated
    /// @param price The new reward price in USD
    event RewardPriceSet(uint256 price);
    
    /// @notice Emitted when the discount is updated
    /// @param discount The new discount percentage
    event DiscountSet(uint256 discount);
    
    /// @notice Emitted when the lock bonus discount is updated
    /// @param lockBonusDiscount The new lock bonus discount percentage
    event LockBonusDiscountSet(uint256 lockBonusDiscount);
    
    /// @notice Emitted when the lock contract is set
    /// @param lock The lock contract address
    event LockSet(address indexed lock);
    
    /// @notice Emitted when payment tokens are withdrawn
    /// @param token The token address
    /// @param to The recipient address
    /// @param amount The amount withdrawn
    event PaymentTokenWithdrawn(address indexed token, address indexed to, uint256 amount);
}

interface IRewardsDistributorBase is IRewardsErrors, IRewardsEvents {
    // user facing functions
    
    /// @notice Claims and purchases reward tokens
    /// @param availableToPurchase The overall available amount of token rewards to purchase
    /// @param proof The merkle proof that validates this claim
    /// @param purchaseAmount The amount to purchase (must be <= available - purchased)
    /// @param paymentToken The token to use for payment
    /// @param shouldLock Whether to lock the purchased tokens
    /// @param onBehalf The address on behalf of whom the claim is being made
    /// @return amount The amount of reward tokens purchased
    function claimPurchase(
        uint256 availableToPurchase,
        bytes32[] calldata proof,
        uint256 purchaseAmount,
        address paymentToken,
        bool shouldLock,
        address onBehalf
    ) external returns (uint256 amount);
    
    /// @notice Returns the amount of reward tokens already purchased by an account
    /// @param account The account to check
    /// @return The amount purchased
    function purchased(address account) external view returns (uint256);
    
    // getters
    
    /// @notice The merkle root of this distribution
    function root() external view returns (bytes32);
    
    /// @notice The timelock duration for root updates
    function timelock() external view returns (uint256);
    
    /// @notice The optional IPFS hash containing metadata about the root
    function ipfsHash() external view returns (bytes32);
    
    /// @notice The reward token address
    function rewardToken() external view returns (address);
    
    /// @notice Returns whether an address is a root updater
    /// @param updater The address to check
    /// @return Whether the address is an updater
    function isUpdater(address updater) external view returns (bool);
    
    /// @notice Returns the amount assigned to an account (deprecated, returns 0)
    /// @param account The account to check
    /// @return Always returns 0
    function assigned(address account) external view returns (uint256);
    

    
    /// @notice The reward price in USD (compatibility function)
    /// @return The current reward price from oracle
    function rewardPrice() external view returns (uint256);
    
    /// @notice The discount percentage (in MATH_PRECISION)
    function discount() external view returns (uint256);
    
    /// @notice The additional discount when locking (in MATH_PRECISION)
    function lockBonusDiscount() external view returns (uint256);
    
    /// @notice The lock contract address
    function lockContract() external view returns (address);
    
    // admin ops functions
    
    /// @notice Withdraws tokens from the contract
    /// @param token The token to withdraw
    /// @param to The recipient address
    /// @param amount The amount to withdraw
    function withdrawTokens(address token, address to, uint256 amount) external;
    
    // root admin functions
    
    /// @notice Accepts and sets the current pending merkle root
    /// @dev Can only be called after the timelock has expired
    function acceptRoot() external;
    
    /// @notice Sets the timelock duration for root updates
    /// @param newTimelock The new timelock duration in seconds
    function setTimelock(uint256 newTimelock) external;
    
    /// @notice Sets or removes a root updater
    /// @param updater The address of the root updater
    /// @param active Whether the root updater should be active
    function setRootUpdater(address updater, bool active) external;
    
    /// @notice Revokes the pending root
    /// @dev Can be frontrun with acceptRoot if timelock has passed
    function revokePendingRoot() external;
    
    /// @notice Submits a new merkle root
    /// @param newRoot The new merkle root
    /// @param ipfsHash The optional IPFS hash containing metadata
    function submitRoot(bytes32 newRoot, bytes32 ipfsHash) external;
    
    // admin setter functions
    
    /// @notice Sets a payment token and its oracle
    /// @param token The payment token address
    /// @param oracle The oracle address (0 to remove)
    function setPaymentToken(address token, address oracle) external;
    
    /// @notice Sets the reward price oracle
    /// @param newOracle The new oracle address
    function setRewardOracle(address newOracle) external;
    
    /// @notice Sets the reward price in USD (deprecated, use setRewardOracle)
    /// @param newPrice The new price per unit
    function setRewardPrice(uint256 newPrice) external;
    
    /// @notice Sets the discount percentage
    /// @param newDiscount The new discount (in MATH_PRECISION)
    function setDiscount(uint256 newDiscount) external;
    
    /// @notice Sets the lock bonus discount
    /// @param newLockBonusDiscount The new lock bonus discount (in MATH_PRECISION)
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external;
    
    /// @notice Sets the lock contract address
    /// @param newLockContract The new lock contract address
    function setLockContract(address newLockContract) external;
}

/// @dev This interface is inherited by the RewardsDistributor so that function signatures are checked by the
/// @dev Consider using the IRewardsDistributor interface instead of this one.
interface IRewardsDistributorStaticTyping is IRewardsDistributorBase {
    function pendingRoot() external view returns (bytes32 root, bytes32 ipfsHash, uint256 validAt);

    /// @notice Returns the payment token configuration
    /// @param token The payment token address
    function paymentTokens(address token) external view returns (address oracle, uint8 decimals);
}

/// @title IRewardsDistributor
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree
/// @dev Use this interface for RewardsDistributor to have access to all the functions with the appropriate
/// function signatures.
interface IRewardsDistributor is IRewardsDistributorBase {
    function pendingRoot() external view returns (PendingRoot memory);

    /// @notice Returns the payment token configuration
    /// @param token The payment token address
    /// @return PaymentToken struct composed by oracle address and token decimals
    function paymentTokens(address token) external view returns (PaymentToken memory );
}
