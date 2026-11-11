// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetTreasuryInterestBpsTest is ConvexCreditLineCommon {
    function test_CreditAccountDelegateAndRecipientsCannotChangeShare() external {
        address[4] memory callers = [CREDIT_ACCOUNT, DELEGATE, FEE_RECIPIENT, REWARD_RECIPIENT];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, callers[i]));
            market.setTreasuryInterestBps(5_000);
            assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
        }
    }

    function test_RevertWhenCallerIsNotOwner() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        market.setTreasuryInterestBps(5_000);
        assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
    }

    function test_RevertAboveMaximumWithoutChangingShare() external {
        uint256[2] memory invalidShares = [market.PERCENTAGE_PRECISION() + 1, type(uint256).max];
        for (uint256 i; i < invalidShares.length; ++i) {
            vm.prank(OWNER);
            vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
            market.setTreasuryInterestBps(invalidShares[i]);
            assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
        }
    }

    function test_SetsValidShareAndEmitsOldAndNewValues() external {
        uint256 bps = 5_000;
        vm.expectEmit(address(market));
        emit SetTreasuryInterestBps(TREASURY_INTEREST_BPS, bps);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(bps);
        assertEq(market.treasuryInterestBps(), bps);
    }

    function test_AcceptsZeroAndFullTreasuryShares() external {
        vm.startPrank(OWNER);
        market.setTreasuryInterestBps(0);
        assertEq(market.treasuryInterestBps(), 0);
        market.setTreasuryInterestBps(10_000);
        assertEq(market.treasuryInterestBps(), 10_000);
        vm.stopPrank();
    }

    function test_EmitsEvenWhenShareIsUnchanged() external {
        vm.expectEmit(address(market));
        emit SetTreasuryInterestBps(TREASURY_INTEREST_BPS, TREASURY_INTEREST_BPS);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(TREASURY_INTEREST_BPS);
        assertEq(market.treasuryInterestBps(), TREASURY_INTEREST_BPS);
    }

    function test_DoesNotAccrueOrClaimAndAppliesNewShareToOutstandingFees() external {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        _mockIrmUpdateRevert();
        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, "MUST_NOT_MINT");

        vm.prank(OWNER);
        market.setTreasuryInterestBps(5_000);

        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
        vm.clearMockedCalls();

        assertEq(market.claimInterest(0), 10 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 5 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 5 ether);
    }

    function test_RemainsCallableWhilePausedOrFrozen() external {
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(5_000);
        assertEq(market.treasuryInterestBps(), 5_000);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(7_000);
        assertEq(market.treasuryInterestBps(), 7_000);
    }
}
