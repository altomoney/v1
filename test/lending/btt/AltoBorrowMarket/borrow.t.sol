// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {AltoBorrowMarket, LiquidationConfiguration} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IPausable} from "@alto/utils/Pausable.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

contract MockCallback {
    function onBorrowCallback(uint256 amount, bytes calldata data) external {}
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
}

contract BorrowTest is Test {
    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address receiver = address(0xCCC);
    address owner = address(this);
    uint256 constant INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        // Deploy mock contracts
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), owner));
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
                dynamicBonusFeeStart: 0.03 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.01 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            })
        );

        // Set owner as pauser for both pause types
        market.setPauser(owner, PAUSED_MARKET, true);
        market.setPauser(owner, FROZEN_MARKET, true);

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), receiver, INITIAL_AMOUNT);
        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), receiver, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(receiver);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Add initial supply to provide liquidity
        vm.startPrank(alice);
        market.addSupply(5000 ether, 0, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(owner);
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET));
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_MarketIsFrozen() public {
        vm.startPrank(owner);
        market.pause(FROZEN_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_MARKET));
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_BothAssetsAndSharesProvided() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 50 ether, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_ReceiverIsZeroAddress() public {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(100 ether, 0, bob, address(0), "");
        vm.stopPrank();
    }

    function test_RevertWhen_SenderIsNotAuthorized() public {
        vm.startPrank(receiver);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(100 ether, 0, bob, receiver, "");
        vm.stopPrank();
    }

    modifier givenAssetsIsProvided() {
        _;
    }

    function test_RevertWhen_AssetsIsZero() public givenAssetsIsProvided {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, bob, bob, "");
        vm.stopPrank();
    }

    modifier whenAssetsIsGreaterThanZero() {
        _;
    }

    function test_RevertWhen_MarketHasInsufficientLiquidity()
        public
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
    {
        vm.startPrank(bob);
        market.addCollateral(10000 ether, bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientMarketLiquidity.selector);
        market.borrow(6000 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    function test_RevertWhen_UserHasInsufficientCollateral() public givenAssetsIsProvided whenAssetsIsGreaterThanZero {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketBorrowingTooMuch.selector);
        market.borrow(100 ether, 0, bob, bob, "");
        vm.stopPrank();
    }

    modifier whenUserHasSufficientCollateral() {
        vm.startPrank(bob);
        market.addCollateral(1000 ether, bob);
        vm.stopPrank();
        _;
    }

    function test_RevertWhen_ReceiverIsNotAuthorizedCallback_WithData()
        public
        givenAssetsIsProvided
        whenAssetsIsGreaterThanZero
        whenUserHasSufficientCollateral
    {
        uint256 collateralAmount = 200 ether;
        uint256 borrowAmount = 100 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Try to borrow with data but receiver is not an authorized callback
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.borrow(borrowAmount, 0, bob, receiver, "some_data");
        vm.stopPrank();
    }

    function test_BorrowWithAssets_ZeroOpeningFee() public {
        uint256 borrowAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);
        (uint128 totalBorrowedAssetsBefore, uint128 totalBorrowedSharesBefore) = market.totalBorrowed();

        // Borrow with assets
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(borrowAmount, 0, bob, bob, "");

        // Verify assets were transferred to borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowAmount);

        // Verify borrow position was created
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(borrowShares, uint128(borrowedShares));
        assertEq(collateralAssets, uint128(collateralAmount));

        // Verify total borrowed was updated
        (uint128 totalBorrowedAssetsAfter, uint128 totalBorrowedSharesAfter) = market.totalBorrowed();
        assertEq(totalBorrowedAssetsAfter, totalBorrowedAssetsBefore + uint128(borrowedAssets));
        assertEq(totalBorrowedSharesAfter, totalBorrowedSharesBefore + uint128(borrowedShares));

        // With zero opening fee
        assertEq(openingFeeAssets, 0);

        vm.stopPrank();
    }

    function test_BorrowWithAssets_WithOpeningFee() public {
        // Set a borrow opening fee
        vm.startPrank(owner);
        market.setBorrowOpeningFee(0.01 ether); // 1% fee
        vm.stopPrank();

        uint256 borrowAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with assets
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(borrowAmount, 0, bob, bob, "");

        // Verify assets were transferred to borrower (original amount without fee)
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowAmount);

        // Verify opening fee was applied
        assertEq(openingFeeAssets, borrowAmount * 0.01 ether / 1 ether);
        assertGt(borrowedAssets, borrowAmount); // Total borrowed includes fee

        vm.stopPrank();
    }

    modifier givenSharesIsProvided() {
        _;
    }

    function test_RevertWhen_SharesIsZero() public givenSharesIsProvided {
        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.borrow(0, 0, bob, bob, "");
        vm.stopPrank();
    }

    modifier whenSharesIsGreaterThanZero() {
        _;
    }

    function test_BorrowWithShares_ZeroOpeningFee() public givenSharesIsProvided whenSharesIsGreaterThanZero {
        uint256 shareAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with shares
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(0, shareAmount, bob, bob, "");

        // Verify assets were transferred to borrower
        assertEq(borrowToken.balanceOf(bob), initialBalance + borrowedAssets);

        // Verify borrow position was created
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(borrowShares, uint128(borrowedShares));
        assertEq(collateralAssets, uint128(collateralAmount));

        // With zero opening fee
        assertEq(openingFeeAssets, 0);

        vm.stopPrank();
    }

    function test_BorrowWithShares_WithOpeningFee() public givenSharesIsProvided whenSharesIsGreaterThanZero {
        // Set a borrow opening fee
        vm.startPrank(owner);
        market.setBorrowOpeningFee(0.01 ether); // 1% fee
        vm.stopPrank();

        uint256 shareAmount = 100 ether;
        uint256 collateralAmount = 200 ether;

        vm.startPrank(bob);
        market.addCollateral(collateralAmount, bob);

        // Initial state check
        uint256 initialBalance = borrowToken.balanceOf(bob);

        // Borrow with shares
        (uint256 borrowedAssets, uint256 borrowedShares, uint256 openingFeeAssets) =
            market.borrow(0, shareAmount, bob, bob, "");

        // Verify assets were transferred to borrower (borrowedAssets minus the opening fee)
        uint256 assetsToReceiver = borrowedAssets - openingFeeAssets;
        assertEq(borrowToken.balanceOf(bob), initialBalance + assetsToReceiver);

        // Verify opening fee was applied
        assertGt(openingFeeAssets, 0);
        assertGt(borrowedShares, shareAmount); // Total shares includes fee

        vm.stopPrank();
    }

    function test_BorrowWithCallback_WithData() public {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
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
            config
        );
        deal(address(collateralToken), bob, 1 ether);
        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Add supply to the market
        deal(address(borrowToken), alice, 10 ether);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(10 ether, 0, alice);
        vm.stopPrank();

        // Mock the callback contract
        MockCallback callback = new MockCallback();
        // Authorize the callback contract
        vm.prank(market.owner());
        market.setAuthorizedCallback(address(callback), true);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Borrow(bob, bob, address(callback), 0.5 ether, 500000000000000000000000, 0, 0);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) =
            market.borrow(0.5 ether, 0, bob, address(callback), "data");
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(address(callback)), 0.5 ether);
    }

    function test_BorrowWithCallback_WithoutData() public {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
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
            config
        );
        deal(address(collateralToken), bob, 1 ether);
        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Add supply to the market
        deal(address(borrowToken), alice, 10 ether);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(10 ether, 0, alice);
        vm.stopPrank();

        // Mock the callback contract
        MockCallback callback = new MockCallback();
        // Authorize the callback contract
        vm.prank(market.owner());
        market.setAuthorizedCallback(address(callback), true);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Borrow(bob, bob, address(callback), 0.5 ether, 500000000000000000000000, 0, 0);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) =
            market.borrow(0.5 ether, 0, bob, address(callback), "");
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(address(callback)), 0.5 ether);
    }

    function test_BorrowWithShares_WithCallback() public {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
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
            config
        );
        deal(address(collateralToken), bob, 1 ether);
        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Add supply to the market
        deal(address(borrowToken), alice, 10 ether);
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        market.addSupply(10 ether, 0, alice);
        vm.stopPrank();

        // Mock the callback contract
        MockCallback callback = new MockCallback();
        // Authorize the callback contract
        vm.prank(market.owner());
        market.setAuthorizedCallback(address(callback), true);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Borrow(bob, bob, address(callback), 500000000000, 0.5 ether, 0, 0);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) =
            market.borrow(0, 0.5 ether, bob, address(callback), "");
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(address(callback)), 500000000000);
    }

    function test_BorrowWithZeroOpeningFee() public {
        // Create market with zero opening fee
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

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
            config
        );

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), receiver, INITIAL_AMOUNT);

        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), receiver, INITIAL_AMOUNT);

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

        vm.startPrank(receiver);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.Borrow(bob, bob, bob, 0.5 ether, 500000000000000000000000, 0, 0);
        (uint256 assets, uint256 shares, uint256 openingFeeAssets) = market.borrow(0.5 ether, 0, bob, bob, "");
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(bob), INITIAL_AMOUNT + 0.5 ether);
    }

    function test_LiquidateWithZeroBonusFee() public {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        // Mint tokens to alice and bob
        deal(address(borrowToken), alice, 10 ether);
        deal(address(borrowToken), bob, 10 ether);
        deal(address(collateralToken), alice, 10 ether);
        deal(address(collateralToken), bob, 10 ether);

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
            config
        );

        // Approve market for both users AFTER creating the new market
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(5 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addCollateral(2 ether, bob); // Increased collateral to 2 ether to support 0.8 ether borrow with 0.75 LTV
        market.borrow(0.8 ether, 0, bob, bob, "");
        vm.stopPrank();

        // Set price to make position liquidable
        OracleMock(address(market.oracle())).setPrice(ORACLE_PRICE_PRECISION / 2);

        // Tag the position
        vm.prank(alice);
        market.tagLiquidablePosition(bob, alice);

        // Wait for BOTH grace periods to pass (priority liquidation + tagger liquidation)
        (,,,,,,, uint32 taggerGracePeriod, uint32 liquidationWindowTag) = market.liquidationConfiguration();
        uint32 priorityGracePeriod = 5 minutes;
        vm.warp(block.timestamp + uint256(priorityGracePeriod) + uint256(taggerGracePeriod) + 1);

        // Liquidate with zero bonus fee
        vm.startPrank(alice);
        uint256 aliceCollateralBefore = collateralToken.balanceOf(alice);
        uint256 aliceBorrowBefore = borrowToken.balanceOf(alice);
        market.liquidate(bob, bytes(""));
        vm.stopPrank();

        // Verify liquidation occurred - alice should have received collateral tokens
        uint256 aliceCollateralAfter = collateralToken.balanceOf(alice);
        assertGt(aliceCollateralAfter, aliceCollateralBefore); // Alice receives collateral

        // Alice's borrow token balance decreases because she pays to repay bob's debt
        uint256 aliceBorrowAfter = borrowToken.balanceOf(alice);
        assertLt(aliceBorrowAfter, aliceBorrowBefore); // Alice pays borrow tokens
    }
}
