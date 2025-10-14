// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract DUSDTransferOwnership is DUSDCommon {
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    modifier givenCallerIsNotOwner() {
        // Use NON_OWNER which is already defined in DUSDCommon
        _;
    }

    modifier givenCallerIsOwner() {
        // OWNER is already set as the owner in DUSDCommon setup
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.transferOwnership(NEW_OWNER);
    }

    function test_WhenNewOwnerIsZeroAddress() external givenCallerIsOwner {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(OWNER, address(0));

        vm.prank(OWNER);
        dusd.transferOwnership(address(0));

        // it should set pendingOwner to zero address
        assertEq(dusd.pendingOwner(), address(0));

        // it should not change current owner
        assertEq(dusd.owner(), OWNER);
    }

    function test_WhenNewOwnerIsCurrentOwner() external givenCallerIsOwner {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(OWNER, OWNER);

        vm.prank(OWNER);
        dusd.transferOwnership(OWNER);

        // it should set pendingOwner to current owner
        assertEq(dusd.pendingOwner(), OWNER);

        // it should not change current owner
        assertEq(dusd.owner(), OWNER);
    }

    function test_WhenNewOwnerIsValidAddress() external givenCallerIsOwner {
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(OWNER, NEW_OWNER);

        vm.prank(OWNER);
        dusd.transferOwnership(NEW_OWNER);

        // it should set pendingOwner to newOwner
        assertEq(dusd.pendingOwner(), NEW_OWNER);

        // it should not change current owner
        assertEq(dusd.owner(), OWNER);

        vm.prank(NEW_OWNER);
        dusd.acceptOwnership();

        // it should change current owner to newOwner
        assertEq(dusd.owner(), NEW_OWNER);
    }

    function test_WhenReplacingExistingPendingOwner() external givenCallerIsOwner {
        // First set a pending owner
        vm.prank(OWNER);
        dusd.transferOwnership(NEW_OWNER);
        assertEq(dusd.pendingOwner(), NEW_OWNER);

        // Then replace with another owner
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(OWNER, ANOTHER_OWNER);

        vm.prank(OWNER);
        dusd.transferOwnership(ANOTHER_OWNER);

        // it should replace previous pendingOwner with new address
        assertEq(dusd.pendingOwner(), ANOTHER_OWNER);

        // it should not change current owner
        assertEq(dusd.owner(), OWNER);

        vm.prank(NEW_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NEW_OWNER));
        dusd.acceptOwnership();

        vm.prank(ANOTHER_OWNER);
        dusd.acceptOwnership();

        // it should change current owner to ANOTHER_OWNER
        assertEq(dusd.owner(), ANOTHER_OWNER);
    }

    function test_WhenNewOwnerIsSameAsCurrentPendingOwner() external givenCallerIsOwner {
        // First set a pending owner
        vm.prank(OWNER);
        dusd.transferOwnership(NEW_OWNER);
        assertEq(dusd.pendingOwner(), NEW_OWNER);

        // Then call transferOwnership with the same address
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(OWNER, NEW_OWNER);

        vm.prank(OWNER);
        dusd.transferOwnership(NEW_OWNER);

        // it should keep the same pendingOwner
        assertEq(dusd.pendingOwner(), NEW_OWNER);

        // it should not change current owner
        assertEq(dusd.owner(), OWNER);

        vm.prank(NEW_OWNER);
        dusd.acceptOwnership();

        // it should change current owner to newOwner
        assertEq(dusd.owner(), NEW_OWNER);
    }
}
