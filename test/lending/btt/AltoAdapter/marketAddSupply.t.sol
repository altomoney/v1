// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterCommonSetup} from "../../utils/AltoAdapter/AdapterCommonSetup.t.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Call} from "@morpho-org/bundler3/Bundler3.sol";

contract MarketAddSupplyTest is AdapterCommonSetup {
    function setUp() public override {
        super.setUp();

        // Setup initial market state
        deal(address(borrowToken), SUPPLIER, 100e18);
        vm.prank(SUPPLIER);
        market.addSupply(10e18, 0, SUPPLIER);

        deal(address(borrowToken), address(altoAdapter), 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                        REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OnBehalfIsAdapterAddress() public {
        vm.startPrank(USER);

        bundle.push(_marketAddSupply(market, 1e18, 0, type(uint256).max, address(altoAdapter)));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_AssetsMaxAndAdapterHasZeroBalance() public {
        vm.startPrank(USER);

        // Clear adapter balance
        deal(address(borrowToken), address(altoAdapter), 0);

        bundle.push(_marketAddSupply(market, type(uint256).max, 0, type(uint256).max, USER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_SlippageProtectionFailsWithAssets() public {
        vm.startPrank(USER);

        // From the trace: assets=1e18, shares=1e24, so share price = 1e18/1e24 * 1e27 = 1e21
        // Set maxSharePriceE27 below this to trigger slippage
        uint256 maxSharePriceE27 = 1e20; // Much lower than the actual share price

        bundle.push(_marketAddSupply(market, 1e18, 0, maxSharePriceE27, USER));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_SlippageProtectionFailsWithAssetsMax() public {
        vm.startPrank(USER);

        // From the trace: assets=50e18, shares=50e24, so share price = 50e18/50e24 * 1e27 = 1e21
        // Set maxSharePriceE27 below this to trigger slippage
        uint256 maxSharePriceE27 = 1e20; // Much lower than the actual share price

        bundle.push(_marketAddSupply(market, type(uint256).max, 0, maxSharePriceE27, USER));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MarketAddSupply_WithSpecifiedAssets() public {
        vm.startPrank(USER);

        uint256 assets = 5e18;
        uint256 userSharesBefore = market.position(USER).supplyShares;

        bundle.push(_marketAddSupply(market, assets, 0, type(uint256).max, USER));
        bundler3.multicall(bundle);

        uint256 userSharesAfter = market.position(USER).supplyShares;

        assertGt(userSharesAfter, userSharesBefore);

        vm.stopPrank();
    }

    function test_MarketAddSupply_WithZeroAssets() public {
        vm.startPrank(USER);

        uint256 userSharesBefore = market.position(USER).supplyShares;

        bundle.push(_marketAddSupply(market, 0, 0, type(uint256).max, USER));

        // Zero assets should revert with InvalidInput
        vm.expectRevert(); // This should fail with AltoBaseMarketInvalidInput
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_MarketAddSupply_WithMaxAssets() public {
        vm.startPrank(USER);

        uint256 adapterBalanceBefore = borrowToken.balanceOf(address(altoAdapter));
        uint256 userSharesBefore = market.position(USER).supplyShares;

        bundle.push(_marketAddSupply(market, type(uint256).max, 0, type(uint256).max, USER));
        bundler3.multicall(bundle);

        uint256 adapterBalanceAfter = borrowToken.balanceOf(address(altoAdapter));
        uint256 userSharesAfter = market.position(USER).supplyShares;

        assertEq(adapterBalanceAfter, 0);
        assertGt(userSharesAfter, userSharesBefore);

        vm.stopPrank();
    }

    function test_MarketAddSupply_WithSlippageProtection() public {
        vm.startPrank(USER);

        uint256 assets = 1e18;
        uint256 maxSharePriceE27 = 2e27; // Reasonable max price
        uint256 userSharesBefore = market.position(USER).supplyShares;

        bundle.push(_marketAddSupply(market, assets, 0, maxSharePriceE27, USER));
        bundler3.multicall(bundle);

        uint256 userSharesAfter = market.position(USER).supplyShares;

        assertGt(userSharesAfter, userSharesBefore);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    function _marketAddSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 maxSharePriceE27,
        address onBehalf
    ) internal view override returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(altoAdapter.marketAddSupply, (market, assets, shares, maxSharePriceE27, onBehalf))
        );
    }
}
