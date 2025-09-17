// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";

contract AltoRewardsDistributorConstructor is Test {
    address owner = address(0x1);
    uint256 merkleRootTimelock = 1 days;

    function testRoot() public {}

    function test_RevertWhen_RewardTokenAddressIsZeroAddress() public {
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        new AltoRewardsDistributor(owner, merkleRootTimelock, address(0));
    }

    function test_WhenRewardTokenAddressIsValid() public {
        ERC20MockDecimals rewardToken = new ERC20MockDecimals("Reward", "RWD", 18);

        AltoRewardsDistributor distributor = new AltoRewardsDistributor(owner, merkleRootTimelock, address(rewardToken));

        // Verify the reward token is set correctly
        (address tokenAddress, uint8 decimals) = distributor.REWARD_TOKEN();
        assertEq(tokenAddress, address(rewardToken));
        assertEq(decimals, 18);

        // Verify owner is set
        assertEq(distributor.owner(), owner);

        // Verify timelock is set
        assertEq(distributor.merkleRootTimelock(), merkleRootTimelock);
    }

    function test_WhenMerkleRootTimelockIsSet() public {
        ERC20MockDecimals rewardToken = new ERC20MockDecimals("Reward", "RWD", 18);
        uint256 customTimelock = 2 days;

        AltoRewardsDistributor distributor = new AltoRewardsDistributor(owner, customTimelock, address(rewardToken));

        assertEq(distributor.merkleRootTimelock(), customTimelock);
    }
}
