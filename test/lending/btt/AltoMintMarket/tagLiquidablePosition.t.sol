// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract TagLiquidablePositionTest is AltoMintMarketTest {
    function setUp() public override {
        super.setUp();

        // Set owner as pauser
        vm.startPrank(owner);
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPriorityLiquidator(charlie, true); // Make charlie a priority liquidator
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.tagLiquidablePosition(alice, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_PositionIsSolvent() external {
        // Position with no borrows or sufficient collateral should not be liquidable
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        market.borrow(50 ether, 0, alice, alice, ""); // Safe LTV
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidatingSolventPosition.selector);
        market.tagLiquidablePosition(alice, bob);
        vm.stopPrank();
    }

    function test_RevertWhen_LiquidatorIsPriorityLiquidator() external {
        // Create liquidable position
        vm.startPrank(alice);
        market.addCollateral(100 ether, alice);
        market.borrow(636 * 1e17, 0, alice, alice, "");
        vm.stopPrank();

        // Make position liquidable
        vm.mockCall(address(oracle), abi.encodeWithSignature("getPrice()"), abi.encode(ORACLE_PRICE_PRECISION / 2));

        vm.startPrank(charlie); // charlie is priority liquidator
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.tagLiquidablePosition(alice, charlie);
        vm.stopPrank();
    }

    modifier givenLiquidatorIsNotPriorityLiquidator() {
        _;
    }

    modifier givenPositionIsAlreadyTagged() {
        // Create liquidable position
        vm.startPrank(alice);
        market.addCollateral(100 ether, alice);
        market.borrow(636 * 1e17, 0, alice, alice, "");
        vm.stopPrank();

        // Make position liquidable
        vm.mockCall(address(oracle), abi.encodeWithSignature("getPrice()"), abi.encode(ORACLE_PRICE_PRECISION / 2));

        // First tag the position
        vm.startPrank(bob);
        market.tagLiquidablePosition(alice, bob);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_PositionIsAlreadyTaggedWithinLiquidationWindow()
        external
        givenLiquidatorIsNotPriorityLiquidator
        givenPositionIsAlreadyTagged
    {
        // Try to tag again within liquidation window
        vm.startPrank(makeAddr("otherLiquidator"));
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationAlreadyTagged.selector);
        market.tagLiquidablePosition(alice, makeAddr("otherLiquidator"));
        vm.stopPrank();
    }

    function test_TagPositionWhen_PositionIsAlreadyTaggedAfterLiquidationWindow()
        external
        givenLiquidatorIsNotPriorityLiquidator
        givenPositionIsAlreadyTagged
    {
        // Wait for liquidation window to pass (3 days)
        vm.warp(block.timestamp + 3 days + 1);

        // Tag again after liquidation window
        address newTagger = makeAddr("newTagger");
        vm.startPrank(newTagger);
        market.tagLiquidablePosition(alice, newTagger);
        vm.stopPrank();

        // it should tag position
        (bool isTagged, address tagger, uint256 timestamp) = market.liquidablePositions(alice);
        assertTrue(isTagged);
        assertEq(tagger, newTagger);
        assertEq(timestamp, block.timestamp);
    }

    modifier givenPositionIsNotTagged() {
        // Create liquidable position
        vm.startPrank(alice);
        market.addCollateral(100 ether, alice);
        market.borrow(636 * 1e17, 0, alice, alice, "");
        vm.stopPrank();

        // Make position liquidable
        vm.mockCall(address(oracle), abi.encodeWithSignature("getPrice()"), abi.encode(ORACLE_PRICE_PRECISION / 2));
        _;
    }

    function test_TagPositionWhen_PositionIsNotTagged()
        external
        givenLiquidatorIsNotPriorityLiquidator
        givenPositionIsNotTagged
    {
        // Check initial state
        (bool isTaggedBefore,,) = market.liquidablePositions(alice);
        assertFalse(isTaggedBefore);

        vm.startPrank(bob);
        market.tagLiquidablePosition(alice, bob);
        vm.stopPrank();

        // it should tag position
        (bool isTaggedAfter, address tagger, uint256 timestamp) = market.liquidablePositions(alice);
        assertTrue(isTaggedAfter);
        assertEq(tagger, bob);
        assertEq(timestamp, block.timestamp);
    }
}
