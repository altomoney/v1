// SPDX-License-Identifier: GPL-3.0-or-later
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
        assertEq(market.feeRecipient(), RECEIVER);

        vm.expectEmit(address(market));
        emit IMarketEvents.SetFeeRecipient(RECEIVER, RECEIVER);
        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);
        assertEq(market.feeRecipient(), RECEIVER);
    }

    function test_RedirectsExistingFeesWhenFormerRecipientClaims() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        uint256 fees = market.claimableFeesAssets();
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        _mockIrmUpdateRevert();
        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, "MUST_NOT_MINT");

        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);
        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        vm.clearMockedCalls();

        vm.prank(FEE_RECIPIENT);
        uint256 claimed = market.claimInterest(0);

        assertEq(claimed, fees);
        assertEq(borrowToken.balanceOf(RECEIVER), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_RemainsCallableWhilePausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setFeeRecipient(RECEIVER);
        assertEq(market.feeRecipient(), RECEIVER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setFeeRecipient(USER);
        assertEq(market.feeRecipient(), USER);
    }
}
