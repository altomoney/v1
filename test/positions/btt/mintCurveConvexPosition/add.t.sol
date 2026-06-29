// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    IMintCurveConvexPositionEvents,
    IMintCurveConvexPositionErrors,
    MintCurveConvexAddParams
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {SwapPositionLib} from "@alto/positions/libraries/SwapPositionLib.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {IMarketErrors, Position} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintCurveConvexPosition_Add_Test is MintCurveConvexPositionCommon {
    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();
        MintCurveConvexAddParams memory params = _addParams(DEFAULT_COLLATERAL, 0, 0, minFrxOut, minLpOut);

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.add(_encodeAdd(params));
    }

    function test_RevertWhen_CollateralAmountAndBorrowAssetsAreZero() public {
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.add(_encodeAdd(_addParams(0, 0, 0, minFrxOut, minLpOut)));
    }

    function test_Add_CollateralOnly() public {
        uint256 collateralAmount = DEFAULT_COLLATERAL;
        _mintCollateralToOwner(collateralAmount);

        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);
        uint256 positionCollateralBefore = collateralToken.balanceOf(address(position));
        Position memory marketPositionBefore = _marketPosition();
        (uint128 totalBorrowedAssetsBefore,) = mintMarket.totalBorrowed();
        uint256 swapCallsBefore = swapTarget.swapCallCount();
        uint256 curveCallsBefore = curvePool.addLiquidityCallCount();
        uint256 convexCallsBefore = convexBooster.depositCallCount();
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();

        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionEvents.AddPosition(OWNER, collateralAmount, 0, 0);

        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(collateralAmount, 0, 0, minFrxOut, minLpOut)));

        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore - collateralAmount);
        assertEq(collateralToken.balanceOf(address(position)), positionCollateralBefore);
        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets + uint128(collateralAmount));
        (uint128 totalBorrowedAssetsAfter,) = mintMarket.totalBorrowed();
        assertEq(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);
        assertEq(swapTarget.swapCallCount(), swapCallsBefore);
        assertEq(curvePool.addLiquidityCallCount(), curveCallsBefore);
        assertEq(convexBooster.depositCallCount(), convexCallsBefore);
    }

    function test_RevertWhen_BorrowOnlyAndPositionHasNoCollateralPosted() public {
        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut);

        vm.prank(OWNER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        position.add(_encodeAdd(params));
    }

    function test_RevertWhen_BorrowOnlyAndSwapTargetIsNotApproved() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);

        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut);
        params.swapTarget = UNAPPROVED_SWAP_TARGET;

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.add(_encodeAdd(params));
    }

    function test_Add_BorrowOnly_WhenAllLegsSucceed() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);

        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);
        uint256 borrowSharesBefore = _marketPosition().borrowShares;
        (uint128 totalBorrowedAssetsBefore,) = mintMarket.totalBorrowed();

        vm.recordLogs();
        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut)));

        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore);
        (uint128 totalBorrowedAssetsAfter,) = mintMarket.totalBorrowed();
        assertGt(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore);
        assertGt(_marketPosition().borrowShares, borrowSharesBefore);
        assertEq(IERC20(address(borrowToken)).allowance(address(position), address(swapTarget)), 0);
        assertEq(swapTarget.lastAmountIn(), amountIn);
        assertEq(swapTarget.lastSellToken(), address(borrowToken));
        assertEq(swapTarget.lastBuyToken(), address(frxUsd));
        assertGt(curvePool.addLiquidityCallCount(), 0);
        assertGt(convexBooster.depositCallCount(), 0);
        assertGe(_stakedLpBalance(), _expectedAddMinLpOut(borrowAssets));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAddPositionLogged(0, borrowAssets, _expectedAddMinLpOut(borrowAssets), logs);
        _assertSwapLogged(
            address(borrowToken),
            address(frxUsd),
            amountIn,
            address(swapTarget),
            _expectedAddMinFrxOut(borrowAssets),
            logs
        );
    }

    function test_Add_BorrowOnly_WhenBorrowAssetsIsOne() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);

        uint256 borrowAssets = 1;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);

        uint256 borrowSharesBefore = _marketPosition().borrowShares;

        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut)));

        assertEq(swapTarget.swapCallCount(), 0);
        assertGt(_marketPosition().borrowShares, borrowSharesBefore);
        assertGt(curvePool.addLiquidityCallCount(), 0);
        assertGt(convexBooster.depositCallCount(), 0);
        assertGe(_stakedLpBalance(), minLpOut);
    }

    function test_RevertWhen_BorrowOnlyAndSwapTargetCallFails() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);
        swapTarget.setSwapOutcome(true, 0);

        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);

        vm.prank(OWNER);
        vm.expectRevert(SwapPositionLib.SwapPositionSwapFailed.selector);
        position.add(_encodeAdd(_addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut)));
    }

    function test_RevertWhen_BorrowOnlyAndFrxUsdReceivedIsLessThanMinFrxOut() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);
        swapTarget.setSwapOutcome(false, 1);

        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapPositionLib.SwapPositionMinAmountOutNotMet.selector, minFrxOut, uint256(1)
            )
        );
        position.add(_encodeAdd(params));
    }

    function test_RevertWhen_BorrowOnlyAndCurveLpMintedIsLessThanMinLpOut() public {
        _addCollateralOnly(DEFAULT_COLLATERAL);
        curvePool.setLpMintOverride(0, true);

        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(0, borrowAssets, amountIn, minFrxOut, minLpOut);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(MockCurvePool.MockCurvePoolMinLpNotMet.selector, minLpOut, uint256(0))
        );
        position.add(_encodeAdd(params));
    }

    function test_RevertWhen_CollateralPlusBorrowAndSwapTargetIsNotApproved() public {
        _mintCollateralToOwner(DEFAULT_COLLATERAL);

        uint256 collateralAmount = DEFAULT_COLLATERAL;
        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(collateralAmount, borrowAssets, amountIn, minFrxOut, minLpOut);
        params.swapTarget = UNAPPROVED_SWAP_TARGET;

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.add(_encodeAdd(params));
    }

    function test_RevertWhen_CollateralPlusBorrowAndSwapTargetCallFails() public {
        _mintCollateralToOwner(DEFAULT_COLLATERAL);
        swapTarget.setSwapOutcome(true, 0);

        uint256 collateralAmount = DEFAULT_COLLATERAL;
        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);

        vm.prank(OWNER);
        vm.expectRevert(SwapPositionLib.SwapPositionSwapFailed.selector);
        position.add(_encodeAdd(_addParams(collateralAmount, borrowAssets, amountIn, minFrxOut, minLpOut)));
    }

    function test_RevertWhen_CollateralPlusBorrowAndFrxUsdReceivedIsLessThanMinFrxOut() public {
        _mintCollateralToOwner(DEFAULT_COLLATERAL);
        swapTarget.setSwapOutcome(false, 1);

        uint256 collateralAmount = DEFAULT_COLLATERAL;
        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);
        MintCurveConvexAddParams memory params = _addParams(collateralAmount, borrowAssets, amountIn, minFrxOut, minLpOut);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapPositionLib.SwapPositionMinAmountOutNotMet.selector, minFrxOut, uint256(1)
            )
        );
        position.add(_encodeAdd(params));
    }

    function test_Add_CollateralPlusBorrow_WhenAllLegsSucceed() public {
        uint256 collateralAmount = DEFAULT_COLLATERAL;
        uint256 borrowAssets = DEFAULT_BORROW;
        uint256 amountIn = borrowAssets / 2;
        uint256 minFrxOut = _expectedAddMinFrxOut(borrowAssets);
        uint256 minLpOut = _expectedAddMinLpOut(borrowAssets);

        _mintCollateralToOwner(collateralAmount);
        uint256 collateralBefore = _marketPosition().collateralAssets;

        vm.recordLogs();
        vm.prank(OWNER);
        position.add(_encodeAdd(_addParams(collateralAmount, borrowAssets, amountIn, minFrxOut, minLpOut)));

        assertEq(_marketPosition().collateralAssets, collateralBefore + uint128(collateralAmount));
        assertGt(_marketPosition().borrowShares, 0);
        assertEq(IERC20(address(borrowToken)).allowance(address(position), address(swapTarget)), 0);
        assertEq(swapTarget.lastAmountIn(), amountIn);
        assertGt(curvePool.addLiquidityCallCount(), 0);
        assertGt(convexBooster.depositCallCount(), 0);
        assertGe(_stakedLpBalance(), minLpOut);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAddPositionLogged(collateralAmount, borrowAssets, minLpOut, logs);
        _assertSwapLogged(
            address(borrowToken), address(frxUsd), amountIn, address(swapTarget), minFrxOut, logs
        );
    }

    function test_Add_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _mintCollateralToOwner(DEFAULT_COLLATERAL);
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();

        vm.prank(AUTHORIZED_SPENDER);
        position.add(_encodeAdd(_addParams(DEFAULT_COLLATERAL, 0, 0, minFrxOut, minLpOut)));

        assertGt(_marketPosition().collateralAssets, 0);
    }
}
