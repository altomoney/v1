// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoVesting} from "@alto/vesting/AltoVesting.sol";
import {IAltoVesting} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

contract AltoVestingRescueVestingTokens is Test {
    AltoVesting public vesting;
    ERC20MockMintable public vestingToken;

    address public OWNER = makeAddr("owner");
    address public PAUSER = makeAddr("pauser");
    address public NON_OWNER = makeAddr("non-owner");

    uint256 public constant INITIAL_TIMELOCK = 3 days;
    bytes32 public constant TEST_MERKLE_ROOT = bytes32(uint256(123));

    // Modifiers for BTT structure
    modifier givenContractIsNotPaused() {
        _;
    }

    modifier givenContractIsPaused() {
        vm.prank(PAUSER);
        vesting.pause(PAUSE_TYPE, true);
        _;
    }

    modifier givenContractHasZeroTokenBalance() {
        // Contract has zero balance by default
        _;
    }

    modifier givenContractHasNonZeroTokenBalance() {
        vestingToken.mint(address(vesting), 1000 ether);
        _;
    }

    function setUp() public {
        vestingToken = new ERC20MockMintable("Alto Token", "ALTO");

        vesting = new AltoVesting(OWNER, INITIAL_TIMELOCK, true, address(vestingToken), TEST_MERKLE_ROOT, bytes32(0));

        vm.startPrank(OWNER);
        vesting.setPauser(PAUSER, PAUSE_TYPE, true);
        vesting.acceptPendingRoot(TEST_MERKLE_ROOT);
        vm.stopPrank();
    }

    function test_RevertWhen_ContractIsNotPaused() external givenContractIsNotPaused {
        vm.prank(OWNER);
        vm.expectRevert(IAltoVesting.AltoVestingNotPaused.selector);
        vesting.rescueVestingTokens();
    }

    function test_WhenContractIsPaused_GivenContractHasZeroTokenBalance()
        external
        givenContractIsPaused
        givenContractHasZeroTokenBalance
    {
        uint256 contractBalanceBefore = vestingToken.balanceOf(address(vesting));

        vm.recordLogs();

        vm.prank(OWNER);
        vesting.rescueVestingTokens();

        // doesn't emit any events
        assertEq(vm.getRecordedLogs().length, 0);

        // it should not transfer any tokens
        assertEq(vestingToken.balanceOf(address(vesting)), contractBalanceBefore);
    }

    function test_WhenContractIsPaused_GivenContractHasNonZeroTokenBalance()
        external
        givenContractIsPaused
        givenContractHasNonZeroTokenBalance
    {
        uint256 rescueAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit IAltoVesting.RescueVestingTokens(address(vestingToken), OWNER, rescueAmount);

        vm.prank(OWNER);
        vesting.rescueVestingTokens();

        // it should transfer all tokens to owner
        assertEq(vestingToken.balanceOf(OWNER), rescueAmount);
        assertEq(vestingToken.balanceOf(address(vesting)), 0);
    }

    function test_RevertWhen_CallerIsNotOwner_GivenContractIsPaused() external givenContractIsPaused {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vesting.rescueVestingTokens();
    }

    function test_RevertWhen_CallerIsNotOwner_GivenContractIsNotPaused() external givenContractIsNotPaused {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        vesting.rescueVestingTokens();
    }
}
