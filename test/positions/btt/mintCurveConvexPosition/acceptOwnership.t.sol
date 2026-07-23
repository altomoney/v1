// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {IMintCurveConvexPositionErrors} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MintCurveConvexPosition_AcceptOwnership_Test is MintCurveConvexPositionCommon {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address internal immutable NEW_OWNER = makeAddr("NewOwner");
    address internal immutable NEW_SPENDER = makeAddr("NewSpender");
    uint256 internal constant RECOVER_AMOUNT = 100e18;

    function _startTransfer(address to) internal {
        vm.prank(OWNER);
        position.transferOwnership(to);
    }

    function test_RevertWhen_NoPendingOwner() public {
        vm.prank(NEW_OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
        position.acceptOwnership();
    }

    function test_RevertWhen_CallerIsNotPendingOwner() public {
        _startTransfer(NEW_OWNER);

        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_AUTHORIZED));
        position.acceptOwnership();
    }

    function test_AcceptOwnership_WhenCallerIsPendingOwner() public {
        _startTransfer(NEW_OWNER);

        vm.expectEmit(true, true, false, false, address(position));
        emit OwnershipTransferred(OWNER, NEW_OWNER);

        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        assertEq(position.owner(), NEW_OWNER, "owner rolled over");
        assertEq(position.pendingOwner(), address(0), "pendingOwner cleared");
    }

    function test_AcceptOwnership_RollsOverAuthorization_PreviousOwnerSpenderLosesAccess() public {
        // Old owner authorizes a spender, then hands the position to a new owner.
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _startTransfer(NEW_OWNER);
        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        // The authorization was recorded under the old owner, so it no longer grants access.
        borrowToken.mint(address(position), RECOVER_AMOUNT);
        vm.prank(AUTHORIZED_SPENDER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);
    }

    function test_AcceptOwnership_RollsOverAuthorization_PreviousOwnerLosesAccess() public {
        _startTransfer(NEW_OWNER);
        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        borrowToken.mint(address(position), RECOVER_AMOUNT);
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);
    }

    function test_AcceptOwnership_RollsOverAuthorization_NewOwnerControlsAndReceivesFunds() public {
        _startTransfer(NEW_OWNER);
        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        // New owner authorizes a fresh spender who can now manage the position.
        vm.prank(NEW_OWNER);
        position.setAuthorization(NEW_SPENDER, true);
        assertTrue(position.isAuthorized(NEW_OWNER, NEW_SPENDER), "new owner authorization recorded");

        borrowToken.mint(address(position), RECOVER_AMOUNT);
        vm.prank(NEW_SPENDER);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        assertEq(borrowToken.balanceOf(NEW_OWNER), RECOVER_AMOUNT, "recovered funds go to the new owner");
    }

    function test_AcceptOwnership_AuthorizationSetByIncomingOwnerBeforeTransferIsEffective() public {
        // The incoming owner pre-authorizes a spender while still just the pending owner.
        vm.prank(NEW_OWNER);
        position.setAuthorization(NEW_SPENDER, true);

        _startTransfer(NEW_OWNER);
        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        // No re-authorization needed: the mapping is keyed on the (now current) owner.
        borrowToken.mint(address(position), RECOVER_AMOUNT);
        vm.prank(NEW_SPENDER);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        assertEq(borrowToken.balanceOf(NEW_OWNER), RECOVER_AMOUNT, "pre-authorized spender pays the new owner");
    }

    function test_AcceptOwnership_OriginalOwnerAuthorizationsReactivateOnRoundTrip() public {
        // Original owner authorizes a spender, then hands ownership away.
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        _startTransfer(NEW_OWNER);
        vm.prank(NEW_OWNER);
        position.acceptOwnership();

        // While NEW_OWNER holds ownership, the original owner's spender is inert.
        borrowToken.mint(address(position), RECOVER_AMOUNT);
        vm.prank(AUTHORIZED_SPENDER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        // Ownership round-trips back to the original owner.
        vm.prank(NEW_OWNER);
        position.transferOwnership(OWNER);
        vm.prank(OWNER);
        position.acceptOwnership();
        assertEq(position.owner(), OWNER, "ownership restored");

        // The original owner's authorization was never cleared, so the spender regains access.
        vm.prank(AUTHORIZED_SPENDER);
        position.recoverERC20(address(borrowToken), RECOVER_AMOUNT);

        assertEq(borrowToken.balanceOf(OWNER), RECOVER_AMOUNT, "spender pays the restored owner");
    }
}
