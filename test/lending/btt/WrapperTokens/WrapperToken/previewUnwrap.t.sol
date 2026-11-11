// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {WrapperTokenCommon} from "./WrapperTokenCommon.t.sol";

contract PreviewUnwrapTest is WrapperTokenCommon {
    function test_PreviewUnwrap_WhenWrappedTokenAmountIsZero() public view {
        assertEq(wrapper.previewUnwrap(0), 0);
    }

    function test_PreviewUnwrap_WhenPtAmountRoundsDownToZero() public {
        wrapper.setExchangeRateForTest(0);

        assertEq(wrapper.previewUnwrap(1), 0);
    }

    function test_PreviewUnwrap_WhenExchangeRateEqualsTenPowDecimals() public view {
        assertEq(wrapper.previewUnwrap(100 ether), 100 ether);
    }

    function test_PreviewUnwrap_WhenExchangeRateGreaterThanTenPowDecimals() public {
        uint256 exchangeRate = 2 * _tenPowDecimals();
        uint256 wrappedAmount = 1 ether;

        wrapper.setExchangeRateForTest(exchangeRate);

        uint256 previewAmount = wrapper.previewUnwrap(wrappedAmount);
        assertEq(previewAmount, _expectedPtAmount(wrappedAmount, exchangeRate));
        assertGt(previewAmount, wrappedAmount);
    }

    function test_PreviewUnwrap_WhenExchangeRateLessThanTenPowDecimals() public {
        uint256 exchangeRate = _tenPowDecimals() / 2;
        uint256 wrappedAmount = 10 ether;

        wrapper.setExchangeRateForTest(exchangeRate);

        uint256 previewAmount = wrapper.previewUnwrap(wrappedAmount);
        assertEq(previewAmount, _expectedPtAmount(wrappedAmount, exchangeRate));
        assertLt(previewAmount, wrappedAmount);
    }
}
