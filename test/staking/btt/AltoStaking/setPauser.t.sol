// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE, RESCUE_TYPE} from "@alto/utils/Constants.sol";

contract AltoStaking_SetPauser_Test is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.setPauser(PAUSER, PAUSE_TYPE, true);
    }

    function test_SetPauserForPauseTypeTrue() public {
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);
        staking.setPauser(PAUSER, PAUSE_TYPE, true);

        assertEq(staking.pausers(PAUSER, PAUSE_TYPE), true);
    }

    function test_SetPauserForPauseTypeFalse() public {
        // First enable the pauser
        vm.prank(OWNER);
        staking.setPauser(PAUSER, PAUSE_TYPE, true);

        // Then disable it
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, false);
        staking.setPauser(PAUSER, PAUSE_TYPE, false);

        assertEq(staking.pausers(PAUSER, PAUSE_TYPE), false);
    }

    function test_SetPauserForRescueModeTypeTrue() public {
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, RESCUE_TYPE, true);
        staking.setPauser(PAUSER, RESCUE_TYPE, true);

        assertEq(staking.pausers(PAUSER, RESCUE_TYPE), true);
    }

    function test_SetPauserForRescueModeTypeFalse() public {
        // First enable the pauser
        vm.prank(OWNER);
        staking.setPauser(PAUSER, RESCUE_TYPE, true);

        // Then disable it
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, RESCUE_TYPE, false);
        staking.setPauser(PAUSER, RESCUE_TYPE, false);

        assertEq(staking.pausers(PAUSER, RESCUE_TYPE), false);
    }
}
