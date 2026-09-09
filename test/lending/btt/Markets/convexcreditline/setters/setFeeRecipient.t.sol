// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetFeeRecipientTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setFeeRecipient(USER);
    }

    function test_RevertForZeroRecipient() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.setFeeRecipient(address(0));
        assertEq(market.feeRecipient(), FEE_RECIPIENT);
    }

    function test_UpdatesRecipientAndEmitsEvenWhenUnchanged() external {
        _mockIrmUpdateRevert();
        vm.expectEmit(address(market));
        emit IMarketEvents.SetFeeRecipient(FEE_RECIPIENT, RECEIVER);
        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);

        vm.expectEmit(address(market));
        emit IMarketEvents.SetFeeRecipient(RECEIVER, RECEIVER);
        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);
        assertEq(market.feeRecipient(), RECEIVER);
    }

    function test_RedirectsExistingFeesAndRemovesOldClaimPermission() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        uint256 fees = market.claimableFeesAssets();

        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);

        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.claimInterest(0);

        vm.prank(RECEIVER);
        market.claimInterest(0);
        assertEq(borrowToken.balanceOf(RECEIVER), fees);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_RemainsCallableWhilePausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setFeeRecipient(USER);
        assertEq(market.feeRecipient(), USER);
    }
}
