// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniversalRewardsDistributor} from "@alto/utils/UniversalRewardsDistributor.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";

contract UniversalRewardsDistributorRescueRewardTokens is Test {
    UniversalRewardsDistributor public distributor;
    ERC20MockDecimals public rewardToken;
    ERC20MockDecimals public rewardToken2;

    address public OWNER = address(0x1);
    address public NON_OWNER = address(0x2);
    address public PAUSER = address(0x3);

    uint256 public constant INITIAL_TIMELOCK = 1 days;
    uint256 public constant TOKEN_AMOUNT = 1000 ether;

    function setUp() public {
        // Deploy tokens
        rewardToken = new ERC20MockDecimals("Reward Token", "RWD", 18);
        rewardToken2 = new ERC20MockDecimals("Reward Token 2", "RWD2", 6);

        // Deploy distributor
        distributor = new UniversalRewardsDistributor(OWNER, INITIAL_TIMELOCK);

        // Setup pauser
        vm.prank(OWNER);
        distributor.setPauser(PAUSER, PAUSE_TYPE, true);

        // Fund distributor with tokens
        deal(address(rewardToken), address(distributor), TOKEN_AMOUNT);
        deal(address(rewardToken2), address(distributor), TOKEN_AMOUNT * 10 ** 6 / 10 ** 18); // Adjust for 6 decimals
    }

    function test_RevertWhen_CallerIsNotOwner() external {
        // Pause the contract first
        vm.prank(PAUSER);
        distributor.pause(PAUSE_TYPE, true);

        vm.prank(NON_OWNER);
        // it should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        distributor.rescueRewardTokens(address(rewardToken));
    }

    function test_RevertWhen_ContractIsNotPaused() external {
        // Ensure contract is not paused
        assertFalse(distributor.paused(PAUSE_TYPE));

        vm.prank(OWNER);
        // it should revert with RewardsDistributorNotPaused
        vm.expectRevert(IUniversalRewardsDistributor.RewardsDistributorNotPaused.selector);
        distributor.rescueRewardTokens(address(rewardToken));
    }

    modifier whenCallerIsOwnerAndContractIsPaused() {
        // Pause the contract
        vm.prank(PAUSER);
        distributor.pause(PAUSE_TYPE, true);
        _;
    }

    function test_WhenNoBalance() external whenCallerIsOwnerAndContractIsPaused {
        // Redeploy distributor but don't fund it
        distributor = new UniversalRewardsDistributor(OWNER, INITIAL_TIMELOCK);
        assertEq(rewardToken.balanceOf(address(distributor)), 0);

        vm.prank(OWNER);
        distributor.setPauser(PAUSER, PAUSE_TYPE, true);

        vm.prank(PAUSER);
        distributor.pause(PAUSE_TYPE, true);

        vm.prank(OWNER);
        vm.recordLogs();
        distributor.rescueRewardTokens(address(rewardToken));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // it should not emit any events
        assertEq(entries.length, 0);

        // it should transfer nothing to owner
        assertEq(rewardToken.balanceOf(OWNER), 0);
        assertEq(rewardToken.balanceOf(address(distributor)), 0);
    }

    function test_WhenBalance() external whenCallerIsOwnerAndContractIsPaused {
        uint256 rescueAmount = rewardToken.balanceOf(address(distributor));
        uint256 initialOwnerBalance = rewardToken.balanceOf(OWNER);

        // it should emit RescueRewardTokens event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IUniversalRewardsDistributor.RescueRewardTokens(address(rewardToken), OWNER, rescueAmount);

        vm.prank(OWNER);
        distributor.rescueRewardTokens(address(rewardToken));

        // it should transfer all of the tokens to owner
        assertEq(rewardToken.balanceOf(OWNER), initialOwnerBalance + rescueAmount);
        assertEq(rewardToken.balanceOf(address(distributor)), 0);
    }

    function test_RescueWithDifferentToken() external whenCallerIsOwnerAndContractIsPaused {
        uint256 rescueAmount = rewardToken2.balanceOf(address(distributor));
        uint256 initialOwnerBalance = rewardToken2.balanceOf(OWNER);

        vm.expectEmit(true, true, true, true);
        emit IUniversalRewardsDistributor.RescueRewardTokens(address(rewardToken2), OWNER, rescueAmount);

        vm.prank(OWNER);
        distributor.rescueRewardTokens(address(rewardToken2));

        assertEq(rewardToken2.balanceOf(OWNER), initialOwnerBalance + rescueAmount);
        assertEq(rewardToken2.balanceOf(address(distributor)), 0);
    }
}
