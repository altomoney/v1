// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AltoBorrowMarket,
    LiquidablePosition,
    LiquidationConfiguration,
    LiquidationResult,
    Balance
} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarketBase, IMarket, IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {console2} from "forge-std/console2.sol";
// Create mock implementation for testing

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockMarket is AltoBorrowMarket {
    using AssetShareConversionMath for uint256;

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
    )
        AltoBorrowMarket(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        )
    {}

    function addInterest(uint256 amount) external {
        totalSupply.assets += uint128(amount);
        totalBorrowed.assets += uint128(amount);
    }

    function borrowSharesToAmount(uint256 shares) external view returns (uint256) {
        return shares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
    }
}

contract AltoBorrowMarketTest is Test {
    MockMarket market;
    MockERC20 borrowToken;
    MockERC20 collateralToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC0C);
    address taggerLiquidator = address(0xD0D);
    address externalLiquidator = address(0xE0E);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv
    ) public {
        borrowToken = new MockERC20("Borrow Token", "BTKN");
        collateralToken = new MockERC20("Collateral Token", "CTKN");

        // LiquidationConfiguration memory liquidationConfiguration = LiquidationConfiguration({
        //     maxLiquidationLtv: 0.8 ether,
        //     dynamicBonusFeeStart: 0.01 ether,
        //     ltvForCompleteLiquidation: 0.9 ether
        // });

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(collateralPrice);

        market = new MockMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            maxLtv,
            0,
            address(this),
            liquidationConfiguration
        );

        // Setup initial balances for test accounts
        borrowToken.mint(alice, INITIAL_AMOUNT);
        borrowToken.mint(bob, INITIAL_AMOUNT);
        borrowToken.mint(charlie, INITIAL_AMOUNT);
        borrowToken.mint(taggerLiquidator, INITIAL_AMOUNT);
        borrowToken.mint(externalLiquidator, INITIAL_AMOUNT);

        collateralToken.mint(alice, INITIAL_AMOUNT);
        collateralToken.mint(bob, INITIAL_AMOUNT);
        collateralToken.mint(charlie, INITIAL_AMOUNT);
        collateralToken.mint(taggerLiquidator, INITIAL_AMOUNT);
        collateralToken.mint(externalLiquidator, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(externalLiquidator);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(market.owner());
        market.setPriorityLiquidator(bob, true);
        market.setPriorityLiquidator(charlie, true);
        vm.stopPrank();
    }

    function setUp() public {}

    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @dev A number of virtual assets of 1 enforces a conversion rate between shares and assets when a market is
    /// empty.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(shares, totalAssets + 1, totalShares + VIRTUAL_SHARES);
    }

    function testLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            1e35,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(10 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.32 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 0.82 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);

        assertEq(liquidationResult.currentLtv, 0.82 ether);
        assertEq(liquidationResult.newLtv, 0.6 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.641655096406579765 ether);
        assertEq(liquidationResult.collateralAmount, 7.02758494010966275 ether);

        vm.stopPrank();
    }

    function testFullLiquidate() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            2 * ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(1 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 1 ether);
        market.addInterest(2 ether);

        assertEq(market.borrowSharesToAmount(borrowShares), 3 ether - 1);

        vm.stopPrank();

        vm.startPrank(charlie);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 1.5 ether);
        assertEq(liquidationResult.newLtv, 0 ether);
        assertEq(liquidationResult.optimalRepayAmount, 3 ether - 1);
        assertEq(liquidationResult.collateralAmount, 1 ether);

        (uint128 assets, uint128 shares) = market.totalBorrowed();
        assertEq(assets, 1);
        assertEq(shares, 0 ether);

        assertEq(collateralToken.balanceOf(charlie), INITIAL_AMOUNT + 1 ether);
        assertEq(borrowToken.balanceOf(charlie), INITIAL_AMOUNT - (3 ether - 1));

        vm.stopPrank();
    }

    function testLiquidateAtLltv() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.3 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.8 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 0.8 ether);
        assertEq(liquidationResult.newLtv, 0.7125 ether);
        assertEq(liquidationResult.collateralAmount, 0.513043478260869566 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.453043478260869566 ether);

        vm.stopPrank();
    }

    function testLiquidateAtTlltv() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);

        LiquidationResult memory liquidationResult = market.liquidate(bob);
        assertEq(liquidationResult.currentLtv, 0.9 ether);
        assertEq(liquidationResult.newLtv, 0 ether);
        assertEq(liquidationResult.collateralAmount, 0.95 ether);
        assertEq(liquidationResult.optimalRepayAmount, 0.9 ether);

        vm.stopPrank();
    }

    function testTagPosition() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertTrue(tagged);
        assertEq(tagger, taggerLiquidator);
        assertEq(timestamp, block.timestamp);
    }

    function testLiquidateTaggedPositionAsTagger() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration = IMarket(address(market)).liquidationConfiguration();

        vm.warp(block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod + 1);
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            taggerLiquidator,
            950000343607371433,
            900000343607371433
        );
        market.liquidate(bob);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);
    }

    function testLiquidateTaggedPositionAsExternalLiquidator() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        LiquidationConfiguration memory liquidationConfiguration = IMarket(address(market)).liquidationConfiguration();

        vm.warp(
            block.timestamp + liquidationConfiguration.priorityLiquidationGracePeriod
                + liquidationConfiguration.taggerLiquidationGracePeriod + 1
        );
        vm.startPrank(externalLiquidator);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob,
            address(collateralToken),
            address(borrowToken),
            externalLiquidator,
            950000480593735489,
            900000480593735489
        );
        market.liquidate(bob);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertFalse(tagged);
        assertEq(tagger, address(0));
        assertEq(timestamp, 0);
    }

    function testLiquidateAsPriorityLiquidator() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(bob);
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.5 ether);
        market.addInterest(0.4 ether);

        (supplyShares, borrowShares, collateralAssets) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(charlie);
        vm.expectEmit();
        emit IMarketEvents.Liquidation(
            bob, address(collateralToken), address(borrowToken), charlie, 950000000000000000, 900000000000000000
        );
        market.liquidate(bob);
        vm.stopPrank();
    }

    function testLiquidateHealthyPositionShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup healthy position (low LTV)
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.3 ether, 0, bob, bob, ""); // Low LTV position
        vm.stopPrank();

        // Try to liquidate as priority liquidator
        vm.startPrank(charlie);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidatingHealthyPosition.selector);
        market.liquidate(bob);
        vm.stopPrank();
    }

    function testLiquidateUntaggedPositionAsNonPriorityShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether); // Make position underwater
        vm.stopPrank();

        // Try to liquidate as non-priority liquidator
        vm.startPrank(externalLiquidator);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob);
        vm.stopPrank();
    }

    function testLiquidateBeforeGracePeriodAsTaggerShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();

        // Tag position
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);

        // Try to liquidate immediately (before grace period)
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob);
        vm.stopPrank();
    }

    function testLiquidateBeforeGracePeriodAsExternalShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();

        // Tag position
        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        // Warp past priority grace period but before tagger grace period
        vm.warp(block.timestamp + 6 minutes); // 5 minutes priority + 1 minute (before 2 minutes tagger period)

        // Try to liquidate as external liquidator
        vm.startPrank(externalLiquidator);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.liquidate(bob);
        vm.stopPrank();
    }

    function testReTagPositionShouldBePossibleAfterTagWindow() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        market.addInterest(0.4 ether);

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.warp(block.timestamp + IMarket(address(market)).liquidationConfiguration().liquidationWindowTag + 1);

        vm.startPrank(alice);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, alice, block.timestamp);
        market.tagLiquidablePosition(bob, alice);
        vm.stopPrank();
    }

    function testReTagPositionShouldRevert() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        market.addInterest(0.4 ether);

        vm.startPrank(taggerLiquidator);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, taggerLiquidator, block.timestamp);
        market.tagLiquidablePosition(bob, taggerLiquidator);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationAlreadyTagged.selector);
        market.tagLiquidablePosition(bob, alice);
        vm.stopPrank();
    }
}
