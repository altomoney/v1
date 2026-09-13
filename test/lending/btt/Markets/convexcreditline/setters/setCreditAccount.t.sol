// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketSetCreditAccountTest is ConvexCreditLineCommon {
    function testFuzz_RevertWhen_CallerIsNotOwner(address caller) external {
        vm.assume(caller != OWNER);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        market.setCreditAccount(USER);
        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
    }

    function test_RevertWhen_NewCreditAccountIsZero() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.setCreditAccount(address(0));
        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
    }

    function testFuzz_RevertWhen_CollateralRemainsWithoutDebt(uint256 assets) external {
        assets = bound(assets, 1, 1_000 ether);
        _addCollateral(assets);
        _expectPositionNotEmpty();
    }

    function test_RevertWhen_DebtAndCollateralRemain() external {
        _openPosition(1_000 ether, 100 ether);
        _expectPositionNotEmpty();
    }

    function test_RevertWhen_DebtRemainsWithoutCollateral() external {
        _openPosition(1_000 ether, 100 ether);
        // Isolate the debt check; `position` is slot 8 in the direct-inheritance layout.
        bytes32 positionBase = keccak256(abi.encode(CREDIT_ACCOUNT, uint256(8)));
        vm.store(address(market), bytes32(uint256(positionBase) + 1), bytes32(0));
        _expectPositionNotEmpty();
    }

    function test_UpdatesEmptyAccountAndEmitsOldAndNewValues() external {
        AccountingState memory beforeState = _state();
        vm.expectEmit(address(market));
        emit SetCreditAccount(CREDIT_ACCOUNT, USER);
        vm.prank(OWNER);
        market.setCreditAccount(USER);

        assertEq(market.creditAccount(), USER);
        assertEq(market.rewardRecipient(), REWARD_RECIPIENT);
        assertTrue(market.isAuthorized(CREDIT_ACCOUNT, DELEGATE));
        assertFalse(market.isAuthorized(USER, DELEGATE));
        _assertUnchanged(beforeState);
    }

    function test_AllowsUnchangedAccountOnlyWhenPositionIsEmpty() external {
        vm.expectEmit(address(market));
        emit SetCreditAccount(CREDIT_ACCOUNT, CREDIT_ACCOUNT);
        vm.prank(OWNER);
        market.setCreditAccount(CREDIT_ACCOUNT);

        _addCollateral(1);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotEmpty.selector);
        market.setCreditAccount(CREDIT_ACCOUNT);
    }

    function test_AllowsRotationAfterFullRepaymentAndCollateralWithdrawal() external {
        _openPosition(1_000 ether, 100 ether);
        _repayAllShares(CREDIT_ACCOUNT);
        _expectPositionNotEmpty();

        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(1_000 ether, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");
        vm.prank(OWNER);
        market.setCreditAccount(USER);

        assertEq(market.creditAccount(), USER);
        (, uint128 shares, uint128 collateral) = market.position(CREDIT_ACCOUNT);
        assertEq(shares, 0);
        assertEq(collateral, 0);
    }

    function test_NewAccountCanUseMarketAndOldAccountAndDelegateLoseAccess() external {
        vm.prank(OWNER);
        market.setCreditAccount(USER);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.setRewardRecipient(CREDIT_ACCOUNT);
        vm.prank(USER);
        market.setRewardRecipient(USER);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.addCollateral(1, CREDIT_ACCOUNT);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        deal(address(collateralToken), USER, 1_000 ether);
        vm.startPrank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(1_000 ether, USER);
        market.borrow(100 ether, 0, USER, USER, "");
        vm.stopPrank();

        vm.prank(DELEGATE);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.borrow(1, 0, USER, DELEGATE, "");
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.removeCollateral(1, USER, CREDIT_ACCOUNT, "");

        vm.startPrank(USER);
        market.repay(100 ether, 0, USER);
        market.removeCollateral(1_000 ether, USER, USER, "");
        vm.stopPrank();
        (, uint128 shares, uint128 collateral) = market.position(USER);
        assertEq(shares, 0);
        assertEq(collateral, 0);
    }

    function test_RotationAfterForeclosurePreservesBadDebtAndUsedCapacity() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        market.setCreditAccount(USER);

        assertEq(market.creditAccount(), USER);
        assertEq(market.badDebtAssets(), 100 ether);
        _assertUnchanged(beforeState);
    }

    function test_RemainsCallableWhilePausedFrozenOrInactive() external {
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.setCreditAccount(USER);
        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.setCreditAccount(RECEIVER);
        _unpause(FROZEN_TYPE);
        _exitConvex();
        vm.prank(OWNER);
        market.setCreditAccount(CREDIT_ACCOUNT);
        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
    }

    function test_RevertWhen_OwnerAttemptsRotationDuringCollateralTransfer() external {
        _addCollateral(1_000 ether);
        vm.prank(OWNER);
        market.transferOwnershipSkip2Step(address(collateralToken));
        collateralToken.setCallback(address(market), abi.encodeCall(market.setCreditAccount, (USER)), 4);
        AccountingState memory beforeState = _state();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.removeCollateral(1_000 ether, CREDIT_ACCOUNT, CREDIT_ACCOUNT, "");

        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function _expectPositionNotEmpty() private {
        AccountingState memory beforeState = _state();
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotEmpty.selector);
        market.setCreditAccount(USER);
        assertEq(market.creditAccount(), CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }
}
