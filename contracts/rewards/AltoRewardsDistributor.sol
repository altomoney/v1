// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    IRewardsDistributorStaticTypes,
    PaymentToken,
    RewardToken,
    IRewardsDistributorBase
} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {MerkleRootManager} from "@alto/rewards/MerkleRootManager.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IAltoStakingBase} from "@alto/staking/interfaces/IAltoStaking.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IUsdOracle} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {Auth} from "@alto/utils/Auth.sol";
import {IRewardsAdapter, BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";

bytes32 constant CLAIM_PAUSE_TYPE = keccak256("CLAIM_PAUSE");

/// @title Rewards Distributor
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract for distributing rights to purchase tokens to users determined by a merkle tree.
contract AltoRewardsDistributor is IRewardsDistributorStaticTypes, MerkleRootManager, Ownable2Step, Pausable, Auth {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    /// @inheritdoc IRewardsDistributorStaticTypes
    RewardToken public REWARD_TOKEN;

    /// @inheritdoc IRewardsDistributorBase
    mapping(address account => uint256 amount) public purchasedRewardTokenUser;

    /// @inheritdoc IRewardsDistributorStaticTypes
    mapping(address token => PaymentToken paymentToken) public paymentTokens;

    /// @inheritdoc IRewardsDistributorBase
    address public rewardTokenUsdOracle;

    /// @inheritdoc IRewardsDistributorBase
    uint256 public constant MAX_DISCOUNT = 0.5 ether;

    /// @inheritdoc IRewardsDistributorBase
    uint256 public lockBonusDiscount;

    /// @inheritdoc IRewardsDistributorBase
    address public lockContract;

    /// @inheritdoc IRewardsDistributorBase
    uint256 public constant MAX_ADAPTERS_WHITELIST = 10;

    address[] public adaptersWhitelist;

    /// @notice Implementation of abstract function from MerkleRootManager
    function _getOwner() internal view override returns (address) {
        return owner();
    }

    /// @dev Modifier to check if the AltoRewardsDistributor is not paused.
    modifier whenNotPaused() {
        if (paused[CLAIM_PAUSE_TYPE]) {
            revert IPausable.IsPaused(CLAIM_PAUSE_TYPE);
        }
        _;
    }

    /// @notice Initializes the contract.
    /// @param _owner The initial owner of the contract.
    /// @param _merkleRootTimelock The initial timelock of the contract.
    /// @param _rewardTokenAddress The reward token address.
    constructor(address _owner, uint256 _merkleRootTimelock, address _rewardTokenAddress) Ownable(_owner) {
        if (_rewardTokenAddress == address(0)) {
            revert AltoRewardsDistributorInvalidInput();
        }

        REWARD_TOKEN =
            RewardToken({token: _rewardTokenAddress, decimals: IERC20Metadata(_rewardTokenAddress).decimals()});
        _setMerkleRootTimelock(_merkleRootTimelock);
        _setPauser(_owner, CLAIM_PAUSE_TYPE, true);
    }

    /// @inheritdoc IRewardsDistributorBase
    function claimRewardTokens(
        uint256 totalRewardsForUser,
        bytes32[] calldata proof,
        uint256 rewardsPurchaseAmount,
        uint256 discount,
        address paymentToken,
        bool lockPurchasedRewards,
        uint256 maxEpochsToLockFor,
        address onBehalf
    ) external whenNotPaused returns (uint256 amount) {
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoRewardsDistributorUnauthorized();
        }

        if (lockPurchasedRewards && lockContract == address(0)) {
            revert AltoRewardsDistributorLockContractNotSet();
        }

        if (
            !_verifyProof(proof, keccak256(bytes.concat(keccak256(abi.encode(onBehalf, totalRewardsForUser, discount)))))
        ) {
            revert AltoRewardsDistributorInvalidInput();
        }

        if (
            rewardsPurchaseAmount == 0
                || rewardsPurchaseAmount > totalRewardsForUser - purchasedRewardTokenUser[onBehalf]
                || onBehalf == address(0)
        ) {
            revert AltoRewardsDistributorInvalidInput();
        }

        // Update purchased amount
        purchasedRewardTokenUser[onBehalf] += rewardsPurchaseAmount;

        // Get discount from adapters
        uint256 adapterDiscountTotal = 0;
        uint256 adapterPaymentTokenShareTotal = 0;

        BonusRewardInfo[] memory bonusRewardInfos = new BonusRewardInfo[](adaptersWhitelist.length);

        for (uint256 i = 0; i < adaptersWhitelist.length; i++) {
            // Adapters are trusted contracts - we shouldn't need to check for reentrancy
            // Adapters' getBonusRewardInfo should be using as little gas as possible
            bonusRewardInfos[i] = IRewardsAdapter(adaptersWhitelist[i]).getBonusRewardInfo(onBehalf);
            adapterDiscountTotal += bonusRewardInfos[i].bonusDiscount;
            adapterPaymentTokenShareTotal += bonusRewardInfos[i].paymentTokenShare;
        }

        discount = discount + adapterDiscountTotal;

        if (lockPurchasedRewards) {
            discount = discount + lockBonusDiscount;
        }

        if (discount > MAX_DISCOUNT) {
            discount = MAX_DISCOUNT;
        }

        if (adapterPaymentTokenShareTotal > MATH_PRECISION) {
            revert AltoRewardsDistributorInvalidAdapterPaymentTokenShare();
        }

        // Calculate payment
        uint256 paymentAmount = _calculatePaymentAmount(rewardsPurchaseAmount, discount, paymentToken);

        // Transfer payment from user
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);

        for (uint256 i = 0; i < adaptersWhitelist.length; i++) {
            address receiver = bonusRewardInfos[i].paymentTokenShareReceiver;
            uint256 paymentTokenShare = bonusRewardInfos[i].paymentTokenShare;
            if (receiver == address(0) || receiver == address(this) || paymentTokenShare == 0) {
                continue;
            }
            IERC20(paymentToken).safeTransfer(receiver, paymentTokenShare.multiplyWithPrecision(paymentAmount));
        }

        // Lock or transfer reward tokens
        if (lockPurchasedRewards) {
            IERC20(REWARD_TOKEN.token).forceApprove(lockContract, rewardsPurchaseAmount);
            IAltoStakingBase(lockContract).lock(
                onBehalf,
                rewardsPurchaseAmount,
                IAltoStakingBase(lockContract).maxMultiplierStakingContainerId(),
                false,
                maxEpochsToLockFor
            );
        } else {
            IERC20(REWARD_TOKEN.token).safeTransfer(onBehalf, rewardsPurchaseAmount);
        }

        emit ClaimRewardTokens(msg.sender, onBehalf, paymentToken, paymentAmount, rewardsPurchaseAmount, discount);

        return paymentAmount;
    }

    /// @inheritdoc IRewardsDistributorBase
    function setPaymentToken(address token, address oracle) external onlyOwner {
        if (oracle != address(0)) {
            paymentTokens[token] = PaymentToken({oracle: oracle, decimals: IERC20Metadata(token).decimals()});
        } else {
            delete paymentTokens[token];
        }

        emit SetPaymentToken(token, oracle);
    }

    /// @inheritdoc IRewardsDistributorBase
    function setRewardTokenUsdOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) {
            revert AltoRewardsDistributorInvalidInput();
        }
        rewardTokenUsdOracle = newOracle;
        emit SetRewardTokenUsdOracle(newOracle);
    }

    /// @inheritdoc IRewardsDistributorBase
    function setLockBonusDiscount(uint256 newLockBonusDiscount) external onlyOwner {
        if (newLockBonusDiscount > MAX_DISCOUNT) {
            revert AltoRewardsDistributorInvalidInput();
        }
        lockBonusDiscount = newLockBonusDiscount;
        emit SetLockBonusDiscount(newLockBonusDiscount);
    }

    /// @inheritdoc IRewardsDistributorBase
    function setLockContract(address newLockContract) external onlyOwner {
        lockContract = newLockContract;
        emit SetLockContract(newLockContract);
    }

    /// @inheritdoc IRewardsDistributorBase
    function withdrawContractTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit WithdrawContractTokens(token, msg.sender, amount);
    }

    /// @inheritdoc IRewardsDistributorBase
    function whitelistAdapter(address adapter) external onlyOwner {
        if (adaptersWhitelist.length >= MAX_ADAPTERS_WHITELIST || adapter == address(0)) {
            revert AltoRewardsDistributorInvalidInput();
        }

        for (uint256 i = 0; i < adaptersWhitelist.length; i++) {
            if (adaptersWhitelist[i] == adapter) {
                revert AltoRewardsDistributorInvalidInput();
            }
        }

        adaptersWhitelist.push(adapter);
        emit WhitelistAdapter(adapter);
    }

    /// @inheritdoc IRewardsDistributorBase
    function revokeAdapter(address adapter) external onlyOwner {
        for (uint256 i = 0; i < adaptersWhitelist.length; i++) {
            if (adaptersWhitelist[i] == adapter) {
                adaptersWhitelist[i] = adaptersWhitelist[adaptersWhitelist.length - 1];
                adaptersWhitelist.pop();
                emit RevokeAdapter(adapter);
                return;
            }
        }

        revert AltoRewardsDistributorInvalidInput();
    }

    /// @dev Calculates the payment amount in payment token.
    function _calculatePaymentAmount(uint256 rewardsPurchaseAmount, uint256 discount, address paymentToken)
        internal
        view
        returns (uint256)
    {
        PaymentToken memory paymentTokenConfig = paymentTokens[paymentToken];
        if (paymentTokenConfig.oracle == address(0)) {
            revert AltoRewardsDistributorInvalidInput();
        }

        if (rewardTokenUsdOracle == address(0)) {
            revert AltoRewardsDistributorLockRewardsOracleNotSet();
        }

        // Get prices from oracles (always 8 decimals precision)
        uint256 rewardPriceValue = IUsdOracle(rewardTokenUsdOracle).getPrice();
        uint256 tokenPrice = IUsdOracle(paymentTokenConfig.oracle).getPrice();

        if (rewardPriceValue == 0 || tokenPrice == 0) {
            revert AltoRewardsDistributorLockInvalidOraclePrice();
        }

        // Calculate reward requested to purchase in USD
        uint256 rewardToPurchaseCostUsd = rewardsPurchaseAmount.divideWithRounding(
            rewardPriceValue,
            10 ** REWARD_TOKEN.decimals,
            true // round up to avoid zero payment
        );

        // Apply discount using MATH_PRECISION
        rewardToPurchaseCostUsd = rewardToPurchaseCostUsd.multiplyWithPrecision(MATH_PRECISION - discount);

        // Convert to payment token amount
        // Result should have paymentDecimals decimals
        uint256 paymentAmount = rewardToPurchaseCostUsd.divideWithRounding(
            10 ** paymentTokenConfig.decimals,
            tokenPrice,
            true // round up to ensure we never underpay
        );

        // When discount results in zero payment due to rounding, allow it
        // This can happen with very high discounts (close to 100%)

        return paymentAmount;
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status)
        external
        override(Pausable, IPausable)
        onlyOwner
    {
        _setPauser(pauser, pauseType, status);
    }
}
