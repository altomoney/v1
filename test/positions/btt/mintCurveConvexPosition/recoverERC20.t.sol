// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {
    IMintCurveConvexPositionErrors,
    IMintCurveConvexPositionEvents
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

contract MintCurveConvexPosition_RecoverERC20_Test is MintCurveConvexPositionCommon {
    uint256 internal constant RECOVER_AMOUNT = 100e18;

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        borrowToken.mint(address(position), RECOVER_AMOUNT);

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);
    }

    function test_TransferTokensToOwner_WhenCallerIsAuthorizedSpender() public {
        borrowToken.mint(address(position), RECOVER_AMOUNT);
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);

        uint256 ownerBalanceBefore = borrowToken.balanceOf(OWNER);
        uint256 positionBalanceBefore = borrowToken.balanceOf(address(position));

        vm.prank(AUTHORIZED_SPENDER);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        assertEq(borrowToken.balanceOf(OWNER), ownerBalanceBefore + RECOVER_AMOUNT, "owner receives tokens");
        assertEq(borrowToken.balanceOf(address(position)), positionBalanceBefore - RECOVER_AMOUNT, "position drained");
    }

    function test_RevertWhen_TokenAddressIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.recoverERC20(address(0), RECOVER_AMOUNT);
    }

    function test_RevertWhen_AmountIsZero() public {
        borrowToken.mint(address(position), RECOVER_AMOUNT);

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.recoverERC20(address(borrowToken), 0);
    }

    function test_RevertWhen_RecoveringMoreThanAvailable() public {
        borrowToken.mint(address(position), RECOVER_AMOUNT);

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(position), RECOVER_AMOUNT, RECOVER_AMOUNT + 1
            )
        );
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT + 1);
    }

    function test_TransferTokensToOwner_WhenCallerIsOwner() public {
        borrowToken.mint(address(position), RECOVER_AMOUNT);

        uint256 ownerBalanceBefore = borrowToken.balanceOf(OWNER);
        uint256 positionBalanceBefore = borrowToken.balanceOf(address(position));

        vm.expectEmit(true, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.ERC20Recovered(address(borrowToken), RECOVER_AMOUNT);

        vm.prank(OWNER);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        assertEq(borrowToken.balanceOf(OWNER), ownerBalanceBefore + RECOVER_AMOUNT, "owner receives tokens");
        assertEq(borrowToken.balanceOf(address(position)), positionBalanceBefore - RECOVER_AMOUNT, "position drained");
    }

    function test_TransferUnrelatedTokenToOwner_WhenCallerIsOwner() public {
        ERC20MockMintable unrelatedToken = new ERC20MockMintable("Unrelated", "UNR");
        unrelatedToken.mint(address(position), RECOVER_AMOUNT);

        uint256 ownerBalanceBefore = unrelatedToken.balanceOf(OWNER);
        uint256 positionBalanceBefore = unrelatedToken.balanceOf(address(position));

        vm.prank(OWNER);
        position.recoverERC20(address(unrelatedToken), RECOVER_AMOUNT);

        assertEq(unrelatedToken.balanceOf(OWNER), ownerBalanceBefore + RECOVER_AMOUNT, "owner receives tokens");
        assertEq(
            unrelatedToken.balanceOf(address(position)), positionBalanceBefore - RECOVER_AMOUNT, "position drained"
        );
    }
}
