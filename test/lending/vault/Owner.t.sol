// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";

contract OwnerTest is IntegrationTest {
    address internal NEW_OWNER = makeAddr("NewOwner");

    function testOwnerIsSetOnDeployment() public view {
        assertEq(AltoVault(address(vault)).owner(), OWNER);
    }

    function testTransferOwnership() public {
        vm.expectEmit();
        emit AltoOwnable2Step.OwnershipTransferStarted(OWNER, NEW_OWNER);
        vm.prank(OWNER);
        AltoVault(address(vault)).transferOwnership(NEW_OWNER);

        assertEq(AltoVault(address(vault)).pendingOwner(), NEW_OWNER);
        assertEq(AltoVault(address(vault)).owner(), OWNER);
    }

    function testAcceptOwnership() public {
        vm.prank(OWNER);
        AltoVault(address(vault)).transferOwnership(NEW_OWNER);

        vm.expectEmit();
        emit Ownable.OwnershipTransferred(OWNER, NEW_OWNER);
        vm.prank(NEW_OWNER);
        AltoVault(address(vault)).acceptOwnership();

        assertEq(AltoVault(address(vault)).owner(), NEW_OWNER);
        assertEq(AltoVault(address(vault)).pendingOwner(), address(0));
    }

    function testAcceptOwnershipRevertsIfNotPendingOwner(address caller) public {
        vm.assume(caller != NEW_OWNER);

        vm.prank(OWNER);
        AltoVault(address(vault)).transferOwnership(NEW_OWNER);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        AltoVault(address(vault)).acceptOwnership();
    }

    function testTransferOwnershipSkip2Step() public {
        vm.prank(OWNER);
        AltoVault(address(vault)).transferOwnershipSkip2Step(NEW_OWNER);

        assertEq(AltoVault(address(vault)).owner(), NEW_OWNER);
        assertEq(AltoVault(address(vault)).pendingOwner(), address(0));
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller) public {
        vm.assume(caller != OWNER);
        vm.startPrank(caller);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        AltoVault(address(vault)).transferOwnership(NEW_OWNER);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        AltoVault(address(vault)).transferOwnershipSkip2Step(NEW_OWNER);

        vm.stopPrank();
    }
}
