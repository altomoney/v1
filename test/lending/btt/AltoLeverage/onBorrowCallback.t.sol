// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoLeverageBTTTest} from "./AltoLeverage.t.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {
    IAltoLeverageSwapper,
    IAltoLeverageSwapperErrors,
    SwapParams
} from "@alto/lending/interfaces/IAltoLeverageSwapper.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";

contract OnBorrowCallbackTest is AltoLeverageBTTTest {
    /// @dev it should revert
    function test_RevertGiven_CallerMarketIsNotSupported() external givenMarketIsNotSupported {
        SwapParams memory leverageData = SwapParams({minAmountOut: 1000 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        // Should revert because market is not supported in leverage contract
        vm.expectRevert(AltoLeverage.NotAuthorized.selector);
        market.borrow(1000 ether, 0, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should revert
    function test_RevertWhen_SwapFails() external givenMarketIsSupported {
        SwapParams memory leverageData = SwapParams({minAmountOut: 1000 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Configure swapper to revert on swap
        vm.mockCallRevert(address(swapper), abi.encodeWithSelector(IAltoLeverageSwapper.swap.selector), "Swap failed");

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        vm.expectRevert("Swap failed");
        market.borrow(1000 ether, 0, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should revert
    function test_RevertWhen_SwapSucceedsButAmountOutIsLessThanMinAmountOut() external givenMarketIsSupported {
        SwapParams memory leverageData = SwapParams({
            minAmountOut: 2000 ether, // Set higher than what swapper returns (1000 ether)
            swapData: hex""
        });
        bytes memory data = abi.encode(leverageData);

        // Configure swapper to revert due to AltoLeverageSwapperMinAmountOutNotMet
        vm.mockCallRevert(
            address(swapper),
            abi.encodeWithSelector(IAltoLeverageSwapper.swap.selector),
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperMinAmountOutNotMet.selector, 2000 ether, 1000 ether
            )
        );

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAltoLeverageSwapperErrors.AltoLeverageSwapperMinAmountOutNotMet.selector, 2000 ether, 1000 ether
            )
        );
        market.borrow(1000 ether, 0, alice, address(leverage), data);
        vm.stopPrank();
    }

    /// @dev it should add collateral to market
    function test_AddCollateralToMarket_WhenSwapSucceedsAndAmountOutMeetsMinAmountOutAndNoLeftoverTokens()
        external
        givenMarketIsSupported
    {
        uint256 borrowAmount = 1000 ether;
        SwapParams memory leverageData = SwapParams({minAmountOut: borrowAmount, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        Position memory positionBefore = market.position(alice);
        uint256 leverageBalanceBefore = borrowToken.balanceOf(address(leverage));

        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        Position memory positionAfter = market.position(alice);
        uint256 leverageBalanceAfter = borrowToken.balanceOf(address(leverage));

        // Alice should have more collateral after the leverage operation
        assertGt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have more collateral");

        // Leverage contract should maintain its original balance (no leftover borrow tokens from this operation)
        assertEq(leverageBalanceAfter, leverageBalanceBefore, "Leverage contract balance should be unchanged");

        // Leverage contract should have no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)),
            1000 ether,
            "Leverage contract should maintain original collateral balance"
        );
        vm.stopPrank();
    }

    /// @dev it should transfer leftover tokens to onBehalf and add collateral to market
    function test_TransferLeftoverTokensAndAddCollateral_WhenSwapSucceedsAndAmountOutMeetsMinAmountOutAndLeftoverTokensExist()
        external
        givenMarketIsSupported
    {
        uint256 borrowAmount = 1000 ether;
        uint256 leftoverAmount = 50 ether;

        // Configure swapper to leave leftover tokens
        swapper.setLeftoverTokens(leftoverAmount);

        SwapParams memory leverageData = SwapParams({minAmountOut: borrowAmount, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        Position memory positionBefore = market.position(alice);
        uint256 leverageBalanceBefore = borrowToken.balanceOf(address(leverage));

        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        Position memory positionAfter = market.position(alice);
        uint256 leverageBalanceAfter = borrowToken.balanceOf(address(leverage));

        // Alice should receive leftover tokens
        assertEq(aliceBalanceAfter, aliceBalanceBefore + leftoverAmount, "Alice should receive leftover tokens");

        // Alice should have more collateral after the leverage operation
        assertGt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have more collateral");

        // Leverage contract should maintain its original balance (no leftover borrow tokens from this operation)
        assertEq(leverageBalanceAfter, leverageBalanceBefore, "Leverage contract balance should be unchanged");
        vm.stopPrank();
    }

    /// @dev Fuzz test for onBorrowCallback
    function testFuzz_OnBorrowCallback(uint256 borrowAmount, uint256 minAmountOut) external givenMarketIsSupported {
        vm.assume(borrowAmount > 0);
        vm.assume(borrowAmount <= 4000 ether); // Keep within reasonable limits to avoid excessive leverage
        vm.assume(minAmountOut <= borrowAmount); // Ensure minAmountOut is achievable
        vm.assume(minAmountOut > 0); // Avoid zero minAmountOut which might cause issues

        SwapParams memory leverageData = SwapParams({minAmountOut: minAmountOut, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(10000 ether, alice); // Provide more collateral for larger borrow amounts

        Position memory positionBefore = market.position(alice);

        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        Position memory positionAfter = market.position(alice);

        // Alice should have more collateral after the leverage operation
        assertGt(positionAfter.collateralAssets, positionBefore.collateralAssets, "Alice should have more collateral");

        // Alice should have more debt after borrowing
        assertGt(positionAfter.borrowShares, positionBefore.borrowShares, "Alice should have more debt");
        vm.stopPrank();
    }

    /// @dev Test callback with zero amount - this should be caught by the market, not the callback
    function test_RevertWhen_BorrowAmountIsZero() external givenMarketIsSupported {
        SwapParams memory leverageData = SwapParams({minAmountOut: 0, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Setup: Alice adds supply and collateral to market
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);

        // This should revert because trying to borrow zero amount (market-level validation)
        vm.expectRevert();
        market.borrow(0, 0, alice, address(leverage), data);
        vm.stopPrank();
    }
}
