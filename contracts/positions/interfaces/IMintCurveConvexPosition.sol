// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPositionFactory} from "./IPositionFactory.sol";

/// @notice Parameters for adding to the existing position
/// @dev This params needs to be encoded and passed to the `add(bytes)` function
struct MintCurveConvexAddParams {
    /// @notice collateral amount to add to the mint market
    uint256 collateralAmount;
    /// @notice borrow amount to borrow from the mint market
    uint256 borrowAssets;
    /// @notice swap target approved by the factory and used to swap the DUSD to frxUSD
    address swapTarget;
    /// @notice calldata passed to the swap target
    /// @dev this calldata needs to be generated for the borrowAssets / 2 amount of DUSD to frxUSD
    bytes swapData;
    /// @notice minimum frxUSD expected to be received from the swap
    uint256 minFrxUsdOutFromDusdSwap;
    /// @notice minimum expected curve LP tokens
    uint256 minLpOutFromCurve;
}

/// @notice mode for reducing the existing position
enum MintCurveConvexRemoveMode {
    /// @notice Used for normal reduction of the position
    /// @dev during normal removal, convexLpAmount of lp is pulled out from convex reward pool when greater than 0,
    ///      then tokens are removed from curve pool, then swap is done from frxUSD to DUSD(if frxUsdAmountToSwap is specified),
    ///      debt is repaid in market(if repayShares is specified) and collateral is removed from the market(if collateralAmount is specified)
    NORMAL,
    /// @notice Used for emergancy reduction of the position
    /// @dev during emergency removal, convexLpAmount of lp is pulled out from convex reward pool when greater than 0,
    ///      then tokens are removed from curve pool and underlying tokens received are sent to position owner
    ///      directly without swap or market interaction
    EMERGENCY_UNWIND_LP
}

/// @notice Parameters for reducing the existing position
struct MintCurveConvexRemoveParams {
    /// @notice Unwind mode(either normal or emergancy)
    MintCurveConvexRemoveMode mode;
    /// @notice amount of convex lp tokens staked to remove from reward pool
    /// @dev Pass a specific amount to unwind LP. Pass `0` to skip LP unwind.
    /// @dev after removal and unwrap from convex, it will have curve LP tokens which will be used to remove liquidity from curve pool
    uint256 convexLpAmount;
    /// @notice minimum expected DUSD to be received from curve pool removal
    uint256 minDusdFromCurve;
    /// @notice minimum expected frxUSD to be received from curve pool removal
    uint256 minFrxUsdFromCurve;
    /// @notice frxUSD amount to swap to DUSD.
    /// @dev Pass `0` to skip swapping
    /// @dev this amount will be approved to swap target. So, swapData needs to be generated for this amount
    uint256 frxUsdAmountToSwap;
    /// @notice Swap target to use
    /// @dev this swap target needs to be approved by the factory
    address swapTarget;
    /// @notice Calldata passed to the swap target.
    /// @dev this calldata needs to be generated for the frxUsdAmountToSwap amount of frxUSD to DUSD
    bytes swapData;
    /// @notice minimum expected DUSD to be received from the frxUSD to DUSD swap
    uint256 minDusdOutFromFrxUsdSwap;
    /// @notice Borrow shares to repay. Pass `0` to skip repayment.
    uint256 repayShares;
    /// @notice amount of collateral to withdraw from the mint market
    /// @dev Pass a specific amount. Pass `0` to skip withdrawal
    uint256 collateralAmountToWithdraw;
    /// @notice whether to claim CRV/CVX rewards when withdrawing from Convex
    /// @dev if true, rewards will be claimed and transferred to the owner
    bool claimRewards;
}

interface IMintCurveConvexPositionErrors {
    /// @notice Error thrown when the caller is not the owner or an authorized spender.
    error MintCurveConvexPositionUnauthorized();

    /// @notice Error thrown when inputs or configuration are invalid.
    error MintCurveConvexPositionInvalidInput();
}

interface IMintCurveConvexPositionEvents {
    /// @notice Emitted when collateral is posted and/or the strategy leg is extended.
    /// @param owner The address of the position owner.
    /// @param collateralAmount The amount of collateral added to the mint market.
    /// @param borrowAssets The amount of DUSD borrowed from the mint market.
    /// @param lpStaked The amount of Curve LP staked in Convex.
    event AddPosition(address indexed owner, uint256 collateralAmount, uint256 borrowAssets, uint256 lpStaked);

    /// @notice Emitted when the position is reduced or unwound.
    /// @param owner The address of the position owner.
    /// @param mode The unwind mode used for the removal.
    /// @param convexLpRemoved The amount of staked Curve LP withdrawn from Convex.
    /// @param collateralWithdrawn The amount of collateral withdrawn from the mint market.
    /// @param debtSharesRepaid The amount of borrow shares repaid to the mint market.
    event RemovePosition(
        address indexed owner,
        MintCurveConvexRemoveMode mode,
        uint256 convexLpRemoved,
        uint256 collateralWithdrawn,
        uint256 debtSharesRepaid
    );

    /// @notice Emitted when a swap is performed.
    /// @param sellToken The token being sold.
    /// @param buyToken The token being bought.
    /// @param amountIn The amount of tokens sold.
    /// @param swapTarget The address of the swap target.
    /// @param amountOut The amount of tokens bought.
    event Swap(
        address indexed sellToken, address indexed buyToken, uint256 amountIn, address swapTarget, uint256 amountOut
    );

    /// @notice Emitted when CRV and CVX rewards are claimed and transferred to the owner.
    /// @param owner The address of the position owner.
    /// @param crvAmount The amount of CRV transferred to the owner.
    /// @param cvxAmount The amount of CVX transferred to the owner.
    event ClaimRewards(address indexed owner, uint256 crvAmount, uint256 cvxAmount);
}

interface IMintCurveConvexPositionBase is IMintCurveConvexPositionErrors, IMintCurveConvexPositionEvents {
    /// @notice Factory providing live strategy configuration and swap target approvals.
    /// @dev This position is created using the factory
    function factory() external view returns (IPositionFactory);

    /// @notice Alto mint market where this position adds collateral and mints DUSD.
    function market() external view returns (address);

    /// @notice Claims accrued CRV and CVX rewards and transfers them to the owner.
    function claimRewards() external;
}

interface IMintCurveConvexPosition is IMintCurveConvexPositionBase {}

interface IMintCurveConvexPositionStaticTypes is IMintCurveConvexPositionBase {}
