// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";

import {IRState} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

import {PegResponsiveExponentialIrmCommon} from "./PegResponsiveExponentialIrmCommon.t.sol";

contract PegResponsiveExponentialIrmUpdateInterestRateViewTest is PegResponsiveExponentialIrmCommon {
    function test_RevertWhen_MarketIsNotSet() external {
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();
        vm.recordLogs();

        vm.expectRevert(IIrm.IrmMarketNotSet.selector);
        irm.updateInterestRateView(1, 1);

        _assertIRState(stateBefore);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_RevertWhen_BlockTimestampIsBeforeLastUpdate() external {
        _bindMarket();
        _mockOracleReturnData(hex"01");
        _setIRState(BASE_RATE, uint48(block.timestamp + 1), 0, false);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert(stdError.arithmeticError);
        irm.updateInterestRateView(0, 0);

        _assertIRState(stateBefore);
    }

    function test_RevertWhen_CompoundInterestCalculationOverflows() external {
        _bindMarket();
        _mockOracleReturnData(hex"01");
        _setIRState(1, 0, 0, false);
        vm.warp(uint256(1) << 128);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert(stdError.arithmeticError);
        irm.updateInterestRateView(0, 0);

        _assertIRState(stateBefore);
    }

    function test_RevertWhen_FinalDebtMultiplicationOverflows() external {
        _bindMarket();
        _mockOracleReturnData(hex"01");
        _setIRState(2, uint48(block.timestamp - 1), 0, false);
        IRState memory stateBefore = _readIRState();

        vm.expectRevert(stdError.arithmeticError);
        irm.updateInterestRateView(0, type(uint256).max);

        _assertIRState(stateBefore);
    }

    function test_WhenElapsedTimeIsZero() external {
        _bindMarket();
        _setIRState(STRESS_RATE, uint48(block.timestamp), 77, true);
        IRState memory stateBefore = _readIRState();

        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(type(uint256).max, type(uint256).max);

        assertEq(interest, 0);
        assertEq(borrowRate, STRESS_RATE);
        _assertIRState(stateBefore);
    }

    function test_WhenTotalBorrowedIsZero() external {
        _bindMarket();
        _setIRState(MAX_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 365 days);
        IRState memory stateBefore = _readIRState();

        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(type(uint256).max, 0);

        assertEq(interest, 0);
        assertEq(borrowRate, MAX_RATE);
        _assertIRState(stateBefore);
    }

    function test_WhenInputsAreSupported_ItReturnsTheExactCompoundInterestAndStoredRate() external {
        uint256 storedRate = 1_000_000_000;
        uint256 elapsed = 1_000;
        uint256 debt = 1_000e18;
        uint256 expectedFactor = 1_000_000_500_000;
        uint256 expectedInterest = 1_000_000_500_000_000;

        _bindMarket();
        _setIRState(storedRate, uint48(block.timestamp), 123, true);
        vm.warp(block.timestamp + elapsed);
        IRState memory stateBefore = _readIRState();

        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(77, debt);

        assertEq(_expectedInterest(debt, storedRate, elapsed), expectedInterest);
        assertEq(storedRate * elapsed + (storedRate * elapsed) ** 2 / 2e18, expectedFactor);
        assertEq(interest, expectedInterest);
        assertEq(borrowRate, storedRate);
        _assertIRState(stateBefore);
    }

    function test_WhenFinalFixedPointMultiplicationHasRemainder_ItRoundsDown() external {
        _bindMarket();
        _setIRState(1, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 1);

        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(0, 1e18 - 1);

        assertEq(interest, 0);
        assertEq(borrowRate, 1);
    }

    function test_WhenTotalSupplyVaries_ItReturnsIdenticalValues() external {
        _bindMarket();
        _setIRState(BASE_RATE, uint48(block.timestamp), 0, false);
        vm.warp(block.timestamp + 1 days);

        (uint256 firstInterest, uint256 firstRate) = irm.updateInterestRateView(0, 123e18);
        (uint256 secondInterest, uint256 secondRate) = irm.updateInterestRateView(type(uint256).max, 123e18);

        assertEq(secondInterest, firstInterest);
        assertEq(secondRate, firstRate);
    }

    function test_WhenCalledByAnyAddress_ItDoesNotReadOracleOrMarketAndDoesNotMutateState() external {
        _bindMarket();
        _setIRState(BASE_RATE, uint48(block.timestamp - 10), 99, true);
        _mockOracleReturnData(hex"01");
        IRState memory stateBefore = _readIRState();

        vm.recordLogs();
        vm.prank(NON_OWNER);
        (uint256 interest, uint256 borrowRate) = irm.updateInterestRateView(1, 2e18);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(interest, _expectedInterest(2e18, BASE_RATE, 10));
        assertEq(borrowRate, BASE_RATE);
        assertEq(logs.length, 0);
        _assertIRState(stateBefore);
    }
}
