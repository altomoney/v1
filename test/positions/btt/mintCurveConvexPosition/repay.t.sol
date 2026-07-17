// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {IMintCurveConvexPositionErrors, IMintCurveConvexPositionEvents} from
    "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";

contract MintCurveConvexPosition_Repay_Test is MintCurveConvexPositionCommon {
    function setUp() public override {
        super.setUp();
        _openPosition(DEFAULT_COLLATERAL, DEFAULT_BORROW);
    }

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        uint256 shares = _borrowShares();
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.repay(shares);
    }

    function test_RevertWhen_RepaySharesIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.repay(0);
    }

    function test_RevertWhen_RepaySharesExceedsBorrowShares() public {
        // Fund the position so the DUSD top-up succeeds and the market repay is what underflows.
        borrowToken.mint(address(position), DEFAULT_BORROW * 4);
        uint256 shares = _borrowShares() + 1e18;

        vm.prank(OWNER);
        vm.expectRevert(stdError.arithmeticError);
        position.repay(shares);
    }

    function test_RevertWhen_CannotCoverRequiredDusd() public {
        // Position holds no DUSD and the owner has neither balance nor allowance.
        uint256 shares = _borrowShares();
        vm.prank(OWNER);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        position.repay(shares);
    }

    function test_Repay_WhenPositionHoldsEnoughDusd() public {
        borrowToken.mint(address(position), DEFAULT_BORROW * 2);
        uint256 shares = _borrowShares();
        uint256 ownerBalanceBefore = borrowToken.balanceOf(OWNER);

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(OWNER, shares, 0);
        vm.prank(OWNER);
        position.repay(shares);

        assertEq(_borrowShares(), 0, "debt cleared");
        assertEq(borrowToken.balanceOf(OWNER), ownerBalanceBefore, "owner funds untouched");
    }

    function test_Repay_WhenPositionHoldsInsufficientDusd() public {
        _fundOwnerDusd(DEFAULT_BORROW * 2);
        uint256 shares = _borrowShares();
        uint256 ownerBalanceBefore = borrowToken.balanceOf(OWNER);

        vm.prank(OWNER);
        position.repay(shares);

        assertEq(_borrowShares(), 0, "debt cleared");
        assertLt(borrowToken.balanceOf(OWNER), ownerBalanceBefore, "shortfall pulled from owner");
    }

    function test_Repay_AccruesInterestBeforeComputing() public {
        _fundOwnerDusd(DEFAULT_BORROW * 2);
        uint256 shares = _borrowShares();

        // Let a year of fixed-rate interest accrue on the debt.
        vm.warp(block.timestamp + 365 days);

        vm.recordLogs();
        vm.prank(OWNER);
        position.repay(shares);

        uint256 assetsRepaid;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.Repaid.selector) {
                (, assetsRepaid) = abi.decode(logs[i].data, (uint256, uint256));
            }
        }

        assertGt(assetsRepaid, DEFAULT_BORROW, "interest accrued into repaid assets");
    }

    function test_Repay_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);
        // The DUSD shortfall is pulled from the caller (the authorized spender).
        _fundDusd(AUTHORIZED_SPENDER, DEFAULT_BORROW * 2);
        uint256 shares = _borrowShares();
        uint256 spenderBalanceBefore = borrowToken.balanceOf(AUTHORIZED_SPENDER);
        uint256 ownerBalanceBefore = borrowToken.balanceOf(OWNER);

        vm.prank(AUTHORIZED_SPENDER);
        position.repay(shares);

        assertEq(_borrowShares(), 0, "debt cleared");
        assertLt(borrowToken.balanceOf(AUTHORIZED_SPENDER), spenderBalanceBefore, "shortfall pulled from caller");
        assertEq(borrowToken.balanceOf(OWNER), ownerBalanceBefore, "owner funds untouched");
    }
}
