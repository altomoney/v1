// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AltoOwnable2StepInstance} from "../AltoOwnable2StepInstance.sol";
import {AltoOwnable2StepUpgradeableInstance} from "../AltoOwnable2StepUpgradeableInstance.sol";

/// @notice BTT tests for AltoOwnable2Step::transferOwnershipSkip2Step (non-upgradeable)
contract AltoOwnable2Step_TransferOwnershipSkip2Step_Test is Test {
    address internal OWNER = makeAddr("Owner");
    address internal NON_OWNER = makeAddr("NonOwner");
    address internal NEW_OWNER = makeAddr("NewOwner");

    AltoOwnable2StepInstance internal inst;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        inst = new AltoOwnable2StepInstance(OWNER);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        // it should revert with OwnableUnauthorizedAccount
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        inst.transferOwnershipSkip2Step(NEW_OWNER);
    }

    function test_WhenNewOwnerIsZeroAddress() public {
        // Setup: first set a pending owner via normal transferOwnership
        vm.prank(OWNER);
        inst.transferOwnership(makeAddr("PendingOwner"));
        assertEq(inst.pendingOwner(), makeAddr("PendingOwner"));

        // it should emit OwnershipTransferred event
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, address(0));

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(address(0));

        // it should set owner to zero address (renounce ownership)
        assertEq(inst.owner(), address(0));

        // it should clear any pending owner
        assertEq(inst.pendingOwner(), address(0));
    }

    function test_WhenNewOwnerIsValidAddress() public {
        // Setup: first set a pending owner via normal transferOwnership
        vm.prank(OWNER);
        inst.transferOwnership(makeAddr("PendingOwner"));
        assertEq(inst.pendingOwner(), makeAddr("PendingOwner"));

        // it should emit OwnershipTransferred event
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, NEW_OWNER);

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(NEW_OWNER);

        // it should set owner to newOwner immediately
        assertEq(inst.owner(), NEW_OWNER);

        // it should clear any pending owner
        assertEq(inst.pendingOwner(), address(0));
    }

    function test_ShouldNotUse2StepProcess() public {
        // it should not use 2-step transfer process
        // Verify that ownership is transferred immediately without needing acceptOwnership
        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(NEW_OWNER);

        // Owner should be NEW_OWNER immediately
        assertEq(inst.owner(), NEW_OWNER);

        // Pending owner should be zero (not set)
        assertEq(inst.pendingOwner(), address(0));

        // NEW_OWNER should be able to use owner functions immediately
        address anotherOwner = makeAddr("AnotherOwner");
        vm.prank(NEW_OWNER);
        inst.transferOwnershipSkip2Step(anotherOwner);
        assertEq(inst.owner(), anotherOwner);
    }

    function testFuzz_TransferOwnershipSkip2Step(address newOwner) public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, newOwner);

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(newOwner);

        assertEq(inst.owner(), newOwner);
        assertEq(inst.pendingOwner(), address(0));
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller) public {
        vm.assume(caller != OWNER);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        inst.transferOwnershipSkip2Step(NEW_OWNER);
    }
}

/// @notice BTT tests for AltoOwnable2StepUpgradeable::transferOwnershipSkip2Step (upgradeable)
contract AltoOwnable2StepUpgradeable_TransferOwnershipSkip2Step_Test is Test {
    address internal OWNER = makeAddr("Owner");
    address internal NON_OWNER = makeAddr("NonOwner");
    address internal NEW_OWNER = makeAddr("NewOwner");

    AltoOwnable2StepUpgradeableInstance internal inst;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        inst = new AltoOwnable2StepUpgradeableInstance();
        inst.initialize(OWNER);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        // it should revert with OwnableUnauthorizedAccount
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        inst.transferOwnershipSkip2Step(NEW_OWNER);
    }

    function test_WhenNewOwnerIsZeroAddress() public {
        // Setup: first set a pending owner via normal transferOwnership
        vm.prank(OWNER);
        inst.transferOwnership(makeAddr("PendingOwner"));
        assertEq(inst.pendingOwner(), makeAddr("PendingOwner"));

        // it should emit OwnershipTransferred event
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, address(0));

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(address(0));

        // it should set owner to zero address (renounce ownership)
        assertEq(inst.owner(), address(0));

        // it should clear any pending owner
        assertEq(inst.pendingOwner(), address(0));
    }

    function test_WhenNewOwnerIsValidAddress() public {
        // Setup: first set a pending owner via normal transferOwnership
        vm.prank(OWNER);
        inst.transferOwnership(makeAddr("PendingOwner"));
        assertEq(inst.pendingOwner(), makeAddr("PendingOwner"));

        // it should emit OwnershipTransferred event
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, NEW_OWNER);

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(NEW_OWNER);

        // it should set owner to newOwner immediately
        assertEq(inst.owner(), NEW_OWNER);

        // it should clear any pending owner
        assertEq(inst.pendingOwner(), address(0));
    }

    function test_ShouldNotUse2StepProcess() public {
        // it should not use 2-step transfer process
        // Verify that ownership is transferred immediately without needing acceptOwnership
        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(NEW_OWNER);

        // Owner should be NEW_OWNER immediately
        assertEq(inst.owner(), NEW_OWNER);

        // Pending owner should be zero (not set)
        assertEq(inst.pendingOwner(), address(0));

        // NEW_OWNER should be able to use owner functions immediately
        address anotherOwner = makeAddr("AnotherOwner");
        vm.prank(NEW_OWNER);
        inst.transferOwnershipSkip2Step(anotherOwner);
        assertEq(inst.owner(), anotherOwner);
    }

    function testFuzz_TransferOwnershipSkip2Step(address newOwner) public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, newOwner);

        vm.prank(OWNER);
        inst.transferOwnershipSkip2Step(newOwner);

        assertEq(inst.owner(), newOwner);
        assertEq(inst.pendingOwner(), address(0));
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller) public {
        vm.assume(caller != OWNER);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        inst.transferOwnershipSkip2Step(NEW_OWNER);
    }
}

