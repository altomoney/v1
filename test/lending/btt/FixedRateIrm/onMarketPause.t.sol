// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

contract FixedRateIrmOnMarketPauseTest is Test {
    address internal immutable OWNER = makeAddr("Owner");
    address internal immutable MARKET = makeAddr("Market");
    address internal immutable OTHER = makeAddr("Other");

    uint256 internal constant START = 1_000;
    uint256 internal constant BORROW_RATE = 0.04 ether / uint256(365 days);

    FixedRateIrm internal irm;

    function setUp() public {
        vm.warp(START);
        irm = new FixedRateIrm(BORROW_RATE, OWNER);
    }

    function test_RevertWhen_MarketIsUnset_ForEitherPauseFlag() public {
        _assertUnauthorized(OWNER, true);
        _assertUnauthorized(OWNER, false);
        _assertUnauthorized(OTHER, true);
        _assertUnauthorized(OTHER, false);
    }

    function test_RevertWhen_CallerIsNotBoundMarket_ForEitherPauseFlag() public {
        irm.setMarket(MARKET);

        _assertUnauthorized(OWNER, true);
        _assertUnauthorized(OWNER, false);
        _assertUnauthorized(OTHER, true);
        _assertUnauthorized(OTHER, false);
    }

    function test_WhenPausingRepeatedly_PreservesStateAndEmitsNoEvents() public {
        irm.setMarket(MARKET);

        vm.warp(START + 1 days);
        _assertPause();

        // Pausing does not read or cast the timestamp.
        vm.warp(uint256(type(uint48).max) + 1);
        _assertPause();
    }

    function test_WhenUnpausing_UpdatesOnlyTimestampAndEmitsState() public {
        irm.setMarket(MARKET);
        vm.warp(START + 1 days);

        _assertUnpause(uint48(START + 1 days));
    }

    function test_WhenUnpausingRepeatedly_EmitsAtSameAndLaterTimestamps() public {
        irm.setMarket(MARKET);
        vm.warp(START + 1 days);

        _assertUnpause(uint48(START + 1 days));
        _assertUnpause(uint48(START + 1 days));

        vm.warp(START + 2 days);
        _assertUnpause(uint48(START + 2 days));
    }

    function test_WhenUnpausing_AcceptsZeroAndMaximumUint48Timestamps() public {
        irm.setMarket(MARKET);

        vm.warp(0);
        _assertUnpause(0);

        vm.warp(type(uint48).max);
        _assertUnpause(type(uint48).max);
    }

    function test_WhenUnpausing_TruncatesTimestampsAboveUint48() public {
        irm.setMarket(MARKET);

        // The production contract uses an explicit cast, not a checked SafeCast.
        vm.warp(uint256(type(uint48).max) + 1);
        _assertUnpause(0);

        vm.warp((uint256(1) << 48) + 37);
        _assertUnpause(37);
    }

    function _assertUnauthorized(address caller, bool paused) internal {
        (uint256 rateBefore, uint48 lastUpdateBefore) = irm.irState();
        address marketBefore = irm.market();

        vm.recordLogs();
        vm.prank(caller);
        vm.expectRevert(IIrm.IrmUnauthorized.selector);
        irm.onMarketPause(paused);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertState(rateBefore, lastUpdateBefore, marketBefore);
    }

    function _assertPause() internal {
        (uint256 rateBefore, uint48 lastUpdateBefore) = irm.irState();

        vm.recordLogs();
        vm.prank(MARKET);
        irm.onMarketPause(true);

        assertEq(vm.getRecordedLogs().length, 0);
        _assertState(rateBefore, lastUpdateBefore, MARKET);
    }

    function _assertUnpause(uint48 expectedTimestamp) internal {
        (uint256 rateBefore,) = irm.irState();

        vm.recordLogs();
        vm.prank(MARKET);
        irm.onMarketPause(false);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertState(rateBefore, expectedTimestamp, MARKET);
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(irm));
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], FixedRateIrm.IRStateUpdated.selector);
        assertEq(
            logs[0].data, abi.encode(FixedRateIrm.IRState({borrowRate: rateBefore, lastUpdate: expectedTimestamp}))
        );
    }

    function _assertState(uint256 expectedRate, uint48 expectedTimestamp, address expectedMarket) internal view {
        (uint256 rate, uint48 lastUpdate) = irm.irState();
        assertEq(rate, expectedRate);
        assertEq(lastUpdate, expectedTimestamp);
        assertEq(irm.owner(), OWNER);
        assertEq(irm.market(), expectedMarket);
    }
}
