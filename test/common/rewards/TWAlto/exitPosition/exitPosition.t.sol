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

    modifier givenCallerIsNotParticipant() {
        // Setup will be done in test where Bob tries to exit for Alice
        _;
    }

    modifier givenCallerIsAuthorized() {
        // Setup will be done in individual tests
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

    function test_RevertWhen_CallerIsNotParticipant()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsNotParticipant
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

    function test_ExitPosition_TodifferentRecipient()
        public
        givenContractIsNotPaused
        givenNoReentrancy
        givenCallerIsAuthorized
        givenRescueModeIsInactive
        givenPositionLockHasExpired
    {
        // Setup: Create position and wait for expiry
        _participateHelper(alice, AMOUNT, BUCKET_ID);
        skip(EPOCH_DURATION * 2);

        uint256 bobBalanceBefore = IERC20(address(alto)).balanceOf(bob);

        // Alice exits her position but sends TAP to Bob
        vm.prank(alice);
        uint256 exitAmount = twAlto.exitPosition(alice, bob, BUCKET_ID);

        // It should return lockAmount
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
