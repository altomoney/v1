// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";
import {IWrapperTokenErrors, IWrapperTokenEvents} from "@alto/lending/wrappedToken/IWrapperToken.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract WrapTest is WrapperTokenCommon {
    uint256 internal constant PT_AMOUNT = 100 ether;

    function test_RevertWhen_ContractIsPaused() public {
        _fundAndApproveUser(PT_AMOUNT);
        _pauseWrapper();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        wrapper.wrap(PT_AMOUNT);
    }

    function test_RevertWhen_UserHasInsufficientPtBalance() public {
        _fundUserPt(user, PT_AMOUNT - 1);
        _approveWrapper(user, PT_AMOUNT);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, PT_AMOUNT - 1, PT_AMOUNT)
        );
        wrapper.wrap(PT_AMOUNT);
    }

    function test_RevertWhen_UserHasInsufficientPtAllowance() public {
        _fundUserPt(user, PT_AMOUNT);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(wrapper), 0, PT_AMOUNT)
        );
        wrapper.wrap(PT_AMOUNT);
    }

    function test_RevertWhen_PreviewWrapReturnsZeroForZeroPtAmount() public {
        assertEq(wrapper.previewWrap(0), 0);

        vm.prank(user);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.wrap(0);
    }

    function test_RevertWhen_PreviewWrapReturnsZeroForRoundedDownAmount() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        wrapper.setExchangeRateForTest(exchangeRate);
        _fundAndApproveUser(1);

        assertEq(wrapper.previewWrap(1), 0);

        vm.prank(user);
        vm.expectRevert(IWrapperTokenErrors.InvalidInput.selector);
        wrapper.wrap(1);
    }

    function test_Wrap_WhenExchangeRateEqualsTenPowDecimals() public {
        _fundAndApproveUser(PT_AMOUNT);

        uint256 expectedWrapped = wrapper.previewWrap(PT_AMOUNT);
        assertEq(expectedWrapped, PT_AMOUNT);

        uint256 userPtBefore = underlyingPt.balanceOf(user);
        uint256 wrapperPtBefore = underlyingPt.balanceOf(address(wrapper));

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Wrapped(user, PT_AMOUNT, expectedWrapped);
        uint256 wrappedAmount = wrapper.wrap(PT_AMOUNT);

        assertEq(wrappedAmount, expectedWrapped);
        assertEq(underlyingPt.balanceOf(user), userPtBefore - PT_AMOUNT);
        assertEq(underlyingPt.balanceOf(address(wrapper)), wrapperPtBefore + PT_AMOUNT);
        assertEq(wrapper.balanceOf(user), expectedWrapped);
    }

    function test_Wrap_WhenExchangeRateGreaterThanTenPowDecimals() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        uint256 ptAmount = 4 * _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedWrapped = wrapper.previewWrap(ptAmount);
        _fundAndApproveUser(ptAmount);

        assertEq(expectedWrapped, _expectedWrappedAmount(ptAmount, exchangeRate));
        assertLt(expectedWrapped, ptAmount);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IWrapperTokenEvents.Wrapped(user, ptAmount, expectedWrapped);
        uint256 wrappedAmount = wrapper.wrap(ptAmount);

        assertEq(wrappedAmount, expectedWrapped);
        assertEq(wrapper.balanceOf(user), expectedWrapped);
    }

    function test_Wrap_WhenExchangeRateLessThanTenPowDecimals() public {
        uint256 exchangeRate = _tenPowDecimals() / 2;
        uint256 ptAmount = _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedWrapped = wrapper.previewWrap(ptAmount);
        _fundAndApproveUser(ptAmount);

        assertGt(expectedWrapped, ptAmount);

        vm.prank(user);
        uint256 wrappedAmount = wrapper.wrap(ptAmount);

        assertEq(wrappedAmount, expectedWrapped);
        assertEq(wrapper.balanceOf(user), expectedWrapped);
    }

    function test_Wrap_RoundTripDoesNotRecoverOriginalPtAmount() public {
        uint256 exchangeRate = 3 * _tenPowDecimals();
        uint256 ptAmount = 4 * _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);
        uint256 expectedWrapped = wrapper.previewWrap(ptAmount);
        _fundAndApproveUser(ptAmount);

        vm.startPrank(user);
        wrapper.wrap(ptAmount);
        wrapper.unwrap(expectedWrapped);
        vm.stopPrank();

        assertLt(underlyingPt.balanceOf(user), ptAmount);
    }
}
