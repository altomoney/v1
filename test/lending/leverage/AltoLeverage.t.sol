// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket, Position, IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {console} from "forge-std/console.sol";
import {SwapParams} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {AltoLiquidationEngine} from "@alto/lending/AltoLiquidationEngine.sol";
import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";

contract AltoLeverageTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    IMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    AltoLeverage leverage;
    SwapperSimpleMock swapper;
    address alice = address(0xA11CE);
    uint256 constant INITIAL_AMOUNT = 100000000000 ether;
    address oracle;

    function setUp() public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        swapper = new SwapperSimpleMock(address(this));
        leverage = new AltoLeverage(address(swapper), address(this));

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(1 * LENDING_ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0.075 ether,
            isEnabledPriorityLiquidation: true,
            disablePriorityLiquidationAbovePositionLtv: 0.95 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        // Create liquidation engine before market deployment
        address liquidationEngine = address(new AltoLiquidationEngine(address(this)));

        BaseMarketInitParams memory baseMarketInitParams = BaseMarketInitParams({
            borrowToken: address(borrowToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            owner: address(this),
            oracle: address(oracle),
            maxLtv: 0.8 ether,
            feeRecipient: address(this),
            liquidationEngine: liquidationEngine
        });

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: baseMarketInitParams,
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });
        market = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));

        // Market initialization automatically calls setMarketOnce on the liquidation engine
        AltoLiquidationEngine(liquidationEngine).setLiquidationConfiguration(liquidationConfig);

        swapper.setWhitelisted(address(leverage), true);
        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), address(swapper), type(uint128).max);
        deal(address(collateralToken), address(swapper), type(uint128).max);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        market.setAuthorizedCallback(address(leverage), true);
        // Allow market in leverage
        leverage.setMarket(address(market), true);
    }

    function testBorrowWithAltoLeverageAsRecipient(uint256 borrowAmount) public {
        vm.assume(borrowAmount <= 4000 ether);
        vm.assume(borrowAmount > 0);

        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);
        vm.stopPrank();

        // Prepare SwapParams
        SwapParams memory leverageData = SwapParams({minAmountOut: borrowAmount, swapData: hex""});
        bytes memory data = abi.encode(leverageData);
        (bool isHealthyBefore, uint256 maxBorrowValue, uint256 borrowValue) = isSolvent(alice, address(market));

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.borrow(borrowAmount, 0, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter, uint256 maxBorrowValueAfter, uint256 borrowValueAfter) = isSolvent(alice, address(market));

        Position memory position = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should have health");

        console.log("maxBorrowValue", maxBorrowValue, maxBorrowValueAfter);
        console.log("borrowValue", borrowValue, borrowValueAfter);
        console.log("borrowShares", position.borrowShares);
        console.log("collateralAssets", position.collateralAssets);

        // Assert Alice's collateral increased (should be > 1000 ether if leverage worked)
        assertGt(position.collateralAssets, 1000 ether, "Alice's collateral should have increased due to leverage");

        // Assert leverage contract has no leftover borrow tokens (if swapper mock does nothing, may still have tokens)
        assertEq(borrowToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain borrow tokens");

        // Assert leverage contract has no leftover collateral tokens
        assertEq(
            collateralToken.balanceOf(address(leverage)), 0, "Leverage contract should not retain collateral tokens"
        );
    }

    function testRemoveCollateralWithAltoLeverage() public {
        testBorrowWithAltoLeverageAsRecipient(4000 ether);

        // Prepare SwapParams
        SwapParams memory leverageData = SwapParams({minAmountOut: 3000 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.removeCollateral(3000 ether, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));

        Position memory positionAfter = market.position(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertLt(positionAfter.borrowShares, position.borrowShares, "Alice's borrow shares should decrease");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
    }

    function testRemoveCollateralWithAltoLeverage_repay_more_than_borrowed() public {
        testBorrowWithAltoLeverageAsRecipient(4000 ether);

        // Prepare SwapParams
        SwapParams memory leverageData = SwapParams({minAmountOut: 4001 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        Position memory position = market.position(alice);
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        vm.warp(block.timestamp + 1 days);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        market.removeCollateral(4000 ether, alice, address(leverage), data);

        // Assertions
        (bool isHealthyAfter,,) = isSolvent(alice, address(market));
        Position memory positionAfter = market.position(alice);
        uint256 aliceBalanceAfter = borrowToken.balanceOf(alice);

        assertTrue(isHealthyAfter, "Alice should be healthy");
        assertEq(positionAfter.borrowShares, 0, "Alice's borrow shares should be zero");
        assertLt(positionAfter.collateralAssets, position.collateralAssets, "Alice's collateral should decrease");
        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should receive the extra token returned by the AltoLeverage swap"
        );
    }

    function testBorrowWithAltoLeverageAsRecipient_revert_due_excessive_leverage() public {
        // Alice supplies collateral
        vm.startPrank(alice);
        market.addSupply(10000000000 ether, 0, alice);
        market.addCollateral(1000 ether, alice);
        vm.stopPrank();

        // Prepare SwapParams
        SwapParams memory leverageData = SwapParams({minAmountOut: 4000.01 ether, swapData: hex""});
        bytes memory data = abi.encode(leverageData);

        // Borrow using AltoLeverage as recipient
        vm.prank(alice);
        vm.expectRevert(IMarketErrors.AltoBaseMarketBorrowingTooMuch.selector);
        market.borrow(4000.01 ether, 0, alice, address(leverage), data);
    }

    function isSolvent(address user, address _market) internal view returns (bool, uint256 max, uint256 current) {
        uint256 collateralPrice = OracleMock(oracle).getPrice();
        uint256 collateralValue = uint256(IMarket(_market).position(user).collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(IMarket(_market).maxLtv());
        uint256 borrowValue = uint256(IMarket(_market).position(user).borrowShares)
            .convertToAssetsUp(IMarket(_market).totalBorrowed().assets, IMarket(_market).totalBorrowed().shares);

        return (maxBorrowValue >= borrowValue, maxBorrowValue, borrowValue);
    }
}
