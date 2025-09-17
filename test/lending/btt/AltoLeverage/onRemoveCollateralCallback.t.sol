// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoLeverageBTTTest} from "./AltoLeverage.t.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {FlashRemoveCollateralLeverageData} from "@alto/lending/leverage/AltoLeverage.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";

contract OnRemoveCollateralCallbackTest is AltoLeverageBTTTest {
    /// @dev it should revert
    function test_RevertGiven_CallerMarketIsNotSupported()
        external
        givenMarketIsNotSupported
        givenUserHasCollateralAndDebt
    {
        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: 1000 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        vm.startPrank(alice);
        vm.expectRevert(AltoLeverage.NotAuthorized.selector);
        market.removeCollateral(100 ether, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should revert
    function test_RevertWhen_SwapFails() external givenMarketIsSupported givenUserHasCollateralAndDebt {
        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: 100 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Configure swapper to revert on swap
        vm.mockCallRevert(address(swapper), abi.encodeWithSelector(IAltoLeverageSwapper.swap.selector), "Swap failed");

        vm.startPrank(alice);
        vm.expectRevert("Swap failed");
        market.removeCollateral(100 ether, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should revert
    function test_RevertWhen_SwapSucceedsButAmountOutIsLessThanMinAmountOut()
        external
        givenMarketIsSupported
        givenUserHasCollateralAndDebt
    {
        FlashRemoveCollateralLeverageData memory leverageData = FlashRemoveCollateralLeverageData({
            minAmountOut: 2000 ether, // Set higher than what swapper returns (1000 ether)
            swapData: hex""
        });
        bytes memory data = abi.encode(leverageData);

        // Configure swapper to return less than minAmountOut
        vm.mockCall(
            address(swapper),
            abi.encodeWithSelector(IAltoLeverageSwapper.swap.selector),
            abi.encode(100 ether) // Return 100 ether which is less than minAmountOut (2000 ether)
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AltoLeverage.MinAmountNotValid.selector, 2000 ether, 100 ether));
        market.removeCollateral(100 ether, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should repay specified amount
    function test_RepaySpecifiedAmount_WhenNoLeftoverTokensAndAmountOutIsLessThanUserBorrowedAssets()
        external
        givenMarketIsSupported
        givenUserHasCollateralAndDebt
    {
        uint256 removeAmount = 200 ether;
        uint256 swapOutput = 100 ether; // Less than user's debt

        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: swapOutput, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);
        uint256 leverageBorrowBalanceBefore = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceBefore = collateralToken.balanceOf(address(leverage));

        vm.startPrank(alice);
        market.removeCollateral(removeAmount, alice, address(leverage), data);
        vm.stopPrank();

        Position memory positionAfter = market.position(alice);
        uint256 leverageBorrowBalanceAfter = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceAfter = collateralToken.balanceOf(address(leverage));

        // Alice should have less debt after repayment
        assertLt(positionAfter.borrowShares, positionBefore.borrowShares, "Alice should have less debt");

        // Alice should have less collateral after removal
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have less collateral");

        // Leverage contract should maintain its original balances
        assertEq(
            leverageBorrowBalanceAfter,
            leverageBorrowBalanceBefore,
            "Leverage contract borrow balance should be unchanged"
        );
        assertEq(
            leverageCollateralBalanceAfter,
            leverageCollateralBalanceBefore,
            "Leverage contract collateral balance should be unchanged"
        );
    }

    /// @dev it should repay full user debt and transfer excess to onBehalf
    function test_RepayFullDebtAndTransferExcess_WhenNoLeftoverTokensAndAmountOutIsGreaterThanUserBorrowedAssets()
        external
        givenMarketIsSupported
        givenUserHasCollateralAndDebt
    {
        uint256 removeAmount = 600 ether;
        uint256 swapOutput = 600 ether; // More than user's debt

        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: swapOutput, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        uint256 leverageBorrowBalanceBefore = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceBefore = collateralToken.balanceOf(address(leverage));

        vm.startPrank(alice);
        market.removeCollateral(removeAmount, alice, address(leverage), data);
        vm.stopPrank();

        Position memory positionAfter = market.position(alice);
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        uint256 leverageBorrowBalanceAfter = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceAfter = collateralToken.balanceOf(address(leverage));

        // Alice should have zero debt after full repayment
        assertEq(positionAfter.borrowShares, 0, "Alice should have zero debt");

        // Alice should have less collateral after removal
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have less collateral");

        // Alice should receive excess tokens
        assertGt(aliceBalanceAfter, aliceBalanceBefore, "Alice should receive excess tokens");

        // Leverage contract should maintain its original balances
        assertEq(
            leverageBorrowBalanceAfter,
            leverageBorrowBalanceBefore,
            "Leverage contract borrow balance should be unchanged"
        );
        assertEq(
            leverageCollateralBalanceAfter,
            leverageCollateralBalanceBefore,
            "Leverage contract collateral balance should be unchanged"
        );
    }

    /// @dev it should transfer leftover tokens to onBehalf and repay specified amount
    function test_TransferLeftoverTokensAndRepayAmount_WhenLeftoverTokensAndAmountOutIsLessThanUserBorrowedAssets()
        external
        givenMarketIsSupported
        givenUserHasCollateralAndDebt
    {
        uint256 removeAmount = 200 ether;
        uint256 swapOutput = 100 ether; // Less than user's debt
        uint256 leftoverAmount = 25 ether;

        // Configure swapper to leave leftovers
        swapper.setLeftoverTokens(leftoverAmount);

        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: swapOutput, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);
        uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);
        uint256 leverageBorrowBalanceBefore = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceBefore = collateralToken.balanceOf(address(leverage));

        vm.startPrank(alice);
        market.removeCollateral(removeAmount, alice, address(leverage), data);
        vm.stopPrank();

        Position memory positionAfter = market.position(alice);
        uint256 aliceCollateralBalanceAfter = collateralToken.balanceOf(alice);
        uint256 leverageBorrowBalanceAfter = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceAfter = collateralToken.balanceOf(address(leverage));

        // Alice should have less debt after partial repayment
        assertLt(positionAfter.borrowShares, positionBefore.borrowShares, "Alice should have less debt");

        // Alice should have less collateral after removal
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have less collateral");

        // Alice should receive leftover collateral tokens
        assertEq(
            aliceCollateralBalanceAfter,
            aliceCollateralBalanceBefore + leftoverAmount,
            "Alice should receive leftover tokens"
        );

        // Leverage contract should maintain its original balances
        assertEq(
            leverageBorrowBalanceAfter,
            leverageBorrowBalanceBefore,
            "Leverage contract borrow balance should be unchanged"
        );
        assertEq(
            leverageCollateralBalanceAfter,
            leverageCollateralBalanceBefore,
            "Leverage contract collateral balance should be unchanged"
        );
    }

    /// @dev it should transfer leftover tokens to onBehalf repay full debt and transfer excess
    function test_TransferLeftoverTokensRepayFullDebtAndTransferExcess_WhenLeftoverTokensAndAmountOutIsGreaterThanUserBorrowedAssets(
    ) external givenMarketIsSupported givenUserHasCollateralAndDebt {
        uint256 removeAmount = 600 ether;
        uint256 swapOutput = 600 ether; // More than user's debt
        uint256 leftoverAmount = 50 ether;

        // Configure swapper to leave leftovers
        swapper.setLeftoverTokens(leftoverAmount);

        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: swapOutput, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);
        uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);
        uint256 aliceBorrowBalanceBefore = borrowToken.balanceOf(alice);
        uint256 leverageBorrowBalanceBefore = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceBefore = collateralToken.balanceOf(address(leverage));

        vm.startPrank(alice);
        market.removeCollateral(removeAmount, alice, address(leverage), data);
        vm.stopPrank();

        Position memory positionAfter = market.position(alice);
        uint256 aliceCollateralBalanceAfter = collateralToken.balanceOf(alice);
        uint256 aliceBorrowBalanceAfter = borrowToken.balanceOf(alice);
        uint256 leverageBorrowBalanceAfter = borrowToken.balanceOf(address(leverage));
        uint256 leverageCollateralBalanceAfter = collateralToken.balanceOf(address(leverage));

        // Alice should have zero debt after full repayment
        assertEq(positionAfter.borrowShares, 0, "Alice should have zero debt");

        // Alice should have less collateral after removal
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have less collateral");

        // Alice should receive leftover collateral tokens
        assertEq(
            aliceCollateralBalanceAfter,
            aliceCollateralBalanceBefore + leftoverAmount,
            "Alice should receive leftover collateral tokens"
        );

        // Alice should receive excess borrow tokens
        assertGt(aliceBorrowBalanceAfter, aliceBorrowBalanceBefore, "Alice should receive excess borrow tokens");

        // Leverage contract should maintain its original balances
        assertEq(
            leverageBorrowBalanceAfter,
            leverageBorrowBalanceBefore,
            "Leverage contract borrow balance should be unchanged"
        );
        assertEq(
            leverageCollateralBalanceAfter,
            leverageCollateralBalanceBefore,
            "Leverage contract collateral balance should be unchanged"
        );
    }

    /// @dev Fuzz test for onRemoveCollateralCallback
    function testFuzz_OnRemoveCollateralCallback(uint256 removeAmount, uint256 minAmountOut)
        external
        givenMarketIsSupported
        givenUserHasCollateralAndDebt
    {
        vm.assume(removeAmount > 0);
        vm.assume(removeAmount <= 300 ether); // Further reduced to ensure we don't remove too much collateral
        vm.assume(minAmountOut <= removeAmount); // Ensure minAmountOut is achievable
        vm.assume(minAmountOut > 0); // Avoid zero minAmountOut

        // Additional constraint: ensure we don't remove more than safe amount
        // User has 1000 ether collateral and 500 ether debt, so we need to keep sufficient collateral
        vm.assume(removeAmount <= 400 ether); // Leave enough collateral to maintain health

        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: minAmountOut, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory positionBefore = market.position(alice);

        vm.startPrank(alice);
        market.removeCollateral(removeAmount, alice, address(leverage), data);
        vm.stopPrank();

        Position memory positionAfter = market.position(alice);

        // Alice should have less or equal debt (could be zero if fully repaid)
        assertLe(positionAfter.borrowShares, positionBefore.borrowShares, "Alice should have less or equal debt");

        // Alice should have less collateral after removal
        assertLt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have less collateral");
    }

    /// @dev Test callback with zero amount - this should be caught by the market, not the callback
    function test_RevertWhen_RemoveAmountIsZero() external givenMarketIsSupported givenUserHasCollateralAndDebt {
        FlashRemoveCollateralLeverageData memory leverageData =
            FlashRemoveCollateralLeverageData({minAmountOut: 0, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        vm.startPrank(alice);
        // This should revert because zero amount operations are invalid (market-level validation)
        vm.expectRevert();
        market.removeCollateral(0, alice, address(leverage), data);
        vm.stopPrank();
    }
}
