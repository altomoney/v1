// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AltoBorrowMarket, LiquidablePosition, LiquidationConfiguration, Balance
} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarketBase, IMarket, IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

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
}

contract TagLiquidablePositionTest is Test {
    using AssetShareConversionMath for uint256;

    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address liquidator = address(0xC0C);
    address priorityLiquidator = address(0xD0D);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv
    ) public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

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
        market.addSupply(100 ether, 0, alice);
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

        vm.startPrank(market.owner());
        market.setPriorityLiquidator(priorityLiquidator, true);
        vm.stopPrank();
    }

    function setUp() public {
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
    }

    function test_RevertWhen_MarketIsPaused() public {
        // Set owner as pauser for PAUSED_MARKET
        market.setPauser(market.owner(), PAUSED_MARKET, true);
        vm.startPrank(market.owner());
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();
    }

    function test_RevertWhen_PositionIsSolvent() public {
        // Setup solvent position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidatingSolventPosition.selector);
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();
    }

    modifier givenPositionIsInsolvent() {
        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_LiquidatorIsPriorityLiquidator() public givenPositionIsInsolvent {
        vm.startPrank(priorityLiquidator);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationUnauthorized.selector);
        market.tagLiquidablePosition(bob, priorityLiquidator);
        vm.stopPrank();
    }

    modifier givenLiquidatorIsNotPriorityLiquidator() {
        _;
    }

    modifier givenPositionIsAlreadyTagged() {
        // Tag position
        vm.startPrank(liquidator);
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_PositionIsAlreadyTaggedWithinWindow()
        public
        givenPositionIsInsolvent
        givenLiquidatorIsNotPriorityLiquidator
        givenPositionIsAlreadyTagged
    {
        // Try to tag again within window
        address anotherLiquidator = address(0xE0E);
        vm.startPrank(anotherLiquidator);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketLiquidationAlreadyTagged.selector);
        market.tagLiquidablePosition(bob, anotherLiquidator);
        vm.stopPrank();
    }

    modifier givenPositionIsNotTagged() {
        _;
    }

    function test_TagPositionWhen_PositionIsNotTagged()
        public
        givenPositionIsInsolvent
        givenLiquidatorIsNotPriorityLiquidator
        givenPositionIsNotTagged
    {
        vm.startPrank(liquidator);
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();

        // Verify position was tagged
        (bool isTagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertTrue(isTagged);
        assertEq(tagger, liquidator);
        assertEq(timestamp, block.timestamp);
    }

    function test_TagPositionWhen_PositionIsAlreadyTaggedAfterWindow() public {
        // Setup underwater position
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        market.accrueInterest();
        market.addInterest(0.4 ether);
        vm.stopPrank();

        // Tag position
        vm.startPrank(liquidator);
        market.tagLiquidablePosition(bob, liquidator);
        vm.stopPrank();

        // Warp past liquidation window
        (,,,,,,,, uint32 liquidationWindowTag) = market.liquidationConfiguration();
        vm.warp(block.timestamp + liquidationWindowTag + 1);

        // Tag again after window
        vm.startPrank(alice);
        vm.expectEmit();
        emit IMarketEvents.PositionTagged(bob, alice, block.timestamp);
        market.tagLiquidablePosition(bob, alice);
        vm.stopPrank();

        (bool tagged, address tagger, uint256 timestamp) = market.liquidablePositions(bob);
        assertTrue(tagged);
        assertEq(tagger, alice);
        assertEq(timestamp, block.timestamp);
    }
}
