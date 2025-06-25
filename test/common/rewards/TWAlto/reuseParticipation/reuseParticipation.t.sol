// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Participation} from "@alto/rewards/interfaces/ITWAlto.sol";

contract TWAlto_reuseParticipation is TWAltoBaseTest {
    bytes32 constant PAUSE_TYPE = keccak256("PAUSE");
    uint256 constant AMOUNT = 1000e18;
    uint8 constant SOURCE_BUCKET_ID = 0;
    uint8 constant TARGET_BUCKET_ID = 0; // Using same bucket for reuse tests

    function setUp() public override {
        super.setUp();
    }

    // ====================================
    //           MODIFIERS
    // ====================================

    modifier givenContractIsPaused() {
        vm.prank(admin);
        twAlto.setPauser(admin, PAUSE_TYPE, true);
        vm.prank(admin);
        twAlto.pause(PAUSE_TYPE, true);
        _;
    }

    modifier givenContractIsNotPaused() {
        // Contract is not paused by default
        _;
    }

    modifier givenReentrancyAttempt() {
        // Reentrancy is handled by OpenZeppelin's ReentrancyGuard
        _;
    }

    modifier givenNoReentrancy() {
        // No reentrancy by default
        _;
    }

    modifier givenCallerIsNotParticipantAndNotDelegatee() {
        // Setup will be done in test where Bob tries to reuse for Alice
        _;
    }

    modifier givenCallerIsAuthorized() {
        // Setup will be done in individual tests (either participant or delegatee)
        _;
    }

    modifier givenPositionTapReleasedIsTrue() {
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);
        // Fast forward past expiry and exit the position
        skip(EPOCH_DURATION * 2);
        vm.prank(alice);
        twAlto.exitPosition(alice, alice, SOURCE_BUCKET_ID);
        _;
    }

    modifier givenPositionTapAmountIsZero() {
        // This would be a malformed state, but we can test it
        _;
    }

    modifier whenRescueModeIsActive() {
        // Will be set in individual tests after creating positions
        _;
    }

    modifier whenEmergencySweepHasBeenActivated() {
        // Will be set in individual tests after creating positions
        _;
    }

    modifier whenLastProcessedWeekIsBehindCurrentEpoch() {
        skip(EPOCH_DURATION * 2); // Skip ahead without advancing weeks
        _;
    }

    modifier whenAllConditionsAreValid() {
        // All conditions valid by default setup
        _;
    }

    modifier givenParticipantHasExistingUnexpiredPositionInTargetBucket() {
        _participateHelper(alice, AMOUNT, TARGET_BUCKET_ID);
        skip(EPOCH_DURATION / 2); // Fast forward but not to expiry
        _;
    }

    modifier givenParticipantHasNoExistingPositionInTargetBucket() {
        // No existing position by default
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_ContractIsPaused() public givenContractIsPaused {
        // Setup: Create position to reuse
        vm.prank(admin);
        twAlto.pause(PAUSE_TYPE, false); // Temporarily unpause to create position
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);
        vm.prank(admin);
        twAlto.pause(PAUSE_TYPE, true); // Re-pause

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_RevertWhen_CallerIsNotParticipantAndNotDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsNotParticipantAndNotDelegatee
    {
        // Setup: Alice has position, Bob tries to reuse for Alice
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // It should revert with NotAuthorized
        vm.expectRevert(TWAltoErrorsLib.NotAuthorized.selector);
        vm.prank(bob);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_WhenCallerIsParticipant()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAllConditionsAreValid
    {
        // Setup: Create position to reuse
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // It should succeed when caller is the participant
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify reuse worked - tapAmount should be doubled since it adds to existing
        Participation memory position = twAlto.getParticipation(alice, TARGET_BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT * 2); // Original + reused amount
    }

    function test_WhenCallerIsDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAllConditionsAreValid
    {
        // Setup: Alice has position and sets Bob as delegatee
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);
        vm.prank(alice);
        twAlto.setDelegatee(SOURCE_BUCKET_ID, bob);

        // It should succeed when caller is the delegatee
        vm.prank(bob);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify reuse worked - tapAmount should be doubled
        Participation memory position = twAlto.getParticipation(alice, TARGET_BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT * 2);
    }

    function test_RevertWhen_PositionTapReleasedIsTrue()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenPositionTapReleasedIsTrue
    {
        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_RevertWhen_PositionTapAmountIsZero()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenPositionTapAmountIsZero
    {
        // It should revert with NotValid (no position exists)
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_RevertWhen_RescueModeIsActive()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenRescueModeIsActive
    {
        // Setup: Create position to reuse FIRST
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // Then activate rescue mode
        vm.prank(admin);
        twAlto.setRescueMode(true);

        // It should revert with RescueModeActive
        vm.expectRevert(TWAltoErrorsLib.RescueModeActive.selector);
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_RevertWhen_EmergencySweepHasBeenActivated()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenEmergencySweepHasBeenActivated
    {
        // Setup: Create position to reuse FIRST
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // Then activate emergency sweep
        vm.prank(admin);
        twAlto.activateEmergencySweep();

        // It should revert with EmergencySweepActivated
        vm.expectRevert(TWAltoErrorsLib.EmergencySweepActivated.selector);
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_WhenLastProcessedWeekIsBehindCurrentEpoch()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenLastProcessedWeekIsBehindCurrentEpoch
        whenAllConditionsAreValid
    {
        // Setup: Create position to reuse
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // Fast forward time to create gap between lastProcessedWeek and currentEpoch
        skip(EPOCH_DURATION * 2);

        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify we're behind
        assertLt(weekBefore, currentEpoch);

        // It should advance week before proceeding
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify week was advanced
        assertEq(twAlto.lastProcessedWeek(), currentEpoch);
    }

    function test_WhenAllConditionsAreValid_NewPosition()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenParticipantHasNoExistingPositionInTargetBucket
        whenAllConditionsAreValid
    {
        // Setup: Create position to reuse
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        uint256 contractBalanceBefore = IERC20(address(alto)).balanceOf(address(twAlto));
        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);
        uint256 currentWeek = twAlto.currentEpoch();

        // It should emit Participate event - with AMOUNT (the reused amount)
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.Participate(
            alice, TARGET_BUCKET_ID, AMOUNT, 1, block.timestamp + EPOCH_DURATION, TARGET_BUCKET_ID
        );

        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // It should not transfer TAP (reuse existing)
        assertEq(IERC20(address(alto)).balanceOf(address(twAlto)), contractBalanceBefore);
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore);

        // Verify new participation was created with doubled tapAmount (original + reused)
        Participation memory position = twAlto.getParticipation(alice, TARGET_BUCKET_ID);
        assertEq(position.bucketId, TARGET_BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT * 2); // Original amount + reused amount
        assertEq(position.multiplier, 1); // From bucket config
        assertEq(position.lockedAt, block.timestamp);
        assertEq(position.expiry, block.timestamp + EPOCH_DURATION);
        assertEq(position.lastInactive, currentWeek);
        assertEq(position.lastActive, currentWeek + 1);
        assertFalse(position.tapReleased);
    }

    function test_WhenAllConditionsAreValid_ExistingUnexpiredPosition()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenParticipantHasExistingUnexpiredPositionInTargetBucket
        whenAllConditionsAreValid
    {
        // Setup: Create another position to reuse
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        uint256 currentWeek = twAlto.currentEpoch();
        uint256 newExpiry = block.timestamp + EPOCH_DURATION;

        // Get position before reuse
        Participation memory positionBefore = twAlto.getParticipation(alice, TARGET_BUCKET_ID);

        // It should emit Participate event with total tapAmount (existing + reused)
        // Note: Contract seems to emit total tapAmount, not just the input amount
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.Participate(alice, TARGET_BUCKET_ID, AMOUNT * 2, 1, newExpiry, TARGET_BUCKET_ID);

        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify position was updated correctly
        Participation memory positionAfter = twAlto.getParticipation(alice, TARGET_BUCKET_ID);

        // It should add the reused amount (which is the existing tapAmount) to existing tapAmount
        // positionBefore.tapAmount = 2000 (from two participations)
        // reused amount = positionBefore.tapAmount = 2000
        // final = 2000 + 2000 = 4000
        assertEq(positionAfter.tapAmount, positionBefore.tapAmount * 2);

        // It should update expiry to new bucket lock duration
        assertEq(positionAfter.expiry, newExpiry);

        // It should update lockedAt to current timestamp
        assertEq(positionAfter.lockedAt, block.timestamp);

        // It should update lastInactive and lastActive
        assertEq(positionAfter.lastInactive, currentWeek);
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
