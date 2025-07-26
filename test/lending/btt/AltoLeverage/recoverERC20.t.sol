// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoLeverage.t.sol";

contract RecoverERC20Test is AltoLeverageBTTTest {
    /// @dev it should revert
    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.expectRevert();
        leverage.recoverERC20(address(borrowToken), 100 ether, alice);
    }

    /// @dev it should transfer tokens to recipient
    function test_TransferTokensToRecipient_WhenTokenAddressIsZeroAddress() external givenCallerIsOwner {
        uint256 amount = 100 ether;

        // This will likely revert due to calling transfer on zero address
        vm.expectRevert();
        leverage.recoverERC20(address(0), amount, alice);
    }

    /// @dev it should transfer zero tokens to recipient
    function test_TransferZeroTokensToRecipient_WhenTokenAmountIsZero() external givenCallerIsOwner {
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        leverage.recoverERC20(address(borrowToken), 0, alice);

        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore, "Alice balance should remain the same");
    }

    /// @dev it should transfer tokens to zero address
    function test_TransferTokensToZeroAddress_WhenRecipientIsZeroAddress() external givenCallerIsOwner {
        uint256 amount = 100 ether;

        // This should revert as ERC20 doesn't allow transfers to zero address
        vm.expectRevert();
        leverage.recoverERC20(address(borrowToken), amount, address(0));
    }

    /// @dev it should transfer tokens to recipient
    function test_TransferTokensToRecipient_WhenAllParametersAreValid() external givenCallerIsOwner {
        uint256 amount = 100 ether;
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);
        uint256 leverageBalanceBefore = borrowToken.balanceOf(address(leverage));

        leverage.recoverERC20(address(borrowToken), amount, alice);

        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);
        uint256 leverageBalanceAfter = borrowToken.balanceOf(address(leverage));

        assertEq(aliceBalanceAfter, aliceBalanceBefore + amount, "Alice should receive the tokens");
        assertEq(leverageBalanceAfter, leverageBalanceBefore - amount, "Leverage should lose the tokens");
    }

    /// @dev Fuzz test for recovering tokens
    function testFuzz_RecoverTokens(uint256 amount, address recipient) external givenCallerIsOwner {
        vm.assume(amount <= borrowToken.balanceOf(address(leverage)));
        vm.assume(recipient != address(0));
        vm.assume(recipient != address(leverage));

        uint256 recipientBalanceBefore = borrowToken.balanceOf(recipient);
        uint256 leverageBalanceBefore = borrowToken.balanceOf(address(leverage));

        leverage.recoverERC20(address(borrowToken), amount, recipient);

        uint256 recipientBalanceAfter = borrowToken.balanceOf(recipient);
        uint256 leverageBalanceAfter = borrowToken.balanceOf(address(leverage));

        assertEq(recipientBalanceAfter, recipientBalanceBefore + amount, "Recipient should receive the tokens");
        assertEq(leverageBalanceAfter, leverageBalanceBefore - amount, "Leverage should lose the tokens");
    }

    /// @dev Test recovering different token types
    function test_RecoverDifferentTokenTypes() external givenCallerIsOwner {
        uint256 borrowAmount = 50 ether;
        uint256 collateralAmount = 75 ether;

        uint256 aliceBorrowBalanceBefore = borrowToken.balanceOf(alice);
        uint256 aliceCollateralBalanceBefore = collateralToken.balanceOf(alice);

        // Recover borrow tokens
        leverage.recoverERC20(address(borrowToken), borrowAmount, alice);

        // Recover collateral tokens
        leverage.recoverERC20(address(collateralToken), collateralAmount, alice);

        uint256 aliceBorrowBalanceAfter = borrowToken.balanceOf(alice);
        uint256 aliceCollateralBalanceAfter = collateralToken.balanceOf(alice);

        assertEq(aliceBorrowBalanceAfter, aliceBorrowBalanceBefore + borrowAmount, "Alice should receive borrow tokens");
        assertEq(
            aliceCollateralBalanceAfter,
            aliceCollateralBalanceBefore + collateralAmount,
            "Alice should receive collateral tokens"
        );
    }

    /// @dev Test recovering more tokens than available
    function test_RevertWhen_RecoveringMoreThanAvailable() external givenCallerIsOwner {
        uint256 leverageBalance = borrowToken.balanceOf(address(leverage));
        uint256 excessAmount = leverageBalance + 1;

        vm.expectRevert();
        leverage.recoverERC20(address(borrowToken), excessAmount, alice);
    }
}
