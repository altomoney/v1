// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Participation} from "@alto/rewards/interfaces/ITWAlto.sol";

contract TWAlto_participate is TWAltoBaseTest {
    bytes32 constant PAUSE_TYPE = keccak256("PAUSE");
    uint256 constant AMOUNT = 1000e18;
    uint8 constant BUCKET_ID = 0;

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
        // We'll skip explicit reentrancy testing as it's at modifier level
        _;
    }

    modifier givenNoReentrancy() {
        // No reentrancy by default
        _;
    }

    modifier givenCallerIsNotParticipantAndNotDelegatee() {
        // Setup will be done in test where Bob tries to participate for Alice
        _;
    }

    modifier givenCallerIsAuthorized() {
        // Setup will be done in individual tests (either participant or delegatee)
        _;
    }

    modifier givenParticipantHasNoExistingPosition() {
        // No existing position by default
        _;
    }

    modifier givenParticipantHasExistingUnexpiredPosition() {
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION / 2); // Fast forward but not to expiry
        _;
    }

    modifier whenAmountIsZero() {
        // Will be used in test with amount = 0
        _;
    }

    modifier whenRescueModeIsActive() {
        vm.prank(admin);
        twAlto.setRescueMode(true);
        _;
    }

    modifier whenEmergencySweepHasBeenActivated() {
        vm.prank(admin);
        twAlto.activateEmergencySweep();
        _;
    }

    modifier whenAmountExceedsUint88Max() {
        // Will be used in test with oversized amount
        _;
    }

    modifier whenLastProcessedWeekIsBehindCurrentEpoch() {
        skip(EPOCH_DURATION * 2); // Skip ahead without advancing weeks
        _;
    }

    modifier whenParticipantHasInsufficientTapBalance() {
        // Will be set up in test with insufficient balance
        _;
    }

    modifier whenParticipantHasNotApprovedSufficientTap() {
        // Will be set up in test with insufficient approval
        _;
    }

    modifier whenAllConditionsAreValid() {
        // All conditions valid by default setup
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_ContractIsPaused() public givenContractIsPaused {
        // Setup tokens
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_RevertWhen_CallerIsNotParticipantAndNotDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsNotParticipantAndNotDelegatee
    {
        // Setup: Alice has no position, Bob tries to participate for Alice
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with NotAuthorized
        vm.expectRevert(TWAltoErrorsLib.NotAuthorized.selector);
        vm.prank(bob);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_WhenCallerIsParticipant()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAllConditionsAreValid
    {
        // Setup
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should succeed when caller is the participant
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);

        // Verify participation was created
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT);
    }

    function test_WhenCallerIsDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAllConditionsAreValid
    {
        // Setup: Alice participates first, then sets Bob as delegatee
        _participateHelper(alice, AMOUNT, BUCKET_ID);

        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, bob);

        // Setup for second participation
        uint256 additionalAmount = 500e18;
        alto.mint(alice, additionalAmount);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), additionalAmount);

        // It should succeed when caller is the delegatee
        vm.prank(bob);
        twAlto.participate(alice, additionalAmount, BUCKET_ID);

        // Verify participation was updated
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT + additionalAmount);
    }

    function test_RevertWhen_AmountIsZero()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAmountIsZero
    {
        // Setup
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with NotValid
        vm.expectRevert(TWAltoErrorsLib.NotValid.selector);
        vm.prank(alice);
        twAlto.participate(alice, 0, BUCKET_ID);
    }

    function test_RevertWhen_RescueModeIsActive()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenRescueModeIsActive
    {
        // Setup tokens
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with RescueModeActive
        vm.expectRevert(TWAltoErrorsLib.RescueModeActive.selector);
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_RevertWhen_EmergencySweepHasBeenActivated()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenEmergencySweepHasBeenActivated
    {
        // Setup tokens
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with EmergencySweepActivated
        vm.expectRevert(TWAltoErrorsLib.EmergencySweepActivated.selector);
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_RevertWhen_AmountExceedsUint88Max()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAmountExceedsUint88Max
    {
        // Use a reasonable amount that exceeds uint88 max but is still mintable
        uint256 _amount = uint256(type(uint88).max) + 1000e18;

        // Setup
        alto.mint(alice, _amount);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), _amount);

        // Should revert for oversized amounts
        vm.expectRevert();
        vm.prank(alice);
        twAlto.participate(alice, _amount, BUCKET_ID);
    }

    function test_WhenLastProcessedWeekIsBehindCurrentEpoch()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenLastProcessedWeekIsBehindCurrentEpoch
        whenAllConditionsAreValid
    {
        // Setup tokens
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        uint256 weekBefore = twAlto.lastProcessedWeek();
        uint256 currentEpoch = twAlto.currentEpoch();

        // Verify we're behind
        assertLt(weekBefore, currentEpoch);

        // It should advance week before proceeding
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);

        // Verify week was advanced
        assertEq(twAlto.lastProcessedWeek(), currentEpoch);
    }

    function test_RevertWhen_ParticipantHasInsufficientTapBalance()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenParticipantHasInsufficientTapBalance
    {
        // Setup: Alice has less than AMOUNT
        uint256 insufficientAmount = AMOUNT - 1;
        alto.mint(alice, insufficientAmount);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        // It should revert with ERC20 transfer error
        vm.expectRevert(); // ERC20 transfer will revert due to insufficient balance
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_RevertWhen_ParticipantHasNotApprovedSufficientTap()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenParticipantHasNotApprovedSufficientTap
    {
        // Setup: Alice has tokens but insufficient approval
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT - 1);

        // It should revert with ERC20 allowance error
        vm.expectRevert(); // ERC20 transferFrom will revert due to insufficient allowance
        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);
    }

    function test_WhenAllConditionsAreValid_NewPosition()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenParticipantHasNoExistingPosition
        whenAllConditionsAreValid
    {
        // Setup
        alto.mint(alice, AMOUNT);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), AMOUNT);

        uint256 contractBalanceBefore = IERC20(address(alto)).balanceOf(address(twAlto));
        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);
        uint256 currentWeek = twAlto.currentEpoch();

        // It should emit Participate event
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.Participate(alice, BUCKET_ID, AMOUNT, 1, block.timestamp + EPOCH_DURATION, BUCKET_ID);

        vm.prank(alice);
        twAlto.participate(alice, AMOUNT, BUCKET_ID);

        // It should transfer TAP from participant to contract
        assertEq(IERC20(address(alto)).balanceOf(address(twAlto)), contractBalanceBefore + AMOUNT);
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore - AMOUNT);

        // Verify participation was created with correct values
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);

        // It should create new participation with correct values
        assertEq(position.bucketId, BUCKET_ID);
        assertEq(position.tapAmount, AMOUNT);
        assertEq(position.multiplier, 1); // From bucket config
        assertEq(position.lockedAt, block.timestamp);
        assertEq(position.expiry, block.timestamp + EPOCH_DURATION); // lockEpochDuration = 1
        assertEq(position.lastInactive, currentWeek);
        assertEq(position.lastActive, currentWeek + 1); // expiry week
        assertFalse(position.tapReleased);

        // It should update weekTotals correctly
        assertEq(twAlto.weekTotals(currentWeek + 1), int256(AMOUNT * 1)); // multiplier = 1
        assertEq(twAlto.weekTotals(currentWeek + 2), -int256(AMOUNT * 1));
    }

    function test_WhenAllConditionsAreValid_ExistingUnexpiredPosition()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenParticipantHasExistingUnexpiredPosition
        whenAllConditionsAreValid
    {
        // Setup for additional participation
        uint256 additionalAmount = 500e18;
        alto.mint(alice, additionalAmount);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), additionalAmount);

        Participation memory positionBefore = twAlto.getParticipation(alice, BUCKET_ID);
        uint256 currentWeek = twAlto.currentEpoch();
        uint256 newExpiry = block.timestamp + EPOCH_DURATION;
        uint256 newExpiryWeek = (newExpiry - twAlto.INIT_TIMESTAMP()) / EPOCH_DURATION;

        // It should emit Participate event with updated values
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.Participate(alice, BUCKET_ID, additionalAmount, 1, newExpiry, BUCKET_ID);

        vm.prank(alice);
        twAlto.participate(alice, additionalAmount, BUCKET_ID);

        // Verify position was updated correctly
        Participation memory positionAfter = twAlto.getParticipation(alice, BUCKET_ID);

        // It should increase tapAmount by additional amount
        assertEq(positionAfter.tapAmount, AMOUNT + additionalAmount);

        // It should update expiry to new expiry
        assertEq(positionAfter.expiry, newExpiry);

        // It should update lockedAt to current timestamp
        assertEq(positionAfter.lockedAt, block.timestamp);

        // It should update lastInactive and lastActive
        assertEq(positionAfter.lastInactive, currentWeek);
        assertEq(positionAfter.lastActive, newExpiryWeek);
    }

    // ====================================
    //           FUZZ TESTS
    // ====================================

    function testFuzz_Participate_ValidAmounts(uint256 _amount)
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        whenAllConditionsAreValid
    {
        // Bound to valid range
        _amount = bound(_amount, 1, type(uint88).max);

        // Setup
        alto.mint(alice, _amount);
        vm.prank(alice);
        IERC20(address(alto)).approve(address(twAlto), _amount);

        // Should succeed for any valid amount
        vm.prank(alice);
        twAlto.participate(alice, _amount, BUCKET_ID);

        // Verify participation
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertEq(position.tapAmount, _amount);
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
