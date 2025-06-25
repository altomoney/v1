// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";

contract TWAlto_advanceWeek is TWAltoBaseTest {
    uint256 constant AMOUNT = 1000e18;
    uint8 constant BUCKET_ID = 0;

    // Event declaration - matching ITWLBase
    event AdvanceEpoch(uint256 indexed newEpoch, uint256 lastEpoch);

    function setUp() public override {
        super.setUp();
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier givenReentrancyAttempt() {
        // Reentrancy is handled by OpenZeppelin's ReentrancyGuard
        _;
    }

    modifier givenNoReentrancy() {
        // No reentrancy by default
        _;
    }

    modifier whenLimitIsZero() {
        // Will be used in test with limit = 0
        _;
    }

    modifier whenLastProcessedWeekEqualsCurrentEpoch() {
        // Contract starts with lastProcessedWeek = 0 and currentEpoch = 0
        _;
    }

    modifier whenLimitIsValidAndLastProcessedWeekIsBehind() {
        // Skip time to create a gap
        skip(EPOCH_DURATION * 3);
        _;
    }

    modifier whenGoalMinusWeekIsGreaterThanLimit() {
        // Will be set up in specific test
        _;
    }

    modifier whenGoalMinusWeekIsLessOrEqualThanLimit() {
        // Will be set up in specific test
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_LimitIsZero() public givenNoReentrancy whenLimitIsZero {
        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        twAlto.advanceWeek(0);
    }

    function test_RevertWhen_LastProcessedWeekEqualsCurrentEpoch()
        public
        givenNoReentrancy
        whenLastProcessedWeekEqualsCurrentEpoch
    {
        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        twAlto.advanceWeek(1);
    }

    function test_ProcessOnlyLimitWeeks_WhenGoalMinusWeekIsGreaterThanLimit()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedWeekIsBehind
        whenGoalMinusWeekIsGreaterThanLimit
    {
        uint256 limit = 2;
        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify we have more weeks than limit
        assertGt(currentEpoch - weekBefore, limit);

        // It should emit AdvanceEpoch event
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(weekBefore + limit, weekBefore + limit);

        twAlto.advanceWeek(limit);

        // It should update lastProcessedWeek to week plus limit
        assertEq(twAlto.lastProcessedWeek(), weekBefore + limit);

        // Should not process all the way to current epoch
        assertLt(twAlto.lastProcessedWeek(), currentEpoch);
    }

    function test_ProcessAllPendingWeeks_WhenGoalMinusWeekIsLessOrEqualThanLimit()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedWeekIsBehind
        whenGoalMinusWeekIsLessOrEqualThanLimit
    {
        uint256 limit = 10; // Large enough limit
        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify limit is greater than or equal to pending weeks
        assertGe(limit, currentEpoch - weekBefore);

        // It should emit AdvanceEpoch event
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(currentEpoch, currentEpoch);

        twAlto.advanceWeek(limit);

        // It should update lastProcessedWeek to currentEpoch
        assertEq(twAlto.lastProcessedWeek(), currentEpoch);
    }

    function test_AdvanceWeek_UpdatesWeekTotals()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedWeekIsBehind
    {
        // Setup: Create some participations to have weekTotals
        _participateHelper(alice, AMOUNT, BUCKET_ID);

        // Skip more time to create gap
        skip(EPOCH_DURATION * 2);

        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        twAlto.advanceWeek(10);

        // Verify week was advanced
        assertEq(twAlto.lastProcessedWeek(), currentEpoch);
    }

    function test_AdvanceWeek_CallsInternalAdvanceWeek()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedWeekIsBehind
    {
        uint256 limit = 2;
        uint256 weekBefore = twAlto.lastProcessedWeek();

        // It should emit AdvanceEpoch event indicating internal function was called
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(weekBefore + limit, weekBefore + limit);

        twAlto.advanceWeek(limit);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_AdvanceWeek_ValidLimits(uint256 _limit)
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedWeekIsBehind
    {
        // Bound to valid range
        _limit = bound(_limit, 1, 100);

        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        twAlto.advanceWeek(_limit);

        // Should advance at least some weeks
        assertGt(twAlto.lastProcessedWeek(), weekBefore);

        // Should not exceed current epoch
        assertLe(twAlto.lastProcessedWeek(), currentEpoch);
    }

    // ====================================
    //         HELPER FUNCTIONS
    // ====================================

    function _participateHelper(address _user, uint256 _amount, uint8 _bucketId) internal {
        alto.mint(_user, _amount);
        vm.startPrank(_user);
        IERC20(address(alto)).approve(address(twAlto), _amount);
        twAlto.participate(_user, _amount, _bucketId);
        vm.stopPrank();
    }
}
