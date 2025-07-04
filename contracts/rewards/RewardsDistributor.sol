// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IRewardsDistributorStaticTyping, ILock, IOracle, PaymentToken} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PendingRoot} from "@alto/rewards/interfaces/IRewardsDistributor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IUsdOracle} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {Auth} from "@alto/utils/Auth.sol";

bytes32 constant CLAIM_PAUSE_TYPE = keccak256("CLAIM_PAUSE");


/// @title Rewards Distributor
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree.
contract RewardsDistributor is IRewardsDistributorStaticTyping, Ownable2Step, Pausable, Auth {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

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

    /// @notice The `amount` of reward token already purchased by `account`.
    mapping(address account => uint256 amount) public purchased;

    /// @notice Payment token configuration (token address => PaymentToken struct).
    mapping(address token => PaymentToken paymentToken) public paymentTokens;

    /// @notice The price per unit of reward token in USD (with {USD_ORACLE_PRICE_PRECISION} precision).
    address public rewardOracle;

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

    PendingRoot public pendingRoot;

    /* MODIFIERS */

    /// @notice Reverts if the caller has not the updater role.
    modifier onlyUpdaterRole() {
        if (!isUpdater[msg.sender] && msg.sender != owner()) revert NotUpdaterRole();
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
        if (rewardTokenAddress == address(0)) revert ZeroAddress();
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
    /// @param onBehalf The address on behalf of whom the claim is being made.
    /// @param lockBucketId The bucket id to lock the purchased tokens in.
    /// @return amount The amount of reward tokens purchased.
    function claimPurchase(
        uint256 availableToPurchase,
        bytes32[] calldata proof,
        uint256 purchaseAmount,
        address paymentToken,
        bool lockTokens,
        address onBehalf,
        uint8 lockBucketId
    ) external whenNotPaused returns (uint256 amount) {
        if (!_isSenderAuthorized(onBehalf)) revert NotOwner();
        if (root == bytes32(0)) revert RootNotSet();
        if (
            !MerkleProof.verifyCalldata(
                proof, root, keccak256(bytes.concat(keccak256(abi.encode(onBehalf, availableToPurchase))))
            )
        ) revert InvalidProofOrExpired();

        // Check that user hasn't already purchased their full allocation
        if (purchaseAmount == 0 || purchaseAmount > availableToPurchase - purchased[onBehalf]) revert InvalidPurchaseAmount();

        // Update purchased amount
        purchased[onBehalf] += purchaseAmount;

        // Calculate payment
        uint256 paymentAmount = _calculatePaymentAmount(purchaseAmount, paymentToken, lockTokens);

        // Transfer payment from user
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);

        // Lock or transfer reward tokens
        if (lockTokens) {
            if (lockContract == address(0)) revert LockNotSet();
            IERC20(rewardToken).forceApprove(lockContract, purchaseAmount);
            ILock(lockContract).participate(onBehalf, purchaseAmount, lockBucketId);
        } else {
            IERC20(rewardToken).safeTransfer(onBehalf, purchaseAmount);
        }

        emit PurchaseClaimed(msg.sender, onBehalf, rewardToken, purchaseAmount);

        return purchaseAmount;
    }

    /* EXTERNAL */

    /// @notice Submits a new merkle root.
    /// @param newRoot The new merkle root.
    /// @param newIpfsHash The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function submitRoot(bytes32 newRoot, bytes32 newIpfsHash) external onlyUpdaterRole {
        if (newRoot == pendingRoot.root && newIpfsHash == pendingRoot.ipfsHash) {
            revert AlreadyPending();
        }

        pendingRoot = PendingRoot({root: newRoot, ipfsHash: newIpfsHash, validAt: block.timestamp + timelock});

        emit PendingRootSet(msg.sender, newRoot, newIpfsHash);
    }

    /// @notice Accepts and sets the current pending merkle root.
    /// @dev This function can only be called after the timelock has expired.
    /// @dev Anyone can call this function.
    function acceptRoot() external {
        if (pendingRoot.validAt == 0) revert NoPendingRoot();
        if (block.timestamp < pendingRoot.validAt) revert TimelockNotExpired();

        _setRoot(pendingRoot.root, pendingRoot.ipfsHash);
    }

    /// @notice Revokes the pending root.
    /// @dev Can be frontrunned with `acceptRoot` in case the timelock has passed.
    function revokePendingRoot() external onlyUpdaterRole {
        if (pendingRoot.validAt == 0) revert NoPendingRoot();

        delete pendingRoot;

        emit PendingRootRevoked(msg.sender);
    }

    /// @notice Sets payment token and its oracle.
    /// @param token The payment token address.
    /// @param oracle The oracle address for the token (0 to remove).
    function setPaymentToken(address token, address oracle) external onlyOwner {
        if (oracle != address(0)) {
            // Validate oracle decimals
            uint8 oracleDecimals = IOracle(oracle).decimals();
            if (oracleDecimals != 8) revert InvalidOracleDecimals();
            
            paymentTokens[token] = PaymentToken({
                oracle: oracle,
                decimals: IERC20Metadata(token).decimals()
            });
        } else {
            delete paymentTokens[token];
        }

        emit PaymentTokenSet(token, oracle);
    }

    /// @notice Sets the reward price in USD (with {USD_ORACLE_PRICE_PRECISION} precision).
    /// @param newOracle The new reward price oracle address.
    function setRewardOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();
        // Validate oracle decimals
        uint8 oracleDecimals = IOracle(newOracle).decimals();
        if (oracleDecimals != 8) revert InvalidOracleDecimals();
        
        rewardOracle = newOracle;
        emit RewardOracleSet(newOracle);
    }

    /// @notice Sets the discount percentage.
    /// @param newDiscount The new discount in basis points.
    function setDiscount(uint256 newDiscount) external onlyOwner {
        if (newDiscount > MATH_PRECISION) revert InvalidDiscount();
        discount = newDiscount;
        emit DiscountSet(newDiscount);
    }

    /// @notice Sets the lock bonus discount.
    /// @param newLockBonusDiscount The new lock bonus discount in basis points.
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external onlyOwner {
        if (newLockBonusDiscount > MATH_PRECISION) revert InvalidDiscount();
        lockBonusDiscount = newLockBonusDiscount;
        emit LockBonusDiscountSet(newLockBonusDiscount);
    }

    /// @notice Sets the lock contract address.
    /// @param newLockContract The new lock contract address.
    function setLockContract(address newLockContract) external onlyOwner {
        lockContract = newLockContract;
        emit LockSet(newLockContract);
    }

    /// @notice Sets the timelock of a given distribution.
    /// @param newTimelock The new timelock.
    /// @dev This function can only be called by the owner of the distribution.
    /// @dev The timelock modification are not applicable to the pending values.
    function setTimelock(uint256 newTimelock) external onlyOwner {
        if (newTimelock == timelock) revert AlreadySet();

        _setTimelock(newTimelock);
    }

    /// @notice Sets the root updater of a given distribution.
    /// @param updater The address of the root updater.
    /// @param active Whether the root updater should be active or not.
    function setRootUpdater(address updater, bool active) external onlyOwner {
        if (isUpdater[updater] == active) revert AlreadySet();

        isUpdater[updater] = active;

        emit RootUpdaterSet(updater, active);
    }

    /// @notice Withdraws tokens from the contract.
    /// @param token The token to withdraw.
    /// @param to The recipient address.
    /// @param amount The amount to withdraw.
    function withdrawTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit PaymentTokenWithdrawn(token, to, amount);
    }

    /* INTERNAL */

    /// @dev Calculates the payment amount in payment token.
    function _calculatePaymentAmount(uint256 purchaseAmount, address paymentToken, bool shouldLock)
        internal
        view
        returns (uint256)
    {
        PaymentToken memory paymentTokenConfig = paymentTokens[paymentToken];
        if (paymentTokenConfig.oracle == address(0)) revert InvalidPaymentToken();
        if (rewardOracle == address(0)) revert PriceNotSet();

        // Get prices from oracles (always 8 decimals precision)
        int256 rewardPriceInt = IOracle(rewardOracle).latestAnswer();
        int256 tokenPriceInt = IOracle(paymentTokenConfig.oracle).latestAnswer();
        
        if (rewardPriceInt <= 0) revert InvalidOraclePrice();
        if (tokenPriceInt <= 0) revert InvalidOraclePrice();
        
        uint256 rewardPriceValue = uint256(rewardPriceInt);
        uint256 tokenPrice = uint256(tokenPriceInt);

        // Calculate base cost in USD
        // purchaseAmount is in reward token decimals
        // rewardPrice has 8 decimals precision
        // Result needs to be in USD with 8 decimals precision
        uint256 baseCostUSD = FixedPointMath.divideWithRounding(
            purchaseAmount * rewardPriceValue,
            1,
            10 ** rewardTokenDecimals,
            true // round up to avoid zero payment
        );

        // Apply discount using MATH_PRECISION
        uint256 appliedDiscount = shouldLock ? lockBonusDiscount : discount;
        uint256 discountedCostUSD = baseCostUSD.multiplyWithPrecision(MATH_PRECISION - appliedDiscount);

        // Convert to payment token amount
        // discountedCostUSD has 8 decimals precision
        // tokenPrice has 8 decimals precision
        // Result should have paymentDecimals decimals
        uint256 paymentAmount = FixedPointMath.divideWithRounding(
            discountedCostUSD * (10 ** paymentTokenConfig.decimals),
            1,
            tokenPrice,
            true // round up to ensure we never underpay
        );

        // When discount results in zero payment due to rounding, allow it
        // This can happen with very high discounts (close to 100%)

        return paymentAmount;
    }

    /// @dev Sets the `root` and `ipfsHash` to `newRoot` and `newIpfsHash`.
    /// @dev Deletes the pending root.
    /// @dev Warning: The `newIpfsHash` might not correspond to the `newRoot`.
    function _setRoot(bytes32 newRoot, bytes32 newIpfsHash) internal {
        root = newRoot;
        ipfsHash = newIpfsHash;

        delete pendingRoot;

        emit RootSet(newRoot, newIpfsHash);
    }

    /// @dev Sets the `timelock` to `newTimelock`.
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;

        emit TimelockSet(newTimelock);
    }

    // Compatibility function for interface - removed assigned mapping
    function assigned(address) external pure returns (uint256) {
        return 0;
    }

    // Compatibility function for interface - maps to rewardOracle
    function rewardPrice() external view returns (uint256) {
        if (rewardOracle == address(0)) return 0;
        int256 price = IOracle(rewardOracle).latestAnswer();
        return price > 0 ? uint256(price) : 0;
    }


    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status) external override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }
}
