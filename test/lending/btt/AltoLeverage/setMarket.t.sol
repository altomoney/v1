// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoLeverageBTTTest} from "./AltoLeverage.t.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";

contract SetMarketTest is AltoLeverageBTTTest {
    /// @dev it should revert
    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.expectRevert();
        leverage.setMarket(address(market), true);
    }

    /// @dev it should set market as supported and emit event
    function test_SetMarketAsSupportedAndEmitEvent_WhenMarketIsZeroAddressAndIsSupportedIsTrue()
        external
        givenCallerIsOwner
    {
        vm.expectEmit(true, false, false, true);
        emit AltoLeverage.MarketUpdated(address(0), true);

        leverage.setMarket(address(0), true);

        assertTrue(leverage.supportedMarkets(address(0)));
    }

    /// @dev it should set market as unsupported and emit event
    function test_SetMarketAsUnsupportedAndEmitEvent_WhenMarketIsZeroAddressAndIsSupportedIsFalse()
        external
        givenCallerIsOwner
    {
        vm.expectEmit(true, false, false, true);
        emit AltoLeverage.MarketUpdated(address(0), false);

        leverage.setMarket(address(0), false);

        assertFalse(leverage.supportedMarkets(address(0)));
    }

    /// @dev it should set market as supported and emit event
    function test_SetMarketAsSupportedAndEmitEvent_WhenMarketIsValidAddressAndIsSupportedIsTrue()
        external
        givenCallerIsOwner
    {
        vm.expectEmit(true, false, false, true);
        emit AltoLeverage.MarketUpdated(address(market), true);

        leverage.setMarket(address(market), true);

        assertTrue(leverage.supportedMarkets(address(market)));
    }

    /// @dev it should set market as unsupported and emit event
    function test_SetMarketAsUnsupportedAndEmitEvent_WhenMarketIsValidAddressAndIsSupportedIsFalse()
        external
        givenCallerIsOwner
    {
        vm.expectEmit(true, false, false, true);
        emit AltoLeverage.MarketUpdated(address(market), false);

        leverage.setMarket(address(market), false);

        assertFalse(leverage.supportedMarkets(address(market)));
    }

    /// @dev Fuzz test for setting market support
    function testFuzz_SetMarketAndEmitEvent(address marketAddr, bool isSupported) external givenCallerIsOwner {
        vm.expectEmit(true, false, false, true);
        emit AltoLeverage.MarketUpdated(marketAddr, isSupported);

        leverage.setMarket(marketAddr, isSupported);

        assertEq(leverage.supportedMarkets(marketAddr), isSupported);
    }

    /// @dev Test toggling market support
    function test_ToggleMarketSupport() external givenCallerIsOwner {
        // First set to true
        leverage.setMarket(address(market), true);
        assertTrue(leverage.supportedMarkets(address(market)));

        // Then set to false
        leverage.setMarket(address(market), false);
        assertFalse(leverage.supportedMarkets(address(market)));

        // Then back to true
        leverage.setMarket(address(market), true);
        assertTrue(leverage.supportedMarkets(address(market)));
    }
}
