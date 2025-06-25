// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TWAltoBaseTest} from "../TWAltoBaseTest.sol";
import {TWAltoErrorsLib} from "@alto/rewards/libraries/TWAltoErrorsLib.sol";
import {TWAltoEventsLib} from "@alto/rewards/libraries/TWAltoEventsLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {Participation} from "@alto/rewards/interfaces/ITWAlto.sol";

contract TWAlto_exitPosition is TWAltoBaseTest {
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
        _;
    }

    modifier givenNoReentrancy() {
        // No reentrancy by default
        _;
    }

    modifier givenCallerIsNotParticipantAndNotDelegatee() {
        // Setup will be done in test where Bob tries to exit for Alice
        _;
    }

    modifier givenCallerIsAuthorized() {
        // Setup will be done in individual tests (either participant or delegatee)
        _;
    }

    modifier givenRescueModeIsInactive() {
        // Rescue mode is inactive by default
        _;
    }

    modifier givenRescueModeIsActive() {
        vm.prank(admin);
        twAlto.setRescueMode(true);
        _;
    }

    modifier givenPositionLockHasNotExpired() {
        // Position will have future expiry
        _;
    }

    modifier givenPositionLockHasExpired() {
        // Fast forward past expiry
        skip(EPOCH_DURATION * 2);
        _;
    }

    modifier givenPositionTapReleasedIsTrue() {
        // Position has already been exited
        _;
    }

    modifier givenPositionTapReleasedIsFalse() {
        // Position is still active
        _;
    }

    // ====================================
    //           TESTS
    // ====================================

    function test_RevertWhen_ContractIsPaused() public givenContractIsPaused {
        // Setup: Create position first
        vm.prank(admin);
        twAlto.pause(PAUSE_TYPE, false); // Temporarily unpause to create position
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        vm.prank(admin);
        twAlto.pause(PAUSE_TYPE, true); // Re-pause

        // It should revert with IsPaused
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        vm.prank(alice);
        twAlto.exitPosition(alice, alice, BUCKET_ID);
    }

    function test_RevertWhen_CallerIsNotParticipantAndNotDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsNotParticipantAndNotDelegatee
    {
        // Setup: Alice has position, Bob tries to exit for Alice
        _participateHelper(alice, AMOUNT, BUCKET_ID);

        // It should revert with NotAuthorized
        vm.expectRevert(TWAltoErrorsLib.NotAuthorized.selector);
        vm.prank(bob);
        twAlto.exitPosition(alice, bob, BUCKET_ID);
    }

    function test_RevertWhen_PositionLockHasNotExpired()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasNotExpired
    {
        // Setup: Create position with future expiry
        _participateHelper(alice, AMOUNT, BUCKET_ID);

        // It should revert with LockNotExpired
        vm.expectRevert(TWAltoErrorsLib.LockNotExpired.selector);
        vm.prank(alice);
        twAlto.exitPosition(alice, alice, BUCKET_ID);
    }

    function test_ReturnZero_WhenPositionTapReleasedIsTrue_ExpiredLock()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasExpired
        givenPositionTapReleasedIsTrue
    {
        // Setup: Create position, wait for expiry, then exit once to set tapReleased
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION * 2);

        vm.prank(alice);
        uint256 firstExitAmount = twAlto.exitPosition(alice, alice, BUCKET_ID);

        // Verify first exit worked
        assertEq(firstExitAmount, AMOUNT);

        // Now position should have tapReleased = true
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertTrue(position.tapReleased);

        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);

        // Second exit should return 0 and not transfer
        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, alice, BUCKET_ID);

        // It should return 0
        assertEq(exitAmount, 0);

        // It should not transfer any tokens
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore);
    }

    function test_ReturnZero_WhenPositionTapReleasedIsTrue_RescueMode()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenPositionTapReleasedIsTrue
    {
        // Setup: Create position, exit once to set tapReleased, then activate rescue mode
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION * 2);

        vm.prank(alice);
        twAlto.exitPosition(alice, alice, BUCKET_ID);

        // Now activate rescue mode
        vm.prank(admin);
        twAlto.setRescueMode(true);

        // Position should have tapReleased = true
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertTrue(position.tapReleased);

        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);

        // Second exit should return 0 and not transfer
        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, alice, BUCKET_ID);

        // It should return 0
        assertEq(exitAmount, 0);

        // It should not transfer any tokens
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore);
    }

    function test_SuccessfulExit_WhenPositionTapReleasedIsFalse_ExpiredLock()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasExpired
        givenPositionTapReleasedIsFalse
    {
        // Setup: Create position and wait for expiry
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION * 2);

        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);

        // It should emit ExitPosition event
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.ExitPosition(BUCKET_ID, alice, AMOUNT);

        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, alice, BUCKET_ID);

        // It should return tapAmount
        assertEq(exitAmount, AMOUNT);

        // It should transfer TAP to recipient
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore + AMOUNT);

        // It should update position state
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertTrue(position.tapReleased);
        assertEq(position.tapAmount, 0);
        assertEq(position.expiry, 0);
    }

    function test_SuccessfulExit_WhenPositionTapReleasedIsFalse_RescueMode()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenPositionTapReleasedIsFalse
    {
        // Setup: Create position (no need to wait for expiry in rescue mode)
        _participateHelper(alice, AMOUNT, BUCKET_ID);

        // Activate rescue mode after creating position
        vm.prank(admin);
        twAlto.setRescueMode(true);

        uint256 aliceBalanceBefore = IERC20(address(alto)).balanceOf(alice);

        // It should emit ExitPosition event
        vm.expectEmit(true, true, true, true);
        emit TWAltoEventsLib.ExitPosition(BUCKET_ID, alice, AMOUNT);

        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, alice, BUCKET_ID);

        // It should return tapAmount
        assertEq(exitAmount, AMOUNT);

        // It should transfer TAP to recipient
        assertEq(IERC20(address(alto)).balanceOf(alice), aliceBalanceBefore + AMOUNT);

        // It should update position state
        Participation memory position = twAlto.getParticipation(alice, BUCKET_ID);
        assertTrue(position.tapReleased);
        assertEq(position.tapAmount, 0);
        assertEq(position.expiry, 0);
    }

    function test_ExitPosition_WithDelegatee()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasExpired
        givenPositionTapReleasedIsFalse
    {
        // Setup: Alice has position and sets Bob as delegatee
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        vm.prank(alice);
        twAlto.setDelegatee(BUCKET_ID, bob);
        skip(EPOCH_DURATION * 2);

        uint256 charlieBalanceBefore = IERC20(address(alto)).balanceOf(address(0x123));

        // Bob (delegatee) exits Alice's position to charlie
        vm.prank(bob);
        uint256 exitAmount = twAlto.exitPosition(alice, address(0x123), BUCKET_ID);

        // It should return tapAmount
        assertEq(exitAmount, AMOUNT);

        // It should transfer TAP to specified recipient (charlie)
        assertEq(IERC20(address(alto)).balanceOf(address(0x123)), charlieBalanceBefore + AMOUNT);
    }

    function test_ExitPosition_TodifferentRecipient()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasExpired
        givenPositionTapReleasedIsFalse
    {
        // Setup: Create position and wait for expiry
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION * 2);

        uint256 bobBalanceBefore = IERC20(address(alto)).balanceOf(bob);

        // Alice exits her position but sends TAP to Bob
        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, bob, BUCKET_ID);

        // It should return tapAmount
        assertEq(exitAmount, AMOUNT);

        // It should transfer TAP to specified recipient (Bob)
        assertEq(IERC20(address(alto)).balanceOf(bob), bobBalanceBefore + AMOUNT);
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
