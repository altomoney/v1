// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsDistributorSetLockContract is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        address newLockContract = address(0x999);

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.setLockContract(newLockContract);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenNewLockContractIsZeroAddress() external whenCallerIsOwner {
        address oldLockContract = distributor.lockContract();
        assertNotEq(oldLockContract, address(0)); // Should have a lock contract set in setup

        // it should emit SetLockContract event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(address(0));

        vm.prank(OWNER);
        distributor.setLockContract(address(0));

        // it should set lock contract to zero
        assertEq(distributor.lockContract(), address(0));
        assertNotEq(distributor.lockContract(), oldLockContract);
    }

    function test_WhenNewLockContractIsNotZeroAddress() external whenCallerIsOwner {
        address newLockContract = address(0x999);
        address oldLockContract = distributor.lockContract();

        // it should emit SetLockContract event
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(newLockContract);

        vm.prank(OWNER);
        distributor.setLockContract(newLockContract);

        // it should update lock contract
        assertEq(distributor.lockContract(), newLockContract);
        assertNotEq(distributor.lockContract(), oldLockContract);
    }

    function test_WhenUpdatingLockContractMultipleTimes() external whenCallerIsOwner {
        address lockContract1 = address(0x888);
        address lockContract2 = address(0x777);

        // Set first lock contract
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(lockContract1);

        vm.prank(OWNER);
        distributor.setLockContract(lockContract1);

        assertEq(distributor.lockContract(), lockContract1);

        // Set second lock contract
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(lockContract2);

        vm.prank(OWNER);
        distributor.setLockContract(lockContract2);

        assertEq(distributor.lockContract(), lockContract2);
        assertNotEq(distributor.lockContract(), lockContract1);
    }

    function test_WhenSettingBackToZeroAfterNonZero() external whenCallerIsOwner {
        address newLockContract = address(0x666);

        // First set to non-zero
        vm.prank(OWNER);
        distributor.setLockContract(newLockContract);
        assertEq(distributor.lockContract(), newLockContract);

        // Then set back to zero
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(address(0));

        vm.prank(OWNER);
        distributor.setLockContract(address(0));

        assertEq(distributor.lockContract(), address(0));
    }

    function test_WhenSettingSameLockContractAgain() external whenCallerIsOwner {
        address currentLockContract = distributor.lockContract();

        // Setting the same contract again should still work
        vm.expectEmit(true, false, false, false);
        emit IRewardsEvents.SetLockContract(currentLockContract);

        vm.prank(OWNER);
        distributor.setLockContract(currentLockContract);

        assertEq(distributor.lockContract(), currentLockContract);
    }
}
