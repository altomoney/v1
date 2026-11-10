// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {AdaptiveCurveIrmCommon} from "./AdaptiveCurveIrmCommon.t.sol";

contract AdaptiveCurveIrmSetMarketTest is AdaptiveCurveIrmCommon {
    function test_WhenUnbound_AllowsOwnerOtherAndMarketToBindAnEoa() public {
        address[3] memory callers = [OWNER, OTHER, address(market)];
        for (uint256 i; i < callers.length; ++i) {
            irm = new AdaptiveCurveIrm(config, OWNER);
            // A market address is stored without calling or validating its interface.
            assertEq(OTHER.code.length, 0);
            vm.prank(callers[i]);
            _bindAndAssert(OTHER, INITIAL_RATE, uint48(START));
        }
    }

    function test_RevertWhen_AlreadyBound_ForZeroSameAndDifferentMarket() public {
        _bindMarket();
        address[3] memory replacements = [address(0), address(market), OTHER];
        vm.warp(START + 1 days);
        for (uint256 i; i < replacements.length; ++i) {
            vm.recordLogs();
            vm.expectRevert(IIrm.IrmMarketAlreadySet.selector);
            irm.setMarket(replacements[i]);
            assertEq(vm.getRecordedLogs().length, 0);
            assertEq(irm.market(), address(market));
            _assertState(INITIAL_RATE, uint48(START));
            _assertConfig(config);
        }
    }

    function test_WhenZeroMarketIsSupplied_InitializesAndAllowsRepeatedBinding() public {
        _bindAndAssert(address(0), INITIAL_RATE, uint48(START));
        vm.warp(START + 1 days);
        _bindAndAssert(address(0), INITIAL_RATE, uint48(START + 1 days));
        _bindAndAssert(address(market), INITIAL_RATE, uint48(START + 1 days));
    }

    function test_WhenTimestampIsZeroMaximumOrOversized_StoresLow48Bits() public {
        uint256[4] memory timestamps =
            [uint256(0), uint256(type(uint48).max), uint256(1) << 48, (uint256(1) << 48) + 37];
        for (uint256 i; i < timestamps.length; ++i) {
            irm = new AdaptiveCurveIrm(config, OWNER);
            vm.warp(timestamps[i]);
            _bindAndAssert(OTHER, INITIAL_RATE, uint48(timestamps[i]));
        }
    }

    function test_WhenBindingAfterZeroAtOversizedTimestamp_AdaptsUsingTruncatedTime() public {
        _bindAndAssert(address(0), INITIAL_RATE, uint48(START));
        vm.warp((uint256(1) << 48) + 37);
        // A prior zero binding initialized the rate. The second binding computes
        // elapsed time against the truncated timestamp and reaches the rate floor.
        _bindAndAssert(address(market), config.minRateAtTarget, 37);
    }

    function _bindAndAssert(address suppliedMarket, int256 rate, uint48 timestamp) internal {
        vm.recordLogs();
        irm.setMarket(suppliedMarket);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(irm.market(), suppliedMarket);
        assertEq(irm.owner(), OWNER);
        _assertState(rate, timestamp);
        _assertConfig(config);
        assertEq(logs.length, 1);
        _assertStateLog(logs[0], rate, timestamp);
    }
}
