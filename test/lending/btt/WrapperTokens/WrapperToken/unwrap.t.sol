// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {IWrapperTokenErrors, IWrapperTokenEvents} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract UnwrapTest is WrapperTokenCommon {
    uint256 internal constant PT_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();
        _fundAndApproveUser(PT_AMOUNT);
        vm.prank(user);
        wrapper.wrap(PT_AMOUNT);
    }

    function test_RevertWhen_ContractIsPaused() public {
        _pauseWrapper();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        wrapper.unwrap(1 ether);
    }

    function test_RevertWhen_UserHasInsufficientWrappedBalance() public {
        uint256 wrappedBalance = wrapper.balanceOf(user);
        uint256 excessiveAmount = wrappedBalance + 1;

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, user, wrappedBalance, excessiveAmount
            )
        );
        wrapper.unwrap(excessiveAmount);
        vm.stopPrank();
    }

    function test_RevertWhen_PreviewUnwrapReturnsZeroForZeroWrappedAmount() public {
        assertEq(wrapper.previewUnwrap(0), 0);

        vm.prank(user);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.unwrap(0);
    }

    function test_RevertWhen_PreviewUnwrapReturnsZeroForRoundedDownAmount() public {
        wrapper.setExchangeRateForTest(0);

        assertEq(wrapper.previewUnwrap(1), 0);

        vm.prank(user);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.unwrap(1);
    }

    function test_Unwrap_WhenExchangeRateEqualsTenPowDecimals() public {
        uint256 wrappedAmount = 40 ether;
        uint256 expectedPt = wrapper.previewUnwrap(wrappedAmount);
        assertEq(expectedPt, wrappedAmount);

        uint256 userPtBefore = underlyingPt.balanceOf(user);
        uint256 userWrappedBefore = wrapper.balanceOf(user);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Unwrapped(user, wrappedAmount, expectedPt);
        uint256 ptAmount = wrapper.unwrap(wrappedAmount);

        assertEq(ptAmount, expectedPt);
        assertEq(wrapper.balanceOf(user), userWrappedBefore - wrappedAmount);
        assertEq(underlyingPt.balanceOf(user), userPtBefore + expectedPt);
    }

    function test_Unwrap_WhenExchangeRateGreaterThanTenPowDecimals() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        uint256 wrappedAmount = 1 ether;

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedPt = wrapper.previewUnwrap(wrappedAmount);

        assertEq(expectedPt, _expectedPtAmount(wrappedAmount, exchangeRate));
        assertGt(expectedPt, wrappedAmount);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Unwrapped(user, wrappedAmount, expectedPt);
        uint256 ptAmount = wrapper.unwrap(wrappedAmount);

        assertEq(ptAmount, expectedPt);
    }

    function test_Unwrap_WhenExchangeRateGreaterAndDividesEvenly() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        uint256 wrappedAmount = 5 * _tenPowDecimals() / 10;

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedPt = wrapper.previewUnwrap(wrappedAmount);

        assertEq(expectedPt, 1 ether);
        assertEq(expectedPt, wrappedAmount * exchangeRate / _tenPowDecimals());

        uint256 userPtBefore = underlyingPt.balanceOf(user);
        vm.prank(user);
        uint256 ptAmount = wrapper.unwrap(wrappedAmount);

        assertEq(ptAmount, expectedPt);
        assertEq(underlyingPt.balanceOf(user), userPtBefore + expectedPt);
    }

    function test_Unwrap_WhenExchangeRateLessThanTenPowDecimals() public {
        uint256 exchangeRate = _tenPowDecimals() / 2;
        uint256 wrappedAmount = 10 ether;

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedPt = wrapper.previewUnwrap(wrappedAmount);

        assertEq(expectedPt, 5 ether);
        assertLt(expectedPt, wrappedAmount);

        vm.prank(user);
        uint256 ptAmount = wrapper.unwrap(wrappedAmount);

        assertEq(ptAmount, expectedPt);
    }

    function test_Unwrap_RoundTripDoesNotRecoverOriginalPtAmount() public {
        uint256 exchangeRate = 3 * _tenPowDecimals();
        uint256 ptAmount = 4 * _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);
        _fundAndApproveUser(ptAmount);

        address roundTripUser = makeAddr("roundTripUser");
        _fundUserPt(roundTripUser, ptAmount);
        vm.prank(roundTripUser);
        underlyingPt.approve(address(wrapper), ptAmount);

        vm.startPrank(roundTripUser);
        uint256 expectedWrapped = wrapper.previewWrap(ptAmount);
        wrapper.wrap(ptAmount);
        uint256 ptBeforeUnwrap = underlyingPt.balanceOf(roundTripUser);
        wrapper.unwrap(expectedWrapped);
        uint256 ptAfterUnwrap = underlyingPt.balanceOf(roundTripUser);
        vm.stopPrank();

        assertLt(ptAfterUnwrap - ptBeforeUnwrap, ptAmount);
    }
}
