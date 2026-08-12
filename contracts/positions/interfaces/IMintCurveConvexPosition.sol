// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMintCurveConvexPositionFactory} from "./IMintCurveConvexPositionFactory.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

interface IMintCurveConvexPositionErrors {
    /// @notice Thrown when the caller is neither the owner nor an authorized spender.
    error MintCurveConvexPositionUnauthorized();

    /// @notice Thrown when inputs are invalid (e.g. zero amounts, zero addresses).
    error MintCurveConvexPositionInvalidInput();

    /// @notice Thrown when attempting to renounce ownership, which is permanently disabled.
    error MintCurveConvexPositionRenounceDisabled();

    /// @notice Thrown when staking Curve LP through the Convex booster returns false.
    error MintCurveConvexPositionStakingFailed();

    /// @notice Thrown when withdrawing/unwrapping staked LP from the Convex reward pool returns false.
    error MintCurveConvexPositionWithdrawalFromConvexRewardPoolFailed();

    /// @notice Thrown when claiming rewards from the Convex reward pool returns false.
    error MintCurveConvexPositionClaimingRewardsFailed();
}

interface IMintCurveConvexPositionEvents {
    /// @notice Emitted when collateral is added to the mint market for this position
    /// @param amount The amount of collateral added.
    event CollateralAdded(uint256 amount);

    /// @notice Emitted when collateral is withdrawn from the mint market to the owner.
    /// @param amount The amount of collateral withdrawn.
    event CollateralRemoved(uint256 amount);

    /// @notice Emitted when DUSD is borrowed, supplied one-sided to Curve and staked in Convex.
    /// @param borrowAssets The amount of DUSD borrowed and deposited into Curve.
    /// @param lpStaked The amount of Curve LP received from the deposit to curve and staked in Convex.
    event Deposited(uint256 borrowAssets, uint256 lpStaked);

    /// @notice Emitted when staked LP is unwound from Convex and then Curve back into DUSD.
    /// @param owner The position owner.
    /// @param lpBurned The amount of staked Curve LP withdrawn from Convex and then Curve.
    /// @param dusdReceived The amount of DUSD received from the one-sided Curve removal.
    /// @param repayShares The amount of borrow shares repaid during this call.
    event Withdrawn(address indexed owner, uint256 lpBurned, uint256 dusdReceived, uint256 repayShares);

    /// @notice Emitted when debt is repaid to the mint market for this position.
    /// @param owner The position owner.
    /// @param repayShares The amount of borrow shares repaid.
    /// @param assetsRepaid The amount of DUSD burnt to repay the shares.
    event Repaid(address indexed owner, uint256 repayShares, uint256 assetsRepaid);

    /// @notice Emitted for each nonzero Convex reward transferred to the owner.
    /// @param owner The position owner receiving the reward.
    /// @param token The reward token transferred.
    /// @param amount The amount transferred.
    event RewardClaimed(address indexed owner, address indexed token, uint256 amount);

    /// @notice Emitted when an ERC20 token is recovered from the position to the owner.
    /// @param token The recovered token.
    /// @param amount The amount recovered.
    event ERC20Recovered(address indexed token, uint256 amount);
}

/// @title IMintCurveConvexPosition
/// @notice Interface for the dedicated DUSD -> Curve -> Convex position and its reverse flow.
interface IMintCurveConvexPosition is IMintCurveConvexPositionErrors, IMintCurveConvexPositionEvents {
    /// @notice Factory that stores the shared MintCurveConvex strategy configuration for this position.
    function factory() external view returns (IMintCurveConvexPositionFactory);

    /// @notice Alto mint market where this position adds collateral and mints DUSD.
    /// @dev Once set, the market cannot be changed.
    function market() external view returns (IMarket);

    /// @notice The Curve/Convex configuration snapshot stored at deployment for this position.
    /// @return curvePool The Curve pool holding DUSD (and one other stable token) as underlying tokens.
    /// @return convexBooster The Convex booster contract used to stake Curve LP.
    /// @return convexRewardPool The Convex reward pool where staked LP and rewards are tracked.
    /// @return convexPid The Convex pool id used when staking the Curve LP.
    /// @return crv The CRV(Curve token) reward token.
    /// @return cvx The CVX(Convex token) reward token.
    function config()
        external
        view
        returns (
            address curvePool,
            address convexBooster,
            address convexRewardPool,
            uint256 convexPid,
            address crv,
            address cvx
        );

    /// @notice The mint market borrow token (DUSD), cached at initialization.
    function borrowToken() external view returns (address);

