// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketLib} from "@alto/lending/libraries/MarketLib.sol";

import "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract ReallocateIdleTest is IntegrationTest {
    using MarketLib for address;
    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        IERC4626(address(vault)).deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();
    }

    function testReallocateSupplyIdle(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        allocations.push(MarketAllocation({market: idleMarket, assets: 0}));
        allocations.push(MarketAllocation({market: allMarkets[0], assets: suppliedAssets[0]}));
        allocations.push(MarketAllocation({market: allMarkets[1], assets: suppliedAssets[1]}));
        allocations.push(MarketAllocation({market: allMarkets[2], assets: suppliedAssets[2]}));
        allocations.push(MarketAllocation({market: idleMarket, assets: type(uint256).max}));

        uint256 idleBefore = _idle();

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(
            allMarkets[0].userSupplyShares(address(vault)),
            suppliedAssets[0] * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[0].userSupplyShares()"
        );
        assertEq(
            allMarkets[1].userSupplyShares(address(vault)),
            suppliedAssets[1] * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[1].userSupplyShares()"
        );
        assertEq(
            allMarkets[2].userSupplyShares(address(vault)),
            suppliedAssets[2] * AssetShareConversionMath.VIRTUAL_SHARES,
            "allMarkets[2].userSupplyShares()"
        );

        uint256 expectedIdle = idleBefore - suppliedAssets[0] - suppliedAssets[1] - suppliedAssets[2];
        assertApproxEqAbs(_idle(), expectedIdle, 3, "idle");
    }
}
