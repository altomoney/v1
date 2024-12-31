// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";

contract TapiocaOptionBrokerSetMarketTest is TOBTestBase {
    address sgl1;
    address sgl2;
    address sgl3;

    function setUp() public override {
        super.setUp();

        sgl1 = makeAddr("sgl1");
        sgl2 = makeAddr("sgl2");
        sgl3 = makeAddr("sgl3");
    }

    function test_revertWhen_callerIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        tob.setMarket(sgl1, true);
        vm.stopPrank();
    }

    function test_setMarket_validConditions() public {
        // Expect SetMarket event
        vm.expectEmit(true, true, true, true);
        emit SetMarket(sgl1, true);

        // Set market
        vm.startPrank(owner);
        tob.setMarket(sgl1, true);
        vm.stopPrank();

        // Verify market updated
        assertTrue(tob._activeMarkets(sgl1), "Market should be active");
    }

    function test_setMarket_whenDeactivatingMarket() public {
        // First activate market
        vm.startPrank(owner);
        tob.setMarket(sgl1, true);
        vm.stopPrank();

        // Expect SetMarket event
        vm.expectEmit(true, true, true, true);
        emit SetMarket(sgl1, false);

        // Deactivate market
        vm.startPrank(owner);
        tob.setMarket(sgl1, false);
        vm.stopPrank();

        // Verify market updated
        assertFalse(tob._activeMarkets(sgl1), "Market should be inactive");
    }

    function test_setMarket_multipleMarkets() public {
        // Set multiple markets
        vm.startPrank(owner);
        tob.setMarket(sgl1, true);
        tob.setMarket(sgl2, true);
        tob.setMarket(sgl3, true);
        vm.stopPrank();

        // Verify all markets active
        assertTrue(tob._activeMarkets(sgl1), "Market 1 should be active");
        assertTrue(tob._activeMarkets(sgl2), "Market 2 should be active");
        assertTrue(tob._activeMarkets(sgl3), "Market 3 should be active");

        // Deactivate one market
        vm.startPrank(owner);
        tob.setMarket(sgl2, false);
        vm.stopPrank();

        // Verify market states
        assertTrue(tob._activeMarkets(sgl1), "Market 1 should still be active");
        assertFalse(tob._activeMarkets(sgl2), "Market 2 should be inactive");
        assertTrue(tob._activeMarkets(sgl3), "Market 3 should still be active");
    }

    event SetMarket(address market, bool active);
}
