// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarketBase, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

contract MockMarket is AltoBaseMarket {
    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) {
        __AltoBaseMarket_init(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        );
    }

    function addInterest(uint256 amount) external {
        totalSupply.assets += uint128(amount);
        totalBorrowed.assets += uint128(amount);
    }
}

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
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        market = new MockMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            0.75 ether,
            0,
            address(this),
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                isEnabledPriorityLiquidation: true,
                disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
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
        market.setPauser(pauser, PAUSED_MARKET, true);
        assertTrue(market.pausers(pauser, PAUSED_MARKET));

        // Owner can remove pauser
        market.setPauser(pauser, PAUSED_MARKET, false);
        assertFalse(market.pausers(pauser, PAUSED_MARKET));

        // Non-owner cannot set pauser
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        market.setPauser(pauser, PAUSED_MARKET, true);
        vm.stopPrank();
    }

    function testPauseMarket() public {
        // Setup pauser
        market.setPauser(pauser, PAUSED_MARKET, true);

        // Pauser can pause market
        vm.startPrank(pauser);
        market.pause(PAUSED_MARKET, true);
        assertTrue(market.paused(PAUSED_MARKET));

        // Pauser can unpause market
        market.pause(PAUSED_MARKET, false);
        assertFalse(market.paused(PAUSED_MARKET));
        vm.stopPrank();

        // Non-pauser cannot pause market
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, alice, PAUSED_MARKET));
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();
    }

    function testFreezeMarket() public {
        // Setup pauser
        market.setPauser(pauser, FROZEN_MARKET, true);

        // Pauser can freeze market
        vm.startPrank(pauser);
        market.pause(FROZEN_MARKET, true);
        assertTrue(market.paused(FROZEN_MARKET));

        // Pauser can unfreeze market
        market.pause(FROZEN_MARKET, false);
        assertFalse(market.paused(FROZEN_MARKET));
        vm.stopPrank();

        // Non-pauser cannot freeze market
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPausable.Unauthorized.selector, alice, FROZEN_MARKET));
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();
    }

    function testPausedMarketOperations() public {
        // Setup pauser and pause market
        market.setPauser(pauser, PAUSED_MARKET, true);
        vm.startPrank(pauser);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        // All operations should revert when paused
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.addSupply(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.removeSupply(1 ether, 0, bob, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.addCollateral(1 ether, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.removeCollateral(1 ether, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.borrow(1 ether, 0, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.repay(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.liquidate(alice, hex"");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.tagLiquidablePosition(alice, bob);
        vm.stopPrank();
    }

    function testFrozenMarketOperations() public {
        // Setup initial position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        vm.stopPrank();

        // Setup pauser and freeze market
        market.setPauser(pauser, FROZEN_MARKET, true);
        vm.startPrank(pauser);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        // New supply/borrow/collateral operations should revert
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.addSupply(1 ether, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.borrow(0.1 ether, 0, bob, bob, "");

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
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
        market.setPriorityLiquidator(alice, true);
        vm.stopPrank();

        vm.startPrank(alice);
        market.liquidate(bob, hex"");
        vm.stopPrank();
    }

    function testPauseAndFreezeInteraction() public {
        // Setup pauser
        market.setPauser(pauser, PAUSED_MARKET, true);
        market.setPauser(pauser, FROZEN_MARKET, true);

        // Test pause while frozen
        vm.startPrank(pauser);
        market.pause(FROZEN_MARKET, true);
        market.pause(PAUSED_MARKET, true);
        assertTrue(market.paused(FROZEN_MARKET));
        assertTrue(market.paused(PAUSED_MARKET));

        // Test unpause while frozen
        market.pause(PAUSED_MARKET, false);
        assertFalse(market.paused(PAUSED_MARKET));
        assertTrue(market.paused(FROZEN_MARKET));

        vm.stopPrank();
    }

    function testMultiplePausers() public {
        address pauser2 = address(0x2);
        address pauser3 = address(0x3);

        // Setup multiple pausers
        market.setPauser(pauser, PAUSED_MARKET, true);
        market.setPauser(pauser2, PAUSED_MARKET, true);
        market.setPauser(pauser3, PAUSED_MARKET, true);

        // Each pauser can pause/unpause
        vm.startPrank(pauser);
        market.pause(PAUSED_MARKET, true);
        assertTrue(market.paused(PAUSED_MARKET));
        vm.stopPrank();

        vm.startPrank(pauser2);
        market.pause(PAUSED_MARKET, false);
        assertFalse(market.paused(PAUSED_MARKET));
        vm.stopPrank();

        vm.startPrank(pauser3);
        market.pause(PAUSED_MARKET, true);
        assertTrue(market.paused(PAUSED_MARKET));
        vm.stopPrank();
    }

    function testPauseEvents() public {
        market.setPauser(pauser, PAUSED_MARKET, true);

        // Test pause event
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSED_MARKET, true);
        market.pause(PAUSED_MARKET, true);

        // Test unpause event
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, PAUSED_MARKET, false);
        market.pause(PAUSED_MARKET, false);
        vm.stopPrank();
    }

    function testFreezeEvents() public {
        market.setPauser(pauser, FROZEN_MARKET, true);

        // Test freeze event
        vm.startPrank(pauser);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, FROZEN_MARKET, true);
        market.pause(FROZEN_MARKET, true);

        // Test unfreeze event
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(pauser, FROZEN_MARKET, false);
        market.pause(FROZEN_MARKET, false);
        vm.stopPrank();
    }

    function testPauserEvents() public {
        // Test pauser added event
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSED_MARKET, true);
        market.setPauser(pauser, PAUSED_MARKET, true);

        // Test pauser removed event
        vm.expectEmit(true, true, true, true);
        emit IPausable.PauserUpdated(pauser, PAUSED_MARKET, false);
        market.setPauser(pauser, PAUSED_MARKET, false);
    }
}
