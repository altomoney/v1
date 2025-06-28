// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Participation, Bucket} from "@alto/rewards/interfaces/ITWAlto.sol";

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

    modifier givenCallerIsNotParticipant() {
        // Setup will be done in test where Bob tries to reuse for Alice
        _;
    }

    modifier givenCallerIsAuthorized() {
        // Setup will be done in individual tests
        _;
    }

    modifier givenPositionLockAmountIsZero() {
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

    modifier whenLastProcessedEpochIsBehindCurrentEpoch() {
        skip(EPOCH_DURATION * 2); // Skip ahead without advancing epochs
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

    function test_RevertWhen_CallerIsNotParticipant()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsNotParticipant
    {
        // Setup: Alice has position, Bob tries to reuse for Alice
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // It should revert with NotAuthorized
        vm.expectRevert(TWAltoErrorsLib.NotAuthorized.selector);
        vm.prank(bob);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);
    }

    function test_RevertWhen_PositionLockAmountIsZero()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenPositionLockAmountIsZero
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

    function test_WhenLastProcessedEpochIsBehindCurrentEpoch()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenLastProcessedEpochIsBehindCurrentEpoch
        whenAllConditionsAreValid
    {
        // Setup: Create position to reuse
        _participateHelper(alice, AMOUNT, SOURCE_BUCKET_ID);

        // Fast forward time to create gap between lastProcessedEpoch and currentEpoch
        skip(EPOCH_DURATION * 2);

        uint256 epochBefore = twAlto.lastProcessedEpoch();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify we're behind
        assertLt(epochBefore, currentEpoch);

        // It should advance epoch before proceeding
        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify epoch was advanced
        assertEq(twAlto.lastProcessedEpoch(), currentEpoch);
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

        // Get position before reuse
        Participation memory positionBefore = twAlto.getParticipation(alice, TARGET_BUCKET_ID);

        uint256 epochDuration = twAlto.EPOCH_DURATION();

        vm.warp(positionBefore.expiry + 1);
        // Advance 100000 epochs is just a sanity check
        twAlto.advanceEpoch(100000);

        assertEq(twAlto.lastProcessedEpoch(), 1);
        assertEq(twAlto.currentEpoch(), 1);

        uint256 contractBalanceBefore = IERC20(address(alto)).balanceOf(address(twAlto));
        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);

        Bucket memory bucketAfter = twAlto.getBucket(TARGET_BUCKET_ID);
        uint256 newExpiry = block.timestamp + (bucketAfter.lockEpochDuration * epochDuration);

        // It should emit Participate event with position lockAmount that it had before the reuse
        vm.expectEmit();
        emit TWAltoEventsLib.Participate(alice, positionBefore.bucketId, positionBefore.lockAmount, 1, newExpiry, true);

        vm.prank(alice);
        twAlto.reuseParticipation(alice, TARGET_BUCKET_ID);

        // Verify position was updated correctly
        Participation memory positionAfter = twAlto.getParticipation(alice, TARGET_BUCKET_ID);

        // It should reuse the position lockAmount
        assertEq(positionAfter.lockAmount, positionBefore.lockAmount);

        // It should update expiry to new bucket lock duration
        assertEq(positionAfter.expiry, newExpiry);

        // It should update lockedAt to current timestamp
        assertEq(positionAfter.lockedAt, block.timestamp);

        // It should not transfer TAP (reuse existing)
        assertEq(IERC20(address(alto)).balanceOf(address(twAlto)), contractBalanceBefore);
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore);
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