    /// @notice The index of the borrow token within the two-coin Curve pool, cached at initialization.
    function indexOfBorrowTokenInPool() external view returns (uint256);

    /// @notice Implementation version, bumped when the implementation in beaconis upgraded.
    function version() external view returns (uint256);

    /// @notice The account nominated to become the next owner via {transferOwnership}.
    /// @dev Zero when there is no pending transfer.
    function pendingOwner() external view returns (address);

    /// @notice Nominates `newOwner` as the pending owner; ownership only moves once they call {acceptOwnership}.
    /// @dev Two-step transfer guards against handing the position (and its collateral/debt) to a mistyped address.
    ///      Passing the zero address cancels any in-flight transfer. Callable only by the current owner.
    /// @param newOwner The account nominated to take over ownership.
    function transferOwnership(address newOwner) external;

    /// @notice Accepts a pending ownership transfer, making the caller the new owner.
    /// @dev Callable only by the address previously set as `pendingOwner`.
    function acceptOwnership() external;

    /// @notice Permanently disabled; always reverts with {MintCurveConvexPositionRenounceDisabled}.
    /// @dev An ownerless position could never manage or unwind its market collateral and debt, nor
    ///      withdraw its staked LP from Convex and Curve, permanently stranding all of its funds.
    function renounceOwnership() external;

    /// @notice Pulls collateral from the owner and deposits it into the mint market.
    /// @param amount The amount of collateral to add.
    function addCollateral(uint256 amount) external;

    /// @notice Withdraws collateral from the mint market directly to the owner.
    /// @param amount The amount of collateral to withdraw.
    function removeCollateral(uint256 amount) external;

    /// @notice Borrows DUSD, supplies it one-sided to the Curve pool and stakes the curve LP tokens in Convex.
    /// @param borrowAssets The amount of DUSD to borrow and deposit into Curve.
    /// @param minLpOut The minimum amount of Curve LP expected from the deposit.
    /// @return lpStaked The amount of Curve LP tokens received from the deposit and staked in Convex.
    function borrowAndDepositToLp(uint256 borrowAssets, uint256 minLpOut) external returns (uint256 lpStaked);

    /// @notice Unwinds staked LP from Convex/Curve into the borrow token and optionally repays debt.
    /// @dev Any borrow token left after the optional repayment is transferred to the owner.
    /// @dev if debt to be repaid is greater than amount of borrow token received from burning the LP,
    ///      then the remaining debt is pulled from the owner.
    /// @param lpToWithdraw The amount of staked Curve LP to withdraw from Convex. Pass 0 to skip the LP unwind.
    /// @param minBorrowTokenOut The minimum amount of borrow token expected from the one-sided Curve removal.
    /// @param sharesToRepay The amount of borrow shares to repay. Pass 0 to skip repayment.
    /// @param claimRewards Whether to also claim all Convex rewards during the Convex withdrawal.
    /// @return borrowTokenReceived The amount of borrow token received from burning the LP.
    /// @return assetsRepaid The amount of borrow token used to repay `sharesToRepay` (0 if sharesToRepay is 0).
    /// @return rewardTokens The complete deduplicated reward-token list (empty if claimRewards is false).
    /// @return rewardAmounts The amount of each corresponding reward token transferred to the owner.
    function withdrawFromLpAndRepay(
        uint256 lpToWithdraw,
        uint256 minBorrowTokenOut,
        uint256 sharesToRepay,
        bool claimRewards
    )
        external
        returns (
            uint256 borrowTokenReceived,
            uint256 assetsRepaid,
            address[] memory rewardTokens,
            uint256[] memory rewardAmounts
        );

    /// @notice Repays debt to the mint market, pulling any DUSD shortfall from the owner.
    /// @param repayShares The exact amount of borrow shares to repay.
    /// @return assetsRepaid The amount of DUSD used to repay `repayShares`.
    function repay(uint256 repayShares) external returns (uint256 assetsRepaid);

    /// @notice Claims all accrued Convex rewards and transfers them to the owner.
    /// @return tokens The complete deduplicated reward-token list queried from Convex at claim time.
    /// @return amounts The amount of each corresponding reward token transferred to the owner.
    function claimRewards() external returns (address[] memory tokens, uint256[] memory amounts);

    /// @notice Recovers ERC20 tokens held by this position to the owner.
    /// @param token The token to recover.
    /// @param amount The amount to recover.
    function recoverERC20(address token, uint256 amount) external;
}
