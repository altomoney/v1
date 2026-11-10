// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketPauseTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerLacksRequestedPauserRole() external {
        AccountingState memory beforeState = _state();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, USER, PAUSE_TYPE));
        market.pause(PAUSE_TYPE, true);

        assertFalse(market.paused(PAUSE_TYPE));
        _assertUnchanged(beforeState);
    }

    function test_PauseAccruesIntoActiveDebtAndFeesBeforeChangingState() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(5 ether, 37);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(37, 5 ether, 105 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IPausable.Paused(OWNER, PAUSE_TYPE, true);
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);

        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 105 ether);
        assertEq(market.claimableFeesAssets(), 5 ether);
        assertEq(market.badDebtAssets(), 0);
        assertTrue(market.paused(PAUSE_TYPE));
    }

    function test_PauseAccrualFailureIsAtomic() external {
        _openPosition(1_000 ether, 100 ether);
        _mockIrmUpdateRevert();
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.pause(PAUSE_TYPE, true);

        assertFalse(market.paused(PAUSE_TYPE));
        _assertUnchanged(beforeState);
    }

    function test_UnpauseNotifiesIrmAndRestartsAccrualAtCurrentTimestamp() external {
        _mockAccrual(0, 0);
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
        vm.warp(block.timestamp + 30 days);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.onMarketPause, (false)));
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, false);

        (, uint48 lastUpdate) = irm.irState();
        assertEq(lastUpdate, block.timestamp);
        assertFalse(market.paused(PAUSE_TYPE));
    }

    function test_UnpauseNotificationFailureLeavesMarketPaused() external {
        _mockAccrual(0, 0);
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
        vm.mockCallRevert(address(irm), abi.encodeCall(IIrm.onMarketPause, (false)), "UNPAUSE_REVERTED");

        vm.prank(OWNER);
        vm.expectRevert(bytes("UNPAUSE_REVERTED"));
        market.pause(PAUSE_TYPE, false);

        assertTrue(market.paused(PAUSE_TYPE));
    }

    function test_FreezeTransitionsDoNotInvokeInterestHooks() external {
        _mockIrmUpdateRevert();
        vm.mockCallRevert(address(irm), abi.encodeCall(IIrm.onMarketPause, (false)), "HOOK_MUST_NOT_BE_CALLED");
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        market.pause(FROZEN_TYPE, true);
        assertTrue(market.paused(FROZEN_TYPE));

        vm.prank(OWNER);
        market.pause(FROZEN_TYPE, false);
        assertFalse(market.paused(FROZEN_TYPE));
        _assertUnchanged(beforeState);
    }

    function test_RepeatedPauseStateRollsBackHookEffects() external {
        _mockAccrual(0, 0);
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, true);
        AccountingState memory beforeState = _state();
        _mockAccrual(5 ether, 37);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, true, true));
        market.pause(PAUSE_TYPE, true);

        assertTrue(market.paused(PAUSE_TYPE));
        _assertUnchanged(beforeState);

        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, false);
        (, uint48 lastUpdateBefore) = irm.irState();
        vm.warp(block.timestamp + 1 days);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IPausable.StateNotChanged.selector, PAUSE_TYPE, false, false));
        market.pause(PAUSE_TYPE, false);

        (, uint48 lastUpdateAfter) = irm.irState();
        assertEq(lastUpdateAfter, lastUpdateBefore);
        assertFalse(market.paused(PAUSE_TYPE));
    }
}
