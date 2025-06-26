// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";

contract TWAlto_advanceEpoch is TWAltoBaseTest {
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

    modifier whenLastProcessedEpochEqualsCurrentEpoch() {
        // Contract starts with lastProcessedEpoch = 0 and currentEpoch = 0
        _;
    }

    modifier whenLimitIsValidAndLastProcessedEpochIsBehind() {
        // Skip time to create a gap
        skip(EPOCH_DURATION * 3);
        _;
    }

    modifier whenGoalMinusEpochIsGreaterThanLimit() {
        // Will be set up in specific test
        _;
    }

    modifier whenGoalMinusEpochIsLessOrEqualThanLimit() {
        // Will be set up in specific test
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_LimitIsZero() public givenNoReentrancy whenLimitIsZero {
        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        twAlto.advanceEpoch(0);
    }

    function test_RevertWhen_LastProcessedEpochEqualsCurrentEpoch()
        public
        givenNoReentrancy
        whenLastProcessedEpochEqualsCurrentEpoch
    {
        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        twAlto.advanceEpoch(1);
    }

    function test_ProcessOnlyLimitEpochs_WhenGoalMinusEpochIsGreaterThanLimit()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedEpochIsBehind
        whenGoalMinusEpochIsGreaterThanLimit
    {
        uint256 limit = 2;
        uint256 epochBefore = twAlto.lastProcessedEpoch();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify we have more epochs than limit
        assertGt(currentEpoch - epochBefore, limit);

        // It should emit AdvanceEpoch event
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(epochBefore + limit, epochBefore + limit);

        twAlto.advanceEpoch(limit);

        // It should update lastProcessedEpoch to epoch plus limit
        assertEq(twAlto.lastProcessedEpoch(), epochBefore + limit);

        // Should not process all the way to current epoch
        assertLt(twAlto.lastProcessedEpoch(), currentEpoch);
    }

    function test_ProcessAllPendingEpochs_WhenGoalMinusEpochIsLessOrEqualThanLimit()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedEpochIsBehind
        whenGoalMinusEpochIsLessOrEqualThanLimit
    {
        uint256 limit = 10; // Large enough limit
        uint256 epochBefore = twAlto.lastProcessedEpoch();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify limit is greater than or equal to pending epochs
        assertGe(limit, currentEpoch - epochBefore);

        // It should emit AdvanceEpoch event
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(currentEpoch, currentEpoch);

        twAlto.advanceEpoch(limit);

        // It should update lastProcessedEpoch to currentEpoch
        assertEq(twAlto.lastProcessedEpoch(), currentEpoch);
    }

    function test_AdvanceEpoch_CallsInternalAdvanceEpoch()
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedEpochIsBehind
    {
        uint256 limit = 2;
        uint256 epochBefore = twAlto.lastProcessedEpoch();

        // It should emit AdvanceEpoch event indicating internal function was called
        vm.expectEmit(true, true, false, false);
        emit AdvanceEpoch(epochBefore + limit, epochBefore + limit);

        twAlto.advanceEpoch(limit);
    }

    // ====================================
    //         FUZZ TESTS
    // ====================================

    function testFuzz_AdvanceEpoch_ValidLimits(uint256 _limit)
        public
        givenNoReentrancy
        whenLimitIsValidAndLastProcessedEpochIsBehind
    {
        // Bound to valid range
        _limit = bound(_limit, 1, 100);

        uint256 epochBefore = twAlto.lastProcessedEpoch();
        uint256 currentEpoch = twAlto.currentEpoch();

        twAlto.advanceEpoch(_limit);

        // Should advance at least some epochs
        assertGt(twAlto.lastProcessedEpoch(), epochBefore);

        // Should not exceed current epoch
        assertLe(twAlto.lastProcessedEpoch(), currentEpoch);
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
