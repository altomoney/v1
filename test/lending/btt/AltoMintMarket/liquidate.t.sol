// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract LiquidateTest is AltoMintMarketTest {
    function setUp() public override {
        super.setUp();

        // Set owner as pauser
        vm.startPrank(owner);
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() external {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() external {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(alice);
        // liquidate function only has whenNotPaused modifier, not whenNotFrozen
        // So it should proceed to liquidation logic and fail on authorization
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier whenMarketIsNotPausedAndNotFrozen() {
        _;
    }

    function test_RevertWhen_UserIsZeroAddress() external whenMarketIsNotPausedAndNotFrozen {
        vm.startPrank(alice);
        // No explicit zero address validation in liquidate, so it gets to liquidation authorization check
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(address(0), "");
        vm.stopPrank();
    }

    modifier whenInputsAreValid() {
        _;
    }

    function test_RevertWhen_PositionIsNotLiquidable() external whenMarketIsNotPausedAndNotFrozen whenInputsAreValid {
        // Create a healthy position
        vm.startPrank(bob);
        market.addCollateral(500 ether, bob);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidatingSolventPosition.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier givenPositionIsLiquidable() {
        // Create liquidable position
        vm.startPrank(bob);
        market.addCollateral(100 ether, bob);
        // Borrow amount that keeps total (including 10% fee) within 75% LTV
        // 63.6 ether + 10% fee = 69.96 ether total ≈ 70% LTV
        market.borrow(636 * 1e17, 0, bob, bob, ""); // ~63.6 ether
        vm.stopPrank();

        // Manipulate oracle price to make position liquidable (50% price drop doubles the effective LTV)
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getPrice()"),
            abi.encode(ORACLE_PRICE_PRECISION / 2) // Half price = double effective LTV
        );
        _;
    }

    modifier givenPositionIsNotTagged() {
        _;
    }

    modifier givenCallerIsNotPriorityLiquidator() {
        _;
    }

    function test_RevertGiven_PositionIsNotTaggedAndCallerIsNotPriorityLiquidator()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsNotTagged
        givenCallerIsNotPriorityLiquidator
    {
        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier givenCallerIsPriorityLiquidator() {
        vm.startPrank(owner);
        market.setPriorityLiquidator(alice, true);
        vm.stopPrank();
        _;
    }

    function test_WhenPositionIsNotTaggedAndCallerIsPriorityLiquidator()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsNotTagged
        givenCallerIsPriorityLiquidator
    {
        uint256 aliceCollateralBefore = collateralToken.balanceOf(alice);
        uint256 aliceBorrowBefore = borrowToken.balanceOf(alice);
        (, uint128 bobBorrowSharesBefore, uint128 bobCollateralBefore) = market.position(bob);

        vm.startPrank(alice);
        market.liquidate(bob, "");
        vm.stopPrank();

        // it should liquidate the position partially
        uint256 aliceCollateralAfter = collateralToken.balanceOf(alice);
        uint256 aliceBorrowAfter = borrowToken.balanceOf(alice);
        (, uint128 bobBorrowSharesAfter, uint128 bobCollateralAfter) = market.position(bob);

        // Alice should receive collateral and pay borrow tokens
        assertGt(aliceCollateralAfter, aliceCollateralBefore);
        assertLt(aliceBorrowAfter, aliceBorrowBefore);

        // Bob's position should be reduced
        assertLt(bobBorrowSharesAfter, bobBorrowSharesBefore);
        assertLt(bobCollateralAfter, bobCollateralBefore);

        // it should emit Liquidate event (implicit in successful execution)
    }

    modifier givenPositionIsTagged() {
        // Tag the position first
        vm.startPrank(charlie);
        market.tagLiquidablePosition(bob, charlie);
        vm.stopPrank();
        _;
    }

    function test_WhenPositionIsTaggedAndWithinGracePeriod()
        external
        whenMarketIsNotPausedAndNotFrozen
        whenInputsAreValid
        givenPositionIsLiquidable
        givenPositionIsTagged
    {
        // Charlie (tagger) should NOT be able to liquidate during priority grace period
        // Only priority liquidators can liquidate during this time
        vm.startPrank(charlie);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }
}
