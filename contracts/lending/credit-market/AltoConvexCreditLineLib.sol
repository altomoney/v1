// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAltoCreditMarketErrors} from "../interfaces/IAltoCreditMarket.sol";
import {IAltoConvexCreditLineErrors, IAltoConvexCreditLineEvents} from "../interfaces/IAltoConvexCreditLine.sol";
import {IConvexBooster} from "../interfaces/vendor/IConvexBooster.sol";
import {IConvexRewardPool} from "../interfaces/vendor/IConvexRewardPool.sol";

/// @title Alto Convex Credit Line Library
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Stateless Convex custody and reward operations for AltoConvexCreditLineMarket
library AltoConvexCreditLineLib {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_REWARD_TOKENS = 16;

    /// @notice Validates Convex initialization inputs and returns the pool contracts used by the market
    function validateConvexInitialization(
        address convexBooster,
        uint256 convexPoolId,
        address collateralToken,
        address rewardRecipient,
        uint256 rewardTokenCount
    ) external view returns (address depositToken, address rewardPool) {
        if (convexBooster == address(0) || rewardRecipient == address(0)) {
            revert IAltoCreditMarketErrors.AltoCreditMarketZeroAddress();
        }

        address lpToken;
        address gauge;
        bool shutdown;
        (lpToken, depositToken, gauge, rewardPool,, shutdown) = IConvexBooster(convexBooster).poolInfo(convexPoolId);

        if (lpToken == address(0) || depositToken == address(0) || gauge == address(0) || rewardPool == address(0)) {
            revert IAltoCreditMarketErrors.AltoCreditMarketZeroAddress();
        }
        if (shutdown || lpToken != collateralToken) {
            revert IAltoCreditMarketErrors.AltoCreditMarketInvalidInput();
        }

        IConvexRewardPool rewards = IConvexRewardPool(rewardPool);
        if (
            rewards.pid() != convexPoolId || rewards.operator() != convexBooster
                || rewards.stakingToken() != depositToken || rewardTokenCount == 0
        ) {
            revert IAltoCreditMarketErrors.AltoCreditMarketInvalidInput();
        }
    }

    /// @notice Deposits received collateral into Convex and verifies the resulting balances
    function depositCollateralToConvex(
        address collateralToken,
        address convexBooster,
        uint256 convexPoolId,
        address convexRewardPool,
        uint256 assets,
        uint256 idleBefore
    ) external {
        IERC20 lpToken = IERC20(collateralToken);
        if (lpToken.balanceOf(address(this)) - idleBefore != assets) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta();
        }

        uint256 stakedBefore = IConvexRewardPool(convexRewardPool).balanceOf(address(this));
        bool success = IConvexBooster(convexBooster).deposit(convexPoolId, assets, true);
        if (!success) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed();
        }

        uint256 idleAfter = lpToken.balanceOf(address(this));
        if (
            idleAfter != idleBefore
                || IConvexRewardPool(convexRewardPool).balanceOf(address(this)) - stakedBefore != assets
        ) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta();
        }

        emit IAltoConvexCreditLineEvents.CollateralStaked(msg.sender, assets);
    }

    /// @notice Withdraws and unwraps collateral from Convex
    function withdrawAndUnwrapCollateral(address collateralToken, address convexRewardPool, uint256 assets) external {
        IERC20 lpToken = IERC20(collateralToken);
        uint256 idleBefore = lpToken.balanceOf(address(this));
        bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
        if (!success) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed();
        }

        if (lpToken.balanceOf(address(this)) - idleBefore != assets) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta();
        }
    }

    /// @notice Claims and forwards every configured reward token
    function claimRewards(address convexRewardPool, address recipient, address[] storage rewardTokens)
        external
        returns (uint256[] memory claimedAmounts)
    {
        bool success = IConvexRewardPool(convexRewardPool).getReward(address(this), true);
        if (!success) {
            revert IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed();
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

            emit IAltoConvexCreditLineEvents.RewardsClaimed(msg.sender, recipient, address(token), amount);
        }
    }

    /// @notice Withdraws the full Convex position into idle collateral
    function emergencyWithdraw(address collateralToken, address convexRewardPool) external returns (uint256 assets) {
        assets = IConvexRewardPool(convexRewardPool).balanceOf(address(this));
        if (assets != 0) {
            uint256 idleBefore = IERC20(collateralToken).balanceOf(address(this));
            bool success = IConvexRewardPool(convexRewardPool).withdrawAndUnwrap(assets, false);
            if (!success) {
                revert IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed();
            }

            if (IERC20(collateralToken).balanceOf(address(this)) - idleBefore != assets) {
                revert IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta();
            }
        }
    }

    /// @notice Validates a token before it is added to the reward forwarding list
    function validateRewardTokenAddition(
        uint256 rewardTokenCount,
        bool tokenAlreadyAdded,
        address token,
        address collateralToken,
        address borrowToken,
        address convexDepositToken
    ) external view {
        if (token == address(0)) {
            revert IAltoCreditMarketErrors.AltoCreditMarketZeroAddress();
        }
        if (
            token.code.length == 0 || rewardTokenCount >= MAX_REWARD_TOKENS || token == collateralToken
                || token == borrowToken || token == convexDepositToken || tokenAlreadyAdded
        ) {
            revert IAltoCreditMarketErrors.AltoCreditMarketInvalidInput();
        }
    }

    /// @notice Removes a non-primary token with no pending market balance
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
            revert IAltoCreditMarketErrors.AltoCreditMarketInvalidInput();
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
            revert IAltoCreditMarketErrors.AltoCreditMarketInvalidInput();
        }

        uint256 lastIndex = tokenCount - 1;
        if (tokenIndex != lastIndex) {
            rewardTokens[tokenIndex] = rewardTokens[lastIndex];
        }
        rewardTokens.pop();
        delete isRewardToken[token];
    }
}
