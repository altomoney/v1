// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IConvexBooster} from "@alto/lending/interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";

/// @title Alto Convex Credit Line Library
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Stateless Convex custody and reward operations for AltoConvexCreditLineMarket
/// @dev Linked functions execute in the calling market's context, so `address(this)` and storage refer to the market.
/// @custom:audit Pending
library AltoConvexCreditLineLib {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_REWARD_TOKENS = 16;

    /// @notice Validates the Convex pool configuration used to initialize the market.
    /// @dev Confirms that the pool is active, matches the collateral token and is internally consistent with its
    /// reward pool. The calling market separately validates the reward-token list.
    /// @param convexBooster The Convex Booster that registers and accepts deposits for the pool.
    /// @param convexPoolId The identifier of the pool registered in the Convex Booster.
    /// @param collateralToken The Curve LP token used as market collateral.
    /// @param rewardRecipient The account configured to receive claimed reward tokens.
    /// @return convexDepositToken The Convex deposit token associated with the pool.
    /// @return convexRewardPool The Convex reward pool in which collateral will be staked.
    function validateConvexInitialization(
        address convexBooster,
        uint256 convexPoolId,
        address collateralToken,
        address rewardRecipient
    ) external view returns (address convexDepositToken, address convexRewardPool) {
        if (convexBooster == address(0) || rewardRecipient == address(0)) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress();
        }

        (address lpToken, address depositToken, address gauge, address rewardPool,, bool shutdown) =
            IConvexBooster(convexBooster).poolInfo(convexPoolId);

        if (lpToken == address(0) || depositToken == address(0) || gauge == address(0) || rewardPool == address(0)) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress();
        }
        if (shutdown || lpToken != collateralToken) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }

        IConvexRewardPool rewards = IConvexRewardPool(rewardPool);
        if (
            rewards.pid() != convexPoolId || rewards.operator() != convexBooster
                || rewards.stakingToken() != depositToken
        ) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }

        return (depositToken, rewardPool);
    }

    /// @notice Requests that Convex deposit collateral held by the market and stake the resulting deposit tokens.
    /// @dev Does not independently verify the resulting collateral or stake balance changes.
    /// @param collateralToken The Curve LP token deposited as collateral.
    /// @param convexBooster The Convex Booster through which the collateral is deposited.
    /// @param convexPoolId The Convex pool identifier used for the deposit.
    /// @param assets The amount of collateral requested for deposit and staking.
    function depositCollateralToConvex(
        address collateralToken,
        address convexBooster,
        uint256 convexPoolId,
        uint256 assets
    ) external {
        IERC20(collateralToken).forceApprove(convexBooster, assets);
        bool success = IConvexBooster(convexBooster).deposit(convexPoolId, assets, true);
        if (!success) {
            revert IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed();
        }

        IERC20(collateralToken).forceApprove(convexBooster, 0);
        emit IAltoConvexCreditLineMarketEvents.CollateralStaked(msg.sender, assets);
    }

    /// @notice Requests withdrawal and unwrapping of collateral from Convex into the market.
    /// @dev Does not independently verify the recovered collateral balance. The caller remains responsible for
    /// transferring the recovered collateral to its final receiver.
    /// @param convexRewardPool The reward pool from which the market withdraws its stake.
    /// @param assets The amount of staked collateral requested for withdrawal and unwrapping.
    function withdrawAndUnwrapCollateral(address convexRewardPool, uint256 assets) external {
        bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
        if (!success) {
            revert IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed();
        }
    }

    /// @notice Claims Convex rewards and forwards every configured reward-token balance to the recipient.
    /// @dev Requests primary and extra rewards, then transfers each token's entire market balance, including any
    /// balance held before the claim. A `RewardsClaimed` event is emitted for every configured token, including zero
    /// amounts.
    /// @param convexRewardPool The reward pool from which rewards are claimed.
    /// @param recipient The account that receives every claimed reward token.
    /// @param rewardTokens The market's configured reward-token list, processed in storage order.
    /// @return claimedAmounts The amount forwarded for each token at the corresponding list index.
    function claimRewards(address convexRewardPool, address recipient, address[] storage rewardTokens)
        external
        returns (uint256[] memory claimedAmounts)
    {
        bool success = IConvexRewardPool(convexRewardPool).getReward(address(this), true);
        if (!success) {
            revert IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed();
        }

        uint256 tokenCount = rewardTokens.length;
        claimedAmounts = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; ++i) {
            IERC20 token = IERC20(rewardTokens[i]);
            uint256 amount = token.balanceOf(address(this));
            claimedAmounts[i] = amount;

            if (amount != 0) {
                token.safeTransfer(recipient, amount);
            }

            emit IAltoConvexCreditLineMarketEvents.RewardsClaimed(msg.sender, recipient, address(token), amount);
        }
    }

    /// @notice Requests withdrawal and unwrapping of the market's entire reported Convex position.
    /// @dev Skips the external withdrawal when no collateral is staked and does not independently verify the recovered
    /// collateral balance.
    /// @param convexRewardPool The reward pool from which the full position is withdrawn.
    /// @return assets The reward-pool stake balance requested for withdrawal.
    function emergencyWithdraw(address convexRewardPool) external returns (uint256 assets) {
        assets = IConvexRewardPool(convexRewardPool).balanceOf(address(this));
        if (assets != 0) {
            bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
            if (!success) {
                revert IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed();
            }
        }
    }

    /// @notice Validates a token before it is added to the reward forwarding list.
    /// @dev Rejects zero addresses, non-contracts, duplicates, reserved market tokens and additions beyond the list
    /// limit.
    /// @param rewardTokenCount The current number of configured reward tokens.
    /// @param tokenAlreadyAdded Whether the token is already present in the reward-token mapping.
    /// @param token The candidate reward-token address.
    /// @param collateralToken The market collateral token, which cannot be added as a reward token.
    /// @param borrowToken The market borrow token, which cannot be added as a reward token.
    /// @param convexRewardPool The Convex reward pool whose staking token cannot be added as a reward token.
    function validateRewardTokenAddition(
        uint256 rewardTokenCount,
        bool tokenAlreadyAdded,
        address token,
        address collateralToken,
        address borrowToken,
        address convexRewardPool
    ) external view {
        if (
            token.code.length == 0 || rewardTokenCount >= MAX_REWARD_TOKENS || token == collateralToken
                || token == borrowToken || token == IConvexRewardPool(convexRewardPool).stakingToken()
                || tokenAlreadyAdded
        ) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }
    }

    /// @notice Removes a non-primary reward token that has no balance held by the market.
    /// @dev Removes the token with swap-and-pop, so the ordering of the remaining list may change. The current primary
    /// reward token cannot be removed.
    /// @param rewardTokens The market's reward-token list.
    /// @param isRewardToken The mapping that records whether a token is configured.
    /// @param convexRewardPool The reward pool used to identify the current primary reward token.
    /// @param token The configured reward token to remove.
    function removeRewardToken(
        address[] storage rewardTokens,
        mapping(address => bool) storage isRewardToken,
        address convexRewardPool,
        address token
    ) external {
        if (
            !isRewardToken[token] || token == IConvexRewardPool(convexRewardPool).rewardToken()
                || IERC20(token).balanceOf(address(this)) != 0
        ) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }

        uint256 tokenCount = rewardTokens.length;
        uint256 tokenIndex = tokenCount;

        for (uint256 i; i < tokenCount; ++i) {
            if (rewardTokens[i] == token) {
                tokenIndex = i;
                break;
            }
        }

        if (tokenIndex == tokenCount) {
            revert IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput();
        }

        uint256 lastIndex = tokenCount - 1;
        if (tokenIndex != lastIndex) {
            rewardTokens[tokenIndex] = rewardTokens[lastIndex];
        }
        rewardTokens.pop();
        delete isRewardToken[token];
    }
}
