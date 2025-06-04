// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerSetExerciseWindowTest is TOBTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setExerciseWindow(1 days);
        vm.stopPrank();
    }

    function test_setExerciseWindow_validConditions() public {
        uint256 newWindow = 1 days;

        // Set exercise window
        vm.startPrank(owner);
        tob.setExerciseWindow(newWindow);
        vm.stopPrank();

        // Verify window updated
        assertEq(tob._exerciseWindow(), newWindow, "Exercise window should be updated");
    }
}
