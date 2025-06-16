// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IRewardsDistributor, IOracle, ILock} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PendingRoot} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {RewardErrorsLib} from "@alto/rewards/libraries/RewardErrorsLib.sol";
import {RewardEventsLib} from "@alto/rewards/libraries/RewardEventsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

bytes32 constant CLAIM_PAUSE_TYPE = keccak256("CLAIM_PAUSE");

/// @title RewardsDistributor
/// @author Alto
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree.
contract RewardsDistributor is IRewardsDistributor, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @notice The reward token address.
    address public immutable rewardToken;

    /// @notice The reward token decimals.
    uint8 public immutable rewardTokenDecimals;

    /* STORAGE */

    /// @notice The merkle root of this distribution.
    bytes32 public root;

    /// @notice The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    bytes32 public ipfsHash;

    /// @notice The `amount` of reward token already assigned to `account`.
    mapping(address account => uint256 amount) public assigned;

    /// @notice The `amount` of reward token already purchased by `account`.
    mapping(address account => uint256 amount) public purchased;

    /// @notice Payment token configuration (token address => oracle address).
    mapping(address token => address oracle) public paymentTokens;

    /// @notice Payment token decimals cache (token address => decimals).
    mapping(address token => uint8) public paymentTokenDecimals;

    /// @notice The price per unit of reward token in USD (8 decimals).
    uint256 public rewardPrice;

    /// @notice The discount percentage (basis points, e.g., 1000 = 10%).
    uint256 public discount;

    /// @notice The additional discount when locking (basis points).
    uint256 public lockBonusDiscount;

    /// @notice The lock contract address.
    address public lockContract;

    /// @notice The addresses that can update the merkle root.
    mapping(address => bool) public isUpdater;

    /// @notice The timelock related to root updates.
    uint256 public timelock;

    /// @notice The pending root of the distribution.
    /// @dev If the pending root is set, the root can be updated after the timelock has expired.
    /// @dev The pending root is skipped if the timelock is set to 0.
    PendingRoot internal _pendingRoot;

    /* MODIFIERS */

    /// @notice Reverts if the caller has not the updater role.
    modifier onlyUpdaterRole() {
        if (!isUpdater[msg.sender] && msg.sender != owner()) revert RewardErrorsLib.NotUpdaterRole();
        _;
    }

    /// @dev Modifier to check if the RewardsDistributor is not paused.
    modifier whenNotPaused() {
        if (paused[CLAIM_PAUSE_TYPE]) {
            revert IPausable.IsPaused(CLAIM_PAUSE_TYPE);
        }
        _;
    }

    /// @notice Initializes the contract.
    /// @param initialOwner The initial owner of the contract.
    /// @param initialTimelock The initial timelock of the contract.
    /// @param initialRoot The initial merkle root.
    /// @param initialIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    /// @param rewardTokenAddress The reward token address.
    /// @dev Warning: The `initialIpfsHash` might not correspond to the `initialRoot`.
    constructor(
        address initialOwner,
        uint256 initialTimelock,
        bytes32 initialRoot,
        bytes32 initialIpfsHash,
        address rewardTokenAddress
    ) Ownable(initialOwner) {
        if (rewardTokenAddress == address(0)) revert RewardErrorsLib.ZeroAddress();
        rewardToken = rewardTokenAddress;
        rewardTokenDecimals = IERC20Metadata(rewardTokenAddress).decimals();
        _setTimelock(initialTimelock);
        _setRoot(initialRoot, initialIpfsHash);
        _setPauser(initialOwner, CLAIM_PAUSE_TYPE, true);
    }

    /* USER FACING */

    /// @notice Claims and purchases reward tokens.
    /// @param availableToPurchase The overall available amount of token rewards to purchase.
    /// @param proof The merkle proof that validates this claim.
    /// @param purchaseAmount The amount to purchase (must be <= available - purchased).
    /// @param paymentToken The token to use for payment.
    /// @param lockTokens Whether to lock the purchased tokens.
    /// @return amount The amount of reward tokens purchased.
    function claimPurchase(
        uint256 availableToPurchase,
        bytes32[] calldata proof,
        uint256 purchaseAmount,
        address paymentToken,
        bool lockTokens
    ) external whenNotPaused returns (uint256 amount) {
        if (root == bytes32(0)) revert RewardErrorsLib.RootNotSet();
        if (
            !MerkleProof.verifyCalldata(
                proof, root, keccak256(bytes.concat(keccak256(abi.encode(msg.sender, availableToPurchase))))
            )
        ) revert RewardErrorsLib.InvalidProofOrExpired();

        assigned[msg.sender] = availableToPurchase;

        // Check that user hasn't already purchased their full allocation
        uint256 remainingToPurchase = assigned[msg.sender] - purchased[msg.sender];
        if (purchaseAmount == 0 || purchaseAmount > remainingToPurchase) revert RewardErrorsLib.InvalidPurchaseAmount();

        // Update purchased amount
        purchased[msg.sender] += purchaseAmount;

        // Calculate payment
        uint256 paymentAmount = _calculatePaymentAmount(purchaseAmount, paymentToken, lockTokens);

        // Transfer payment from user
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);

        // Lock or transfer reward tokens
        if (lockTokens) {
            if (lockContract == address(0)) revert RewardErrorsLib.LockNotSet();
            IERC20(rewardToken).forceApprove(lockContract, purchaseAmount);
            ILock(lockContract).lock(purchaseAmount, msg.sender);
        } else {
            IERC20(rewardToken).safeTransfer(msg.sender, purchaseAmount);
        }

        emit RewardEventsLib.PurchaseClaimed(msg.sender, rewardToken, purchaseAmount);

        return purchaseAmount;
    }

    /* EXTERNAL */

    /// @notice Submits a new merkle root.
    /// @param newRoot The new merkle root.
    /// @param newIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function submitRoot(bytes32 newRoot, bytes32 newIpfsHash) external onlyUpdaterRole {
        if (newRoot == _pendingRoot.root && newIpfsHash == _pendingRoot.ipfsHash) {
            revert RewardErrorsLib.AlreadyPending();
        }

        _pendingRoot = PendingRoot({root: newRoot, ipfsHash: newIpfsHash, validAt: block.timestamp + timelock});

        emit RewardEventsLib.PendingRootSet(msg.sender, newRoot, newIpfsHash);
    }

    /// @notice Accepts and sets the current pending merkle root.
    /// @dev This function can only be called after the timelock has expired.
    /// @dev Anyone can call this function.
    function acceptRoot() external {
        if (_pendingRoot.validAt == 0) revert RewardErrorsLib.NoPendingRoot();
        if (block.timestamp < _pendingRoot.validAt) revert RewardErrorsLib.TimelockNotExpired();

        _setRoot(_pendingRoot.root, _pendingRoot.ipfsHash);
    }

    /// @notice Revokes the pending root.
    /// @dev Can be frontrunned with `acceptRoot` in case the timelock has passed.
    function revokePendingRoot() external onlyUpdaterRole {
        if (_pendingRoot.validAt == 0) revert RewardErrorsLib.NoPendingRoot();

        delete _pendingRoot;

        emit RewardEventsLib.PendingRootRevoked(msg.sender);
    }

    /// @notice Sets payment token and its oracle.
    /// @param token The payment token address.
    /// @param oracle The oracle address for the token (0 to remove).
    function setPaymentToken(address token, address oracle) external onlyOwner {
        if (IOracle(oracle).latestAnswer() <= 0) revert RewardErrorsLib.InvalidOraclePrice();
        if (IOracle(oracle).decimals() != 8) revert RewardErrorsLib.InvalidOracleDecimals();

        paymentTokens[token] = oracle;
        paymentTokenDecimals[token] = IERC20Metadata(token).decimals();

        emit RewardEventsLib.PaymentTokenSet(token, oracle);
    }

    /// @notice Sets the reward price in USD (8 decimals).
    /// @param newPrice The new price per unit.
    function setRewardPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert RewardErrorsLib.InvalidPrice();
        rewardPrice = newPrice;
        emit RewardEventsLib.RewardPriceSet(newPrice);
    }

    /// @notice Sets the discount percentage.
    /// @param newDiscount The new discount in basis points.
    function setDiscount(uint256 newDiscount) external onlyOwner {
        if (newDiscount > 10000) revert RewardErrorsLib.InvalidDiscount();
        discount = newDiscount;
        emit RewardEventsLib.DiscountSet(newDiscount);
    }

    /// @notice Sets the lock bonus discount.
    /// @param newLockBonusDiscount The new lock bonus discount in basis points.
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external onlyOwner {
        if (newLockBonusDiscount > 10000) revert RewardErrorsLib.InvalidDiscount();
        lockBonusDiscount = newLockBonusDiscount;
        emit RewardEventsLib.LockBonusDiscountSet(newLockBonusDiscount);
    }

    /// @notice Sets the lock contract address.
    /// @param newLockContract The new lock contract address.
    function setLockContract(address newLockContract) external onlyOwner {
        lockContract = newLockContract;
        emit RewardEventsLib.LockSet(newLockContract);
    }

    /// @notice Sets the timelock of a given distribution.
    /// @param newTimelock The new timelock.
    /// @dev This function can only be called by the owner of the distribution.
    /// @dev The timelock modification are not applicable to the pending values.
    function setTimelock(uint256 newTimelock) external onlyOwner {
        if (newTimelock == timelock) revert RewardErrorsLib.AlreadySet();

        _setTimelock(newTimelock);
    }

    /// @notice Sets the root updater of a given distribution.
    /// @param updater The address of the root updater.
    /// @param active Whether the root updater should be active or not.
    function setRootUpdater(address updater, bool active) external onlyOwner {
        if (isUpdater[updater] == active) revert RewardErrorsLib.AlreadySet();

        isUpdater[updater] = active;

        emit RewardEventsLib.RootUpdaterSet(updater, active);
    }

    /// @notice Withdraws tokens from the contract.
    /// @param token The token to withdraw.
    /// @param to The recipient address.
    /// @param amount The amount to withdraw.
    function withdrawTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit RewardEventsLib.PaymentTokenWithdrawn(token, to, amount);
    }

    /* INTERNAL */

    /// @dev Calculates the payment amount in payment token.
    function _calculatePaymentAmount(uint256 purchaseAmount, address paymentToken, bool shouldLock)
        internal
        view
        returns (uint256)
    {
        if (paymentTokens[paymentToken] == address(0)) revert RewardErrorsLib.InvalidPaymentToken();
        if (rewardPrice == 0) revert RewardErrorsLib.PriceNotSet();

        // Get payment token price from oracle (always 8 decimals)
        IOracle oracle = IOracle(paymentTokens[paymentToken]);
        int256 tokenPrice = oracle.latestAnswer();
        if (tokenPrice <= 0) revert RewardErrorsLib.InvalidOraclePrice();

        // Calculate base cost in USD
        // purchaseAmount is in reward token decimals
        // rewardPrice has 8 decimals
        // Result needs to be in USD with 8 decimals
        uint256 baseCostUSD = FixedPointMath.divideWithRounding(
            purchaseAmount * rewardPrice,
            1,
            10 ** rewardTokenDecimals,
            true // round up to avoid zero payment
        );

        // Apply discount - either base discount OR lock bonus discount, not both
        uint256 appliedDiscount = shouldLock ? lockBonusDiscount : discount;
        uint256 discountedCostUSD = baseCostUSD * (10000 - appliedDiscount) / 10000;

        // Convert to payment token amount
        // discountedCostUSD has 8 decimals
        // tokenPrice has 8 decimals (oracle standard)
        // Result should have paymentDecimals decimals
        uint256 paymentAmount = FixedPointMath.divideWithRounding(
            discountedCostUSD * (10 ** paymentTokenDecimals[paymentToken]),
            1,
            uint256(tokenPrice),
            true // round up to ensure we never underpay
        );

        // Ensure payment amount is never zero for non-zero purchase
        if (paymentAmount == 0 && purchaseAmount != 0) revert RewardErrorsLib.InvalidPurchaseAmount();

        return paymentAmount;
    }

    /// @dev Sets the `root` and `ipfsHash` to `newRoot` and `newIpfsHash`.
    /// @dev Deletes the pending root.
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function _setRoot(bytes32 newRoot, bytes32 newIpfsHash) internal {
        root = newRoot;
        ipfsHash = newIpfsHash;

        delete _pendingRoot;

        emit RewardEventsLib.RootSet(newRoot, newIpfsHash);
    }

    /// @dev Sets the `timelock` to `newTimelock`.
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;

        emit RewardEventsLib.TimelockSet(newTimelock);
    }

    // Compatibility function for interface - maps to assigned
    function claimed(address account) external view returns (uint256) {
        return assigned[account];
    }

    // Getter function for pendingRoot to match interface
    function pendingRoot() external view returns (PendingRoot memory) {
        return _pendingRoot;
    }
}
