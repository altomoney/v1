// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IAltoConvexCreditLineMarketErrors} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "../ConvexCreditLineCommon.t.sol";
import {CreditLineCallForwarderMock} from "../mocks/CreditLineCallForwarderMock.sol";

contract AltoConvexCreditLineMarketSetIrmTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.setIrm(USER, false);
    }

    function test_RevertForZeroCurrentAndNonFixedBeforeAccrual() external {
        FixedRateIrm adaptive = _newFixedRateIrm();
        vm.mockCall(address(adaptive), abi.encodeCall(IIrm.IRM_TYPE, ()), abi.encode(IRMType.ADAPTIVE_CURVE));
        _mockIrmUpdateRevert();

        vm.startPrank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.setIrm(address(0), false);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setIrm(address(irm), false);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.setIrm(address(adaptive), false);
        vm.stopPrank();

        assertEq(market.irm(), address(irm));
    }

    function test_PropagatesMalformedOrRevertingTypeQuery() external {
        FixedRateIrm candidate = _newFixedRateIrm();
        bytes memory query = abi.encodeCall(IIrm.IRM_TYPE, ());
        vm.mockCallRevert(address(candidate), query, "TYPE_REVERTED");
        vm.prank(OWNER);
        vm.expectRevert(bytes("TYPE_REVERTED"));
        market.setIrm(address(candidate), true);
        vm.clearMockedCalls();

        vm.mockCall(address(candidate), query, hex"01");
        vm.prank(OWNER);
        vm.expectRevert();
        market.setIrm(address(candidate), true);
        vm.clearMockedCalls();
        assertEq(market.irm(), address(irm));
    }

    function test_AccruesWithOldIrmBeforeRegisteringNewIrm() external {
        _openPosition(1_000 ether, 100 ether);
        _mockAccrual(5 ether, 77);
        FixedRateIrm candidate = _newFixedRateIrm();

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(77, 5 ether, 105 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IMarketEvents.SetIrm(address(irm), address(candidate));
        vm.prank(OWNER);
        market.setIrm(address(candidate), false);

        assertEq(market.irm(), address(candidate));
        assertEq(candidate.market(), address(market));
        assertEq(market.claimableFeesAssets(), 5 ether);
    }

    function test_SkipFlagAndPausedStateSkipOldAccrual() external {
        FixedRateIrm first = _newFixedRateIrm();
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        market.setIrm(address(first), true);

        _pause(PAUSE_TYPE);
        FixedRateIrm second = _newFixedRateIrm();
        vm.mockCallRevert(
            address(first), abi.encodeWithSelector(IIrm.updateInterestRate.selector), bytes("UPDATE_REVERTED")
        );
        vm.prank(OWNER);
        market.setIrm(address(second), false);
        assertEq(market.irm(), address(second));
    }

    function test_FrozenDoesNotSkipAccrual() external {
        _pause(FROZEN_TYPE);
        _mockAccrual(0, 91);
        FixedRateIrm candidate = _newFixedRateIrm();
        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 0)));
        vm.prank(OWNER);
        market.setIrm(address(candidate), false);
    }

    function test_SkipFlagSkipsAccrualWhilePausedAndFrozen() external {
        _pause(PAUSE_TYPE);
        FixedRateIrm first = _newFixedRateIrm();
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        market.setIrm(address(first), true);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        FixedRateIrm second = _newFixedRateIrm();
        vm.mockCallRevert(
            address(first), abi.encodeWithSelector(IIrm.updateInterestRate.selector), bytes("UPDATE_REVERTED")
        );
        vm.prank(OWNER);
        market.setIrm(address(second), true);
    }

    function test_RollsBackWhenOldAccrualOrNewRegistrationFails() external {
        FixedRateIrm candidate = _newFixedRateIrm();
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.setIrm(address(candidate), false);
        assertEq(market.irm(), address(irm));
        _assertUnchanged(beforeState);

        vm.clearMockedCalls();
        _mockAccrual(1, 2);
        vm.mockCallRevert(
            address(candidate), abi.encodeWithSelector(IIrm.setMarket.selector), bytes("SET_MARKET_REVERTED")
        );
        vm.prank(OWNER);
        vm.expectRevert(bytes("SET_MARKET_REVERTED"));
        market.setIrm(address(candidate), false);
        assertEq(market.irm(), address(irm));
        _assertUnchanged(beforeState);
    }

    function test_RejectsReentrancyAndRollsBack() external {
        FixedRateIrm candidate = _newFixedRateIrm();
        CreditLineCallForwarderMock callback = new CreditLineCallForwarderMock(address(market), CREDIT_ACCOUNT);
        vm.mockFunction(address(irm), address(callback), abi.encodeWithSelector(IIrm.updateInterestRate.selector));
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.setIrm(address(candidate), false);

        assertEq(market.irm(), address(irm));
        _assertUnchanged(beforeState);
    }
}
