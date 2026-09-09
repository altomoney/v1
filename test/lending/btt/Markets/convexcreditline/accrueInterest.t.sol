// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketAccrueInterestTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedButRemainPermissionlessWhenFrozen() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        vm.prank(USER);
        market.accrueInterest();

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(USER);
        market.accrueInterest();
    }

    function test_PassesCreditLimitAndCurrentDebtOnlyToIrm() external {
        _openPosition(1_000 ether, 100 ether);
        uint256 depositsBefore = booster.depositCalls();
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();
        _mockAccrual(0, 17);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
        vm.prank(USER);
        market.accrueInterest();

        assertEq(booster.depositCalls(), depositsBefore);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
    }

    function test_ZeroInterestCallsIrmEmitsAndPreservesAllAccounting() external {
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        _mockAccrual(0, 23);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(23, 0, 100 ether, uint128(CREDIT_LIMIT));
        market.accrueInterest();

        _assertUnchanged(beforeState);
    }

    function test_NonzeroInterestUpdatesOnlyDebtAssetsAndClaimableFees() external {
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        _mockAccrual(7 ether, 31);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(31, 7 ether, 107 ether, uint128(CREDIT_LIMIT));
        market.accrueInterest();

        AccountingState memory afterState = _state();
        assertEq(afterState.totalBorrowed.assets, beforeState.totalBorrowed.assets + 7 ether);
        assertEq(afterState.claimableFees, beforeState.claimableFees + 7 ether);
        assertEq(afterState.totalBorrowed.shares, beforeState.totalBorrowed.shares);
        assertEq(afterState.totalSupply.assets, beforeState.totalSupply.assets);
        assertEq(afterState.totalSupply.shares, beforeState.totalSupply.shares);
        assertEq(afterState.creditPosition.borrowShares, beforeState.creditPosition.borrowShares);
        assertEq(afterState.creditPosition.collateralAssets, beforeState.creditPosition.collateralAssets);
    }

    function test_IrmRevertOrMalformedReturnRollsBack() external {
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.accrueInterest();
        _assertUnchanged(beforeState);

        vm.clearMockedCalls();
        bytes memory updateCall = abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 0));
        vm.mockCall(address(irm), updateCall, hex"01");
        vm.expectRevert();
        market.accrueInterest();
        vm.clearMockedCalls();
        _assertUnchanged(beforeState);
    }

    function test_RevertAtomicallyWhenDebtUint128AdditionOverflows() external {
        _openPosition(10, 1);
        AccountingState memory beforeState = _state();
        _mockAccrual(type(uint128).max, 1);

        vm.expectRevert();
        market.accrueInterest();

        _assertUnchanged(beforeState);
    }

    function test_ClaimableUint128OverflowRollsBackEarlierDebtAndIrmUpdates() external {
        vm.store(address(market), bytes32(uint256(52)), bytes32(uint256(type(uint128).max)));
        _mockAccrual(1, 1);
        AccountingState memory beforeState = _state();

        vm.expectRevert();
        market.accrueInterest();

        _assertUnchanged(beforeState);
    }
}
