// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketBase, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedRateIrmCommon} from "./FixedRateIrmCommon.t.sol";

contract FixedRateIrmSetBorrowRateTest is FixedRateIrmCommon {
    function test_RevertWhen_CallerIsNotOwner_BeforeMarketAndRateChecks() public {
        _expectUnauthorized();
        _assertState(INITIAL_RATE, 0);
        _bindMarket();
        _mockPauseQueryFailure();
        _expectUnauthorized();
        _assertUnchanged();
    }

    function test_RevertWhen_MarketIsUnset_BeforeRateValidation() public {
        vm.prank(OWNER);
        vm.expectRevert(IIrm.IrmMarketNotSet.selector);
        irm.setBorrowRate(MAX_RATE + 1);
        _assertState(INITIAL_RATE, 0);
    }

    function testFuzz_RevertWhen_RateExceedsMaximum_BeforeMarketCalls(uint256 rate) public {
        _bindMarket();
        _mockPauseQueryFailure();
        rate = bound(rate, MAX_RATE + 1, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(IIrm.IrmInvalidParams.selector);
        irm.setBorrowRate(rate);
        _assertUnchanged();
    }

    function testFuzz_WhenMarketIsActive_AccruesOldRateThenStoresNewRateAndEmits(uint256 rate) public {
        _bindMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(bound(rate, 0, MAX_RATE), false);
    }

    function test_WhenMarketIsPaused_SkipsAccrualAndPreservesTimestamp() public {
        _bindMarket();
        _pauseMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(2e9, true);
    }

    function test_WhenRateIsZeroOrMaximum_AcceptsInclusiveBoundaries() public {
        _bindMarket();
        _pauseMarket();
        _assertSuccessfulChange(0, true);
        _assertSuccessfulChange(MAX_RATE, true);
    }

    function test_WhenRateIsUnchangedAndMarketIsActive_StillAccruesAndEmits() public {
        _bindMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(INITIAL_RATE, false);
    }

    function test_WhenRateIsUnchangedAndMarketIsPaused_SkipsAccrualAndEmits() public {
        _bindMarket();
        _pauseMarket();
        vm.warp(START + 100_000);
        _assertSuccessfulChange(INITIAL_RATE, true);
    }

    function test_RevertWhen_PauseQueryFails_PreservesState() public {
        _bindMarket();
        _mockPauseQueryFailure();
        vm.prank(OWNER);
        vm.expectRevert(MarketCallFailed.selector);
        irm.setBorrowRate(2e9);
        _assertUnchanged();
    }

    function test_RevertWhen_AccrualFails_RollsBackNestedStateChanges() public {
        _bindMarket();
        (uint256 supply, uint256 borrowed) = _prepareMarketAccrualOverflow();
        vm.warp(START + 100_000);
        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (supply, borrowed)), 1);
        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        irm.setBorrowRate(2e9);
        _assertState(INITIAL_RATE, uint48(START));
        _assertMarketBalances(supply, borrowed);
    }

    function _expectUnauthorized() internal {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        irm.setBorrowRate(MAX_RATE + 1);
    }

    function _assertUnchanged() internal view {
        _assertState(INITIAL_RATE, uint48(START));
        assertEq(irm.market(), address(market));
        assertEq(irm.owner(), OWNER);
        _assertMarketBalances(1000 ether, 800 ether);
    }

    function _assertSuccessfulChange(uint256 rate, bool paused) internal {
        uint48 timestamp = paused ? uint48(START) : uint48(block.timestamp);
        uint256 interest = paused ? 0 : _expectedInterest(800 ether, INITIAL_RATE, block.timestamp - START);
        vm.expectCall(address(market), abi.encodeCall(IPausable.paused, (PAUSE_TYPE)));
        if (!paused) vm.expectCall(address(market), abi.encodeCall(IMarketBase.accrueInterest, ()), 1);
        vm.recordLogs();
        vm.prank(OWNER);
        irm.setBorrowRate(rate);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertState(rate, timestamp);
        assertEq(irm.owner(), OWNER);
        assertEq(irm.market(), address(market));
        _assertMarketBalances(1000 ether + interest, 800 ether + interest);
        assertEq(logs.length, paused ? 2 : 4);
        if (!paused) {
            _assertStateLog(logs[0], INITIAL_RATE, timestamp);
            assertEq(logs[1].emitter, address(market));
            assertEq(logs[1].topics.length, 1);
            assertEq(logs[1].topics[0], IMarketEvents.AccrueInterest.selector);
            assertEq(
                logs[1].data,
                abi.encode(INITIAL_RATE, interest, uint128(800 ether + interest), uint128(1000 ether + interest))
            );
        }
        _assertStateLog(logs[logs.length - 2], rate, timestamp);
        Vm.Log memory rateLog = logs[logs.length - 1];
        assertEq(rateLog.emitter, address(irm));
        assertEq(rateLog.topics.length, 1);
        assertEq(rateLog.topics[0], FixedRateIrm.SetBorrowRate.selector);
        assertEq(rateLog.data, abi.encode(rate));
    }
}
