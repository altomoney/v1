// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoVestingSetPauser is Test {
    AltoVesting public vesting;
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("owner");
    address public NON_OWNER = makeAddr("non-owner");
    address public PAUSER = makeAddr("pauser");
    address public ZERO_ADDRESS = address(0);

    uint256 public constant INITIAL_TIMELOCK = 3 days;
    bytes32 public constant TEST_MERKLE_ROOT = bytes32(uint256(123));
    bytes32 public constant PAUSE_TYPE = keccak256("PAUSE");
    bytes32 public constant ZERO_PAUSE_TYPE = bytes32(0);

    // Modifiers for BTT structure
    modifier givenCallerIsNotOwner() {
        vm.startPrank(NON_OWNER);
        _;
        vm.stopPrank();
    }

    modifier givenCallerIsOwner() {
        vm.startPrank(OWNER);
        _;
        vm.stopPrank();
    }

    modifier whenPauserIsZeroAddress() {
        PAUSER = ZERO_ADDRESS;
        _;
    }

    modifier whenPauserIsNonZeroAddress() {
        // PAUSER is already set to non-zero address
        _;
    }

    modifier whenPauseTypeIsZero() {
        _;
    }

    modifier whenPauseTypeIsNonZero() {
        _;
    }

    modifier whenStatusIsFalse() {
        _;
    }

    modifier whenStatusIsTrue() {
        _;
    }

    modifier whenPauserAlreadyHasStatus() {
        // First set the pauser to true
        vesting.setPauser(PAUSER, PAUSE_TYPE, true);
        _;
    }

    modifier whenChangingFromTrueToFalse() {
        // Pauser already has true status from previous modifier
        _;
    }

    modifier whenChangingFromFalseToTrue() {
        // Pauser already has true status, first set to false
        vesting.setPauser(PAUSER, PAUSE_TYPE, false);
        _;
    }

    function setUp() public {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");

        vesting = new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), TEST_MERKLE_ROOT, bytes32(0));

        vm.startPrank(OWNER);
        vesting.acceptPendingRoot(TEST_MERKLE_ROOT);
        vm.stopPrank();
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vesting.setPauser(PAUSER, PAUSE_TYPE, true);
    }

    function test_WhenCallerIsOwner_WhenPauserIsZeroAddress() external givenCallerIsOwner whenPauserIsZeroAddress {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(ZERO_ADDRESS, PAUSE_TYPE, true);

        vesting.setPauser(ZERO_ADDRESS, PAUSE_TYPE, true);

        assertTrue(vesting.pausers(ZERO_ADDRESS, PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserIsNonZeroAddress_WhenPauseTypeIsZero_WhenStatusIsFalse()
        external
        givenCallerIsOwner
        whenPauserIsNonZeroAddress
        whenPauseTypeIsZero
        whenStatusIsFalse
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, ZERO_PAUSE_TYPE, false);

        vesting.setPauser(PAUSER, ZERO_PAUSE_TYPE, false);

        assertFalse(vesting.pausers(PAUSER, ZERO_PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserIsNonZeroAddress_WhenPauseTypeIsZero_WhenStatusIsTrue()
        external
        givenCallerIsOwner
        whenPauserIsNonZeroAddress
        whenPauseTypeIsZero
        whenStatusIsTrue
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, ZERO_PAUSE_TYPE, true);

        vesting.setPauser(PAUSER, ZERO_PAUSE_TYPE, true);

        assertTrue(vesting.pausers(PAUSER, ZERO_PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserIsNonZeroAddress_WhenPauseTypeIsNonZero_WhenStatusIsFalse()
        external
        givenCallerIsOwner
        whenPauserIsNonZeroAddress
        whenPauseTypeIsNonZero
        whenStatusIsFalse
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, false);

        vesting.setPauser(PAUSER, PAUSE_TYPE, false);

        assertFalse(vesting.pausers(PAUSER, PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserIsNonZeroAddress_WhenPauseTypeIsNonZero_WhenStatusIsTrue()
        external
        givenCallerIsOwner
        whenPauserIsNonZeroAddress
        whenPauseTypeIsNonZero
        whenStatusIsTrue
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);

        vesting.setPauser(PAUSER, PAUSE_TYPE, true);

        assertTrue(vesting.pausers(PAUSER, PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserAlreadyHasStatus_WhenChangingFromTrueToFalse()
        external
        givenCallerIsOwner
        whenPauserAlreadyHasStatus
        whenChangingFromTrueToFalse
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, false);

        vesting.setPauser(PAUSER, PAUSE_TYPE, false);

        assertFalse(vesting.pausers(PAUSER, PAUSE_TYPE));
    }

    function test_WhenCallerIsOwner_WhenPauserAlreadyHasStatus_WhenChangingFromFalseToTrue()
        external
        givenCallerIsOwner
        whenPauserAlreadyHasStatus
        whenChangingFromFalseToTrue
    {
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);

        vesting.setPauser(PAUSER, PAUSE_TYPE, true);

        assertTrue(vesting.pausers(PAUSER, PAUSE_TYPE));
    }
}
