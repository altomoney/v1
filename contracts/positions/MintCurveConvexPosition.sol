// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PositionBase} from "./PositionBase.sol";
import {IPosition, PositionType} from "./interfaces/IPosition.sol";
import {
    IMintCurveConvexPosition,
    IMintCurveConvexPositionStaticTypes,
    IMintCurveConvexPositionBase,
    MintCurveConvexAddParams,
    MintCurveConvexRemoveMode,
    MintCurveConvexRemoveParams
} from "./interfaces/IMintCurveConvexPosition.sol";
import {IPositionFactory, MintCurveConvexConfig} from "./interfaces/IPositionFactory.sol";
import {ConvexPositionLib} from "./libraries/ConvexPositionLib.sol";
import {CurvePositionLib} from "./libraries/CurvePositionLib.sol";
import {MintPositionLib} from "./libraries/MintPositionLib.sol";
import {SwapPositionLib} from "./libraries/SwapPositionLib.sol";
import {IConvexRewardPool} from "./interfaces/IConvex.sol";

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MintCurveConvexPosition
/// @notice Strategy contract for minting DUSD from mint market and supplying lp to curve and convex
/// @dev This contract needs to be set as the implementation of PositionBeacon contract
contract MintCurveConvexPosition is PositionBase, IMintCurveConvexPositionStaticTypes {
    using SafeERC20 for IERC20;

    /// @inheritdoc IMintCurveConvexPositionBase
    IPositionFactory public factory;

    /// @inheritdoc IMintCurveConvexPositionBase
    address public market;

    uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes a beacon proxy instance for one user.
    /// @param _owner The position owner.
    /// @param _factory The position factory whose configuration this strategy reads at execution time.
    /// @dev This contract will be deployed by position factory through createPosition function
    /// @param _market The Alto mint market used for collateral and DUSD minting.
    function initialize(address _owner, address _factory, address _market) external initializer {
        if (_factory == address(0) || _market == address(0)) revert MintCurveConvexPositionInvalidInput();
        __PositionBase_init(_owner);
        factory = IPositionFactory(_factory);
        market = _market;
    }

    /// @inheritdoc PositionBase
    function _add(bytes calldata data) internal override onlyOwnerOrAuthorized nonReentrant {
        MintCurveConvexAddParams memory params = abi.decode(data, (MintCurveConvexAddParams));
        // revert if neither collateral is to be added nor DUSD is borrowed
        if (params.collateralAmount == 0 && params.borrowAssets == 0) revert MintCurveConvexPositionInvalidInput();

        MintCurveConvexConfig memory config = config();
        address collateralToken = IMarket(market).collateralToken();
        address borrowToken = IMarket(market).borrowToken();
        address positionOwner = owner();

        if (params.collateralAmount > 0) {
            MintPositionLib.addCollateral(market, collateralToken, positionOwner, params.collateralAmount);
        }

        uint256 lpStaked;

        if (params.borrowAssets > 0) {
            MintPositionLib.borrow(market, params.borrowAssets);

            uint256 swapAmount = params.borrowAssets / 2; // swap half of the borrowed DUSD to frxUSD
            _swap(
                borrowToken,
                config.frxUsd,
                swapAmount,
                params.swapTarget,
                params.swapData,
                params.minFrxUsdOutFromDusdSwap
            );

            // @dev this will add liquidity to curve pool with amount of borrowToken(DUSD) and frxUSD present in contract
            // @dev Not using specific amount here because if amount is donated to this contract, it will be used to add liquidity to curve pool
            uint256 borrowTokenLeft = IERC20(borrowToken).balanceOf(address(this));
            uint256 frxLeft = IERC20(config.frxUsd).balanceOf(address(this));

            lpStaked = CurvePositionLib.addLiquidity(
                address(this),
                config.curvePool,
                borrowToken,
                config.frxUsd,
                borrowTokenLeft,
                frxLeft,
                params.minLpOutFromCurve
            );

            ConvexPositionLib.stake(config.convexBooster, config.convexPid, config.curvePool, lpStaked);
        }

        emit AddPosition(positionOwner, params.collateralAmount, params.borrowAssets, lpStaked);
    }

    /// @inheritdoc PositionBase
    function _remove(bytes calldata data) internal override onlyOwnerOrAuthorized nonReentrant {
        MintCurveConvexRemoveParams memory params = abi.decode(data, (MintCurveConvexRemoveParams));

        if (params.mode == MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP) {
            _emergencyUnwindLp(params);
        } else if (params.mode == MintCurveConvexRemoveMode.NORMAL) {
            _removeNormal(params);
        } else {
            revert MintCurveConvexPositionInvalidInput();
        }
    }

    /// @notice Removes the position normally when mode is NORMAL
    function _removeNormal(MintCurveConvexRemoveParams memory params) internal {
        MintCurveConvexConfig memory config = config();
        address borrowToken = IMarket(market).borrowToken();
        address collateralToken = IMarket(market).collateralToken();
        address positionOwner = owner();

        uint256 lpToBurn = params.convexLpAmount;

        if (lpToBurn > 0) {
            ConvexPositionLib.withdraw(config.convexRewardPool, lpToBurn, params.claimRewards);

            if (params.claimRewards) {
                uint256 crvBalance = _transferTokenBalanceIfAny(config.crv);
                uint256 cvxBalance = _transferTokenBalanceIfAny(config.cvx);
                emit ClaimRewards(positionOwner, crvBalance, cvxBalance);
            }

            CurvePositionLib.removeLiquidity(
                config.curvePool,
                borrowToken,
                config.frxUsd,
                lpToBurn,
                params.minDusdFromCurve,
                params.minFrxUsdFromCurve
            );
        }

        _swap(
            config.frxUsd,
            borrowToken,
            params.frxUsdAmountToSwap,
            params.swapTarget,
            params.swapData,
            params.minDusdOutFromFrxUsdSwap
        );

        if (params.repayShares > 0) {
            MintPositionLib.repay(market, borrowToken, 0, params.repayShares);
        }

        if (params.collateralAmountToWithdraw > 0) {
            MintPositionLib.removeCollateral(market, params.collateralAmountToWithdraw, positionOwner);
        }

        _transferTokenBalanceIfAny(borrowToken);
        _transferTokenBalanceIfAny(config.frxUsd);
        _transferTokenBalanceIfAny(collateralToken);

        emit RemovePosition(
            positionOwner,
            MintCurveConvexRemoveMode.NORMAL,
            lpToBurn,
            params.collateralAmountToWithdraw,
            params.repayShares
        );
    }

    /// @notice Removes the position  when mode is EMERGENCY_UNWIND_LP
    function _emergencyUnwindLp(MintCurveConvexRemoveParams memory params) internal {
        MintCurveConvexConfig memory config = config();
        address positionOwner = owner();

        address borrowToken = IMarket(market).borrowToken();

        uint256 lpToBurn = params.convexLpAmount;
        if (lpToBurn > 0) {
            // withdraw from convex reward pool with claim rewards enabled
            ConvexPositionLib.withdraw(config.convexRewardPool, lpToBurn, true);
            // remove liquidity from curve pool with amount of lpToBurn
            CurvePositionLib.removeLiquidity(
                config.curvePool,
                borrowToken,
                config.frxUsd,
                lpToBurn,
                params.minDusdFromCurve,
                params.minFrxUsdFromCurve
            );

            uint256 crvBalance = _transferTokenBalanceIfAny(config.crv);
            uint256 cvxBalance = _transferTokenBalanceIfAny(config.cvx);
            emit ClaimRewards(positionOwner, crvBalance, cvxBalance);
        }

        _transferTokenBalanceIfAny(borrowToken);
        _transferTokenBalanceIfAny(config.frxUsd);
        _transferTokenBalanceIfAny(config.curvePool);

        emit RemovePosition(positionOwner, MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP, lpToBurn, 0, 0);
    }

    /// @notice Swaps tokens from one token to another
    /// @param fromToken The token to swap from
    /// @param toToken The token to swap to
    /// @param amountIn The amount of tokens to swap
    /// @param swapTarget The target to swap through
    /// @param swapData The data to pass to the swap target
    /// @param minAmountOut The minimum amount of tokens to receive
    /// @return amountOut The amount of toToken tokens received
    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address swapTarget,
        bytes memory swapData,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        if (!factory.approvedSwapTarget(swapTarget)) {
            revert MintCurveConvexPositionInvalidInput();
        }

        amountOut =
            SwapPositionLib.swap(address(this), fromToken, toToken, amountIn, swapTarget, swapData, minAmountOut);
        emit Swap(fromToken, toToken, amountIn, swapTarget, amountOut);
    }

    /// @inheritdoc IMintCurveConvexPositionBase
    function claimRewards() external override onlyOwnerOrAuthorized nonReentrant {
        MintCurveConvexConfig memory config = config();
        ConvexPositionLib.claimRewards(config.convexRewardPool);
        address positionOwner = owner();

        uint256 crvBalance = _transferTokenBalanceIfAny(config.crv);
        uint256 cvxBalance = _transferTokenBalanceIfAny(config.cvx);

        emit ClaimRewards(positionOwner, crvBalance, cvxBalance);
    }

    /// @notice Returns the configuration for the mint curve convex position
    function config() internal view returns (MintCurveConvexConfig memory config) {
        config = factory.mintCurveConvexConfig();
    }

    ///@inheritdoc IPosition
    function version() external view virtual override returns (uint256) {
        return 1;
    }

    ///@inheritdoc IPosition
    function positionType() external view virtual override returns (PositionType) {
        return PositionType.MINT_CURVE_CONVEX;
    }

    /// @notice Transfers the contract's full token balance to the position owner.
    /// @param token The token to transfer.
    /// @return balance The balance transferred.
    function _transferTokenBalanceIfAny(address token) internal returns (uint256 balance) {
        balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(owner(), balance);
        }
    }

    modifier onlyOwnerOrAuthorized() {
        if (!_isSenderAuthorized(owner())) revert MintCurveConvexPositionUnauthorized();
        _;
    }
}
