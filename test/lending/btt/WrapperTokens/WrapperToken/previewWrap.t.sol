// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";

contract PreviewWrapTest is WrapperTokenCommon {
    function test_PreviewWrap_WhenPtAmountIsZero() public view {
        assertEq(wrapper.previewWrap(0), 0);
    }

    function test_PreviewWrap_WhenWrappedAmountRoundsDownToZero() public {
        wrapper.setExchangeRateForTest(2 * _tenPowDecimals());

        assertEq(wrapper.previewWrap(1), 0);
    }

    function test_PreviewWrap_WhenExchangeRateEqualsTenPowDecimals() public view {
        assertEq(wrapper.previewWrap(100 ether), 100 ether);
    }

    function test_PreviewWrap_WhenExchangeRateGreaterThanTenPowDecimals() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        uint256 ptAmount = 4 * _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);

        uint256 previewAmount = wrapper.previewWrap(ptAmount);
        assertEq(previewAmount, _expectedWrappedAmount(ptAmount, exchangeRate));
        assertLt(previewAmount, ptAmount);
    }

    function test_PreviewWrap_WhenExchangeRateLessThanTenPowDecimals() public {
        uint256 exchangeRate = _tenPowDecimals() / 2;
        uint256 ptAmount = _tenPowDecimals();

        wrapper.setExchangeRateForTest(exchangeRate);

        uint256 previewAmount = wrapper.previewWrap(ptAmount);
        assertEq(previewAmount, _expectedWrappedAmount(ptAmount, exchangeRate));
        assertGt(previewAmount, ptAmount);
    }
}
