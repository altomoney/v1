// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MintCurveConvexPosition_TransferOwnership_Test is MintCurveConvexPositionCommon {
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    address internal immutable NEW_OWNER = makeAddr("NewOwner");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NON_AUTHORIZED));
        position.transferOwnership(NEW_OWNER);
    }

    function test_TransferOwnership_WhenNewOwnerIsNonZero() public {
        vm.expectEmit(true, true, false, false, address(position));
        emit OwnershipTransferStarted(OWNER, NEW_OWNER);

        vm.prank(OWNER);
        position.transferOwnership(NEW_OWNER);

        assertEq(position.pendingOwner(), NEW_OWNER, "pendingOwner set");
        assertEq(position.owner(), OWNER, "owner unchanged until acceptance");
    }

    function test_TransferOwnership_KeepsCurrentOwnerAuthorizationsEffective() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);

        vm.prank(OWNER);
        position.transferOwnership(NEW_OWNER);

        // Ownership has not moved yet, so the current owner's authorizations still hold.
        borrowToken.mint(address(position), 1e18);
        vm.prank(AUTHORIZED_SPENDER);
        position.recoverERC20(address(borrowToken), 1e18);

        assertEq(borrowToken.balanceOf(OWNER), 1e18, "spender still pays the current owner");
    }

    function test_TransferOwnership_WhenNewOwnerIsZero_ClearsPendingTransfer() public {
        vm.prank(OWNER);
        position.transferOwnership(NEW_OWNER);
        assertEq(position.pendingOwner(), NEW_OWNER, "pendingOwner set");

        vm.prank(OWNER);
        position.transferOwnership(address(0));

        assertEq(position.pendingOwner(), address(0), "pending transfer cleared");
        assertEq(position.owner(), OWNER, "owner unchanged");
    }
}
