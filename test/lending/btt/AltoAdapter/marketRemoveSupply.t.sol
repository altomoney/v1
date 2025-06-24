// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterCommonSetup} from "../../utils/AltoAdapter/AdapterCommonSetup.t.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Call} from "@morpho-org/bundler3/Bundler3.sol";

contract MarketRemoveSupplyTest is AdapterCommonSetup {
    function setUp() public override {
        super.setUp();

        // Setup initial market state with supply
        deal(address(borrowToken), SUPPLIER, 100e18);
        vm.prank(SUPPLIER);
        market.addSupply(50e18, 0, SUPPLIER);

        // Add supply for USER to remove later
        deal(address(borrowToken), USER, 100e18);
        vm.startPrank(USER);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(20e18, 0, USER);
        // Authorize the adapter to act on behalf of USER
        market.setAuthorization(address(altoAdapter), true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_SharesMaxAndInitiatorHasZeroShares() public {
        vm.startPrank(RECEIVER); // RECEIVER has no shares
        // Authorize the adapter to act on behalf of RECEIVER
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketRemoveSupply(market, 0, type(uint256).max, 0, RECEIVER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_SlippageProtectionFailsWithShares() public {
        vm.startPrank(USER);

        uint256 minSharePriceE27 = type(uint256).max; // Impossibly high min price

        bundle.push(_marketRemoveSupply(market, 0, 1e18, minSharePriceE27, USER));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_RevertWhen_SlippageProtectionFailsWithSharesMax() public {
        vm.startPrank(USER);

        uint256 minSharePriceE27 = type(uint256).max; // Impossibly high min price

        bundle.push(_marketRemoveSupply(market, 0, type(uint256).max, minSharePriceE27, USER));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SUCCESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MarketRemoveSupply_WithSpecifiedShares() public {
        vm.startPrank(USER);

        uint256 shares = 5e18;
        uint256 userSharesBefore = market.position(USER).supplyShares;
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_marketRemoveSupply(market, 0, shares, 0, RECEIVER));
        bundler3.multicall(bundle);

        uint256 userSharesAfter = market.position(USER).supplyShares;
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertLt(userSharesAfter, userSharesBefore);
        assertGt(receiverBalanceAfter, receiverBalanceBefore);

        vm.stopPrank();
    }

    function test_MarketRemoveSupply_WithZeroShares() public {
        vm.startPrank(USER);

        uint256 userSharesBefore = market.position(USER).supplyShares;
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_marketRemoveSupply(market, 0, 0, 0, RECEIVER));

        // Zero shares should revert with InvalidInput
        vm.expectRevert(); // This should fail with AltoBaseMarketInvalidInput
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function test_MarketRemoveSupply_WithMaxShares() public {
        vm.startPrank(USER);

        uint256 userSharesBefore = market.position(USER).supplyShares;
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_marketRemoveSupply(market, 0, type(uint256).max, 0, RECEIVER));
        bundler3.multicall(bundle);

        uint256 userSharesAfter = market.position(USER).supplyShares;
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertEq(userSharesAfter, 0);
        assertGt(receiverBalanceAfter, receiverBalanceBefore);

        vm.stopPrank();
    }

    function test_MarketRemoveSupply_WithSlippageProtection() public {
        vm.startPrank(USER);

        uint256 shares = 1e18;
        // From the trace: assets=1e12, shares=1e18, so share price = 1e12/1e18 * 1e27 = 1e21
        // Set minSharePriceE27 above this to trigger slippage failure initially, then use a reasonable value
        uint256 minSharePriceE27 = 1e20; // Lower than the actual share price so it should pass
        uint256 userSharesBefore = market.position(USER).supplyShares;
        uint256 receiverBalanceBefore = borrowToken.balanceOf(RECEIVER);

        bundle.push(_marketRemoveSupply(market, 0, shares, minSharePriceE27, RECEIVER));
        bundler3.multicall(bundle);

        uint256 userSharesAfter = market.position(USER).supplyShares;
        uint256 receiverBalanceAfter = borrowToken.balanceOf(RECEIVER);

        assertLt(userSharesAfter, userSharesBefore);
        assertGt(receiverBalanceAfter, receiverBalanceBefore);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    function _marketRemoveSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver
    ) internal view override returns (Call memory) {
        return _call(
            altoAdapter,
            abi.encodeCall(altoAdapter.marketRemoveSupply, (market, assets, shares, minSharePriceE27, receiver))
        );
    }
}
