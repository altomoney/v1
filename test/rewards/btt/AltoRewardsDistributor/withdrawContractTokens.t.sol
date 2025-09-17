// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {IRewardsEvents} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoRewardsDistributorWithdrawContractTokens is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        distributor.withdrawContractTokens(address(paymentToken), 100 ether);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_ContractHasNoTokensToWithdraw() external whenCallerIsOwner {
        ERC20MockDecimals emptyToken = new ERC20MockDecimals("Empty Token", "EMPTY", 18);

        vm.prank(OWNER);
        // it should revert (from SafeERC20 - insufficient balance)
        vm.expectRevert();
        distributor.withdrawContractTokens(address(emptyToken), 100 ether);
    }

    function test_WhenContractHasTokensToWithdraw() external whenCallerIsOwner {
        // First, get some payment tokens into the contract by making a purchase
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 purchaseAmount = aliceAvailable / 2;
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, purchaseAmount, BASE_DISCOUNT, address(paymentToken), false, 0, ALICE
        );
        vm.stopPrank();

        uint256 contractBalance = paymentToken.balanceOf(address(distributor));
        uint256 ownerBalanceBefore = paymentToken.balanceOf(OWNER);

        assertGt(contractBalance, 0, "Contract should have tokens");

        // it should emit WithdrawContractTokens event
        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.WithdrawContractTokens(address(paymentToken), OWNER, contractBalance);

        vm.prank(OWNER);
        distributor.withdrawContractTokens(address(paymentToken), contractBalance);

        // it should transfer tokens to msg.sender (owner)
        assertEq(paymentToken.balanceOf(OWNER), ownerBalanceBefore + contractBalance);
        assertEq(paymentToken.balanceOf(address(distributor)), 0);
    }

    function test_WhenWithdrawingRewardTokens() external whenCallerIsOwner {
        uint256 contractBalance = rewardToken.balanceOf(address(distributor));
        uint256 ownerBalanceBefore = rewardToken.balanceOf(OWNER);

        assertGt(contractBalance, 0, "Contract should have reward tokens");

        uint256 withdrawAmount = contractBalance / 2;

        // it should emit WithdrawContractTokens event
        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.WithdrawContractTokens(address(rewardToken), OWNER, withdrawAmount);

        vm.prank(OWNER);
        distributor.withdrawContractTokens(address(rewardToken), withdrawAmount);

        // it should transfer tokens to msg.sender (owner)
        assertEq(rewardToken.balanceOf(OWNER), ownerBalanceBefore + withdrawAmount);
        assertEq(rewardToken.balanceOf(address(distributor)), contractBalance - withdrawAmount);
    }

    function test_WhenWithdrawingPartialAmount() external whenCallerIsOwner {
        // Add some payment tokens to contract first
        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable / 4, BASE_DISCOUNT, address(paymentToken), false, 0, ALICE
        );
        vm.stopPrank();

        uint256 contractBalance = paymentToken.balanceOf(address(distributor));
        uint256 partialAmount = contractBalance / 3;
        uint256 ownerBalanceBefore = paymentToken.balanceOf(OWNER);

        // it should emit WithdrawContractTokens event
        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.WithdrawContractTokens(address(paymentToken), OWNER, partialAmount);

        vm.prank(OWNER);
        distributor.withdrawContractTokens(address(paymentToken), partialAmount);

        // it should transfer partial tokens to msg.sender (owner)
        assertEq(paymentToken.balanceOf(OWNER), ownerBalanceBefore + partialAmount);
        assertEq(paymentToken.balanceOf(address(distributor)), contractBalance - partialAmount);
    }

    function test_WhenWithdrawingDifferentTokenTypes() external whenCallerIsOwner {
        // Test withdrawing different payment tokens
        vm.startPrank(ALICE);
        paymentToken2.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable / 3, BASE_DISCOUNT, address(paymentToken2), false, 0, ALICE
        );
        vm.stopPrank();

        uint256 contractBalance = paymentToken2.balanceOf(address(distributor));
        uint256 ownerBalanceBefore = paymentToken2.balanceOf(OWNER);

        // it should emit WithdrawContractTokens event
        vm.expectEmit(true, true, false, true);
        emit IRewardsEvents.WithdrawContractTokens(address(paymentToken2), OWNER, contractBalance);

        vm.prank(OWNER);
        distributor.withdrawContractTokens(address(paymentToken2), contractBalance);

        // it should transfer tokens to msg.sender (owner)
        assertEq(paymentToken2.balanceOf(OWNER), ownerBalanceBefore + contractBalance);
        assertEq(paymentToken2.balanceOf(address(distributor)), 0);
    }
}
