// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

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

/// @dev Claim data struct
struct ClaimData {
    /// @dev The total rewards for the user
    uint256 totalRewardsForUser;
    /// @dev The discount on rewards purchase
    uint256 discount;
    /// @dev The id of the reward
    uint256 id;
    /// @dev The expiration timestamp of the reward
    uint256 expirationTimestamp;
}

/// @title IRewardsErrors
/// @notice Interface containing all error definitions for the RewardsDistributor
interface IRewardsErrors {
    /// @notice Error thrown when executor is not allowed to perform the action on behalf of another user
    error AltoRewardsDistributorUnauthorized();
    /// @notice Error thrown when the input is invalid
    error AltoRewardsDistributorInvalidInput();
    /// @notice Error thrown when the input is invalid
    error AltoRewardsDistributorInvalidAdapterPaymentTokenShare();
    /// @notice Error thrown when the lock contract is not set and user is trying to lock rewards
    error AltoRewardsDistributorLockContractNotSet();
    /// @notice Error thrown when the lock rewards oracle is not set and user is trying to lock rewards
    error AltoRewardsDistributorLockRewardsOracleNotSet();
    /// @notice Error thrown when the oracle returns an invalid price (0)
    error AltoRewardsDistributorLockInvalidOraclePrice();
}

/// @title IRewardsEvents
/// @notice Interface containing all event definitions for the RewardsDistributor
interface IRewardsEvents {
    /// @notice Emitted when a user claims and purchases reward tokens
    /// @param caller The account that called the claimPurchase function
    /// @param onBehalf The account on behalf of whom the purchase is being made
    /// @param id The id of the reward
    /// @param rewardTokenAmount The amount of reward tokens purchased
    /// @param paymentToken The payment token address
    /// @param paymentTokenAmount The amount of payment tokens used
    /// @param discount The discount applied to the rewards
    event ClaimRewardTokens(
        address indexed caller,
        address indexed onBehalf,
        uint256 indexed id,
        uint256 rewardTokenAmount,
        address paymentToken,
        uint256 paymentTokenAmount,
        uint256 discount
    );

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

interface IRewardsDistributorBase is IRewardsErrors, IRewardsEvents, IAuth, IPausable {
    /// @notice Returns the amount of reward tokens already purchased by an account
    /// @param account The account to check
    /// @param id The id of the reward
    /// @return The amount purchased
    function purchasedRewardTokenUser(address account, uint256 id) external view returns (uint256);

    /// @notice The reward token oracle address
    /// @dev The oracle is used to get the price of the reward token in USD when claiming
    /// the rewards
    /// @dev it returns price with USD_ORACLE_PRICE_PRECISION precision
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
    ///  @param claimData The claim data used to validate the claim
    /// @param proof The merkle proof that validates this claim
    /// @param rewardsPurchaseAmount The amount of reward tokens to purchase
    /// @param paymentToken The token to use for payment
    /// @param lockPurchasedRewards Whether to lock the purchased tokens for extra discount
    /// @param maxEpochsToLockFor The maximum number of epochs to lock for. Useful when max epochs are updated
    /// during UI interaction and UI shows an old number of epochs to lock for.
    /// @param onBehalf The address on behalf of whom the claim is being made
    /// @return amount The amount of payment tokens used
    function claimRewardTokens(
        ClaimData memory claimData,
        bytes32[] calldata proof,
        uint256 rewardsPurchaseAmount,
        address paymentToken,
        bool lockPurchasedRewards,
        uint256 maxEpochsToLockFor,
        address onBehalf
    ) external returns (uint256 amount);

    /// @notice Sets a payment token and its oracle
    /// @dev This contract is not compatible with transfer-tax tokens as
    /// paymentToken. If these token types are used for any purpose
    /// within the contract, this will result in down-stream issues and
    /// inherently break the accounting.
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

    /// @notice Withdraws tokens from the contract
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    /// @dev This function is used to withdraw tokens from the contract.
    /// @dev It is used primarily to withdraw the payment tokens and secondarily
    /// to withdraw the reward token in case of contract change or other reasons.
    function withdrawContractTokens(address token, uint256 amount) external;

    /// @notice Whitelists an adapter
    /// @param adapter The adapter to whitelist
    /// @dev This function is used to whitelist an adapter.
    /// @dev Adapters are trusted contracts and we don't need to check for reentrancy.
    /// @dev Adapters' getBonusRewardInfo should be using as little gas as possible.
    /// GAS CONSUMPTION HAS TO BE CHECKED BEFORE THE ADAPTER IS WHITELISTED.
    function whitelistAdapter(address adapter) external;

    /// @notice Removes an adapter from the whitelist
    /// @param adapter The adapter to remove from the whitelist
    function revokeAdapter(address adapter) external;
}

/// @dev This interface is inherited by the RewardsDistributor so that function signatures are checked by the
/// @dev Consider using the IRewardsDistributor interface instead of this one.
interface IRewardsDistributorStaticTypes is IRewardsDistributorBase {
    /// @notice The reward token configuration
    /// @dev IMMUTABLE!
    function REWARD_TOKEN() external view returns (address token, uint8 decimals);

    /// @notice Returns the approved payment token configuration for specific token
    /// @param token The payment token address
    /// @dev Payment token is used to pay for the reward token
    function paymentTokens(address token) external view returns (address oracle, uint8 decimals);

    /// @notice The adapters whitelist
    /// @dev This holds the list of trusted contract addresses that implement the IRewardsAdapter interface
    /// @dev Adapters are used when claiming rewards to provide additional discounts and payment token sharing functionality
    function adaptersWhitelist(uint256 index) external view returns (address);
}

/// @title IRewardsDistributor
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree
/// @dev Use this interface for RewardsDistributor to have access to all the functions with the appropriate
/// function signatures.
interface IRewardsDistributor is IRewardsDistributorBase {
    /// @notice The reward token configuration
    /// @dev IMMUTABLE!
    function REWARD_TOKEN() external view returns (RewardToken memory);

    /// @notice Returns the payment token configuration
    /// @param token The payment token address
    /// @return PaymentToken struct composed by oracle address and token decimals
    function paymentTokens(address token) external view returns (PaymentToken memory);

    /// @notice The adapters whitelist
    /// @dev This holds the list of trusted contract addresses that implement the IRewardsAdapter interface
    /// @dev Adapters are used when claiming rewards to provide additional discounts and payment token sharing functionality
    function adaptersWhitelist() external view returns (address[] memory);
}
