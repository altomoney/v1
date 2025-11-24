// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {
    LiquidationConfiguration,
    BaseMarketInitParams,
    BorrowMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";

contract LiquidateTest is Test {
    AltoBorrowMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0x1234);
    address priorityLiquidator = address(0x5678);
    address owner = address(this);
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: owner,
            oracle: address(oracle),
            maxLtv: 0.75 ether,
            feeRecipient: owner,
            liquidationConfiguration: config
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams, initialBorrowOpeningFee: 0, supplyCapAssets: 0
        });

        market = AltoBorrowMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        // Set owner as pauser for PAUSE_TYPE
        market.setPauser(owner, PAUSE_TYPE, true);

        // Setup priority liquidator
        market.setPriorityLiquidator(priorityLiquidator, true);

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), liquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), priorityLiquidator, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), liquidator, INITIAL_AMOUNT);
        deal(address(collateralToken), priorityLiquidator, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(priorityLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Add initial supply and set up borrowing position
        vm.startPrank(alice);
        market.addSupply(5000 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        market.borrow(600 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSE_TYPE, true);
        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_PositionIsSolvent() public {
        vm.startPrank(liquidator);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidatingSolventPosition.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier givenPositionIsInsolvent() {
        // Make position liquidatable by reducing collateral value
        address oracle = market.oracle();
        vm.startPrank(owner);
        OracleMock(oracle).setPrice(LENDING_ORACLE_PRICE_PRECISION / 2); // Halve collateral value
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_CallerIsNotAuthorized() public givenPositionIsInsolvent {
        // Try to liquidate as a non-priority, non-tagger, non-owner address
        address nonAuthorized = address(0x9999);
        vm.startPrank(nonAuthorized);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier whenCallerIsPriorityLiquidator() {
        _;
    }

    function test_LiquidateWhen_CallerIsPriorityLiquidator()
        public
        givenPositionIsInsolvent
        whenCallerIsPriorityLiquidator
    {
        // Make position liquidatable by simulating price change/interest
        market.accrueInterest();

        vm.startPrank(priorityLiquidator);
        // This should succeed since priorityLiquidator is authorized
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    modifier whenPositionIsTagged() {
        // Tag the position first
        vm.startPrank(liquidator);
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();
        _;
    }

    function test_LiquidateWhen_PositionIsTaggedAndWithinWindow() public givenPositionIsInsolvent whenPositionIsTagged {
        // Try to liquidate immediately (should fail due to grace period)
        vm.startPrank(liquidator);
        vm.expectRevert(IMarketErrors.AltoBaseMarketLiquidationUnauthorized.selector);
        market.liquidate(bob, "");
        vm.stopPrank();
    }

    function test_LiquidateWhen_PositionIsTaggedAndAfterGracePeriod()
        public
        givenPositionIsInsolvent
        whenPositionIsTagged
    {
        // Wait for grace periods to pass
        vm.warp(block.timestamp + 6 minutes + 3 minutes); // Both grace periods

        vm.startPrank(liquidator);
        // This should succeed now
        market.liquidate(bob, "");
        vm.stopPrank();
    }
}
