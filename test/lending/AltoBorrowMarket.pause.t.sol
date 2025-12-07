// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract AltoBorrowMarketPauseTest is Test {
    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address pauser = address(0x1);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            0.75 ether,
            0,
            address(this),
            liquidationConfig
        );

        // Setup initial balances
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);

        // Setup approvals
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Setup initial supply
        vm.startPrank(alice);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();
    }

    function testSetPauser() public {
        // Owner can set pauser
        market.setPauser(pauser, PAUSE_TYPE, true);
        assertTrue(market.pausers(pauser, PAUSE_TYPE));

        // Owner can remove pauser
        market.setPauser(pauser, PAUSE_TYPE, false);
        assertFalse(market.pausers(pauser, PAUSE_TYPE));

        // Non-owner cannot set pauser
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        market.setPauser(pauser, PAUSE_TYPE, true);
        vm.stopPrank();
    }

    function testPauseMarket() public {
        // Setup pauser
        market.setPauser(pauser, PAUSE_TYPE, true);

        // Pauser can pause market
        vm.startPrank(pauser);
        market.pause(PAUSE_TYPE, true);
        assertTrue(market.paused(PAUSE_TYPE));

        // Pauser can unpause market
        market.pause(PAUSE_TYPE, false);
        assertFalse(market.paused(PAUSE_TYPE));
        vm.stopPrank();

        // Non-pauser cannot pause market
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, alice, PAUSE_TYPE));
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();
    }

    function testFreezeMarket() public {
        // Setup pauser
        market.setPauser(pauser, FROZEN_TYPE, true);

        // Pauser can freeze market
        vm.startPrank(pauser);
        market.pause(FROZEN_TYPE, true);
        assertTrue(market.paused(FROZEN_TYPE));

        // Pauser can unfreeze market
        market.pause(FROZEN_TYPE, false);
        assertFalse(market.paused(FROZEN_TYPE));
        vm.stopPrank();

        // Non-pauser cannot freeze market
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, alice, FROZEN_TYPE));
        market.pause(FROZEN_TYPE, true);
        vm.stopPrank();
    }

    function testPausedMarketOperations() public {
        // Setup pauser and pause market
        market.setPauser(pauser, PAUSE_TYPE, true);
        vm.startPrank(pauser);
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();

        // All operations should revert when paused
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.addSupply(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.removeSupply(1 ether, 0, bob, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.addCollateral(1 ether, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.removeCollateral(1 ether, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.borrow(1 ether, 0, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.repay(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.liquidate(alice, hex"", hex"");

        IDcfDlbPriorityLiquidationEngine liquidationEngine =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        liquidationEngine.tagLiquidablePosition(alice, bob);
        vm.stopPrank();
    }

    function testFrozenMarketOperations() public {
        // Setup initial position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        vm.stopPrank();

        // Setup pauser and freeze market
        market.setPauser(pauser, FROZEN_TYPE, true);
        vm.startPrank(pauser);
        market.pause(FROZEN_TYPE, true);
        vm.stopPrank();

        // New supply/borrow/collateral operations should revert
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        market.addSupply(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        market.borrow(0.1 ether, 0, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE));
        market.addCollateral(1 ether, bob);

        // Repay and remove collateral should still work
        market.repay(0.1 ether, 0, bob);
        market.removeCollateral(0.1 ether, bob, bob, "");

        // Liquidations should still work
        vm.startPrank(alice);
        market.addInterest(1 ether); // Make position underwater
        vm.stopPrank();

        // Make alice a priority liquidator
        vm.startPrank(owner);
        IDcfDlbPriorityLiquidationEngine(market.liquidationEngine()).setPriorityLiquidator(alice, true);
        vm.stopPrank();

        vm.startPrank(alice);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }

    function testPauseAndFreezeInteraction() public {
        // Setup pauser
        market.setPauser(pauser, PAUSE_TYPE, true);
        market.setPauser(pauser, FROZEN_TYPE, true);

        // Test pause while frozen
        vm.startPrank(pauser);
        market.pause(FROZEN_TYPE, true);
        market.pause(PAUSE_TYPE, true);
        assertTrue(market.paused(FROZEN_TYPE));
        assertTrue(market.paused(PAUSE_TYPE));

        // Test unpause while frozen
        market.pause(PAUSE_TYPE, false);
        assertFalse(market.paused(PAUSE_TYPE));
        assertTrue(market.paused(FROZEN_TYPE));

        vm.stopPrank();
    }

    function testMultiplePausers() public {
        address pauser2 = address(0x2);
        address pauser3 = address(0x3);

        // Setup multiple pausers
        market.setPauser(pauser, PAUSE_TYPE, true);
        market.setPauser(pauser2, PAUSE_TYPE, true);
        market.setPauser(pauser3, PAUSE_TYPE, true);

        // Each pauser can pause/unpause
        vm.startPrank(pauser);
        market.pause(PAUSE_TYPE, true);
        assertTrue(market.paused(PAUSE_TYPE));
        vm.stopPrank();

        vm.startPrank(pauser2);
        market.pause(PAUSE_TYPE, false);
        assertFalse(market.paused(PAUSE_TYPE));
        vm.stopPrank();

        vm.startPrank(pauser3);
        market.pause(PAUSE_TYPE, true);
        assertTrue(market.paused(PAUSE_TYPE));
        vm.stopPrank();
    }

    function testPauseEvents() public {
        market.setPauser(pauser, PAUSE_TYPE, true);

        // Test pause event
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE, true);
        market.pause(PAUSE_TYPE, true);

        // Test unpause event
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSE_TYPE, false);
        market.pause(PAUSE_TYPE, false);
        vm.stopPrank();
    }

    function testFreezeEvents() public {
        market.setPauser(pauser, FROZEN_TYPE, true);

        // Test freeze event
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, FROZEN_TYPE, true);
        market.pause(FROZEN_TYPE, true);

        // Test unfreeze event
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, FROZEN_TYPE, false);
        market.pause(FROZEN_TYPE, false);
        vm.stopPrank();
    }

    function testPauserEvents() public {
        // Test pauser added event
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE, true);
        market.setPauser(pauser, PAUSE_TYPE, true);

        // Test pauser removed event
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSE_TYPE, false);
        market.setPauser(pauser, PAUSE_TYPE, false);
    }
}
