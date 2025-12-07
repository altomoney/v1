// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {IMarket, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ILiquidateCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

contract LiquidateCallback is ILiquidateCallback {
    function onLiquidateCallback(uint256 assetsToRepay, uint256 collateralReceived, bytes calldata data) external {
        (address borrowToken, uint256 borrowAmount) = abi.decode(data, (address, uint256));
        IERC20(borrowToken).approve(msg.sender, assetsToRepay);
    }
}

error OracleAlwaysReverts();

contract OracleMockAlwaysReverts {
    function setPrice(uint256 price) external pure {}

    function getPrice() external pure returns (uint256) {
        revert OracleAlwaysReverts();
    }
}

contract AltoBorrowMarketLiquidationsFuzzTest is Test {
    MockMarket market;
    IMarket internal imarket;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    OracleMock oracle;
    OracleMockAlwaysReverts oracleAlwaysReverts;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address supplier = address(0xB0B1);
    address liquidator = address(0xC0C);
    address taggerLiquidator = address(0xD0D);
    address externalLiquidator = address(0xE0E);
    uint256 constant INITIAL_AMOUNT = 1000 ether;
    LiquidateCallback liquidateCallback;

    address internal immutable FEE_RECEIVER = makeAddr("FeeReceiver");

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv,
        IERC20 collateralToken,
        address oracle
    ) public {
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        OracleMock(oracle).setPrice(collateralPrice);

        market = _deployMarket(
            address(borrowToken), address(collateralToken), irm, address(oracle), maxLtv, liquidationConfiguration
        );

        imarket = IMarket(address(market));

        _setupInitialBalances();
        _setupApprovals();
        _setupMarketPermissions();
    }

    function _deployMarket(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _oracle,
        uint256 _maxLtv,
        LiquidationConfiguration memory _liquidationConfiguration
    ) internal returns (MockMarket) {
        return MockMarketDeployer.deployMarket(
            _borrowToken,
            _collateralToken,
            _irm,
            address(this),
            _oracle,
            _maxLtv,
            0,
            FEE_RECEIVER,
            _liquidationConfiguration
        );
    }

    function _setupInitialBalances() internal {
        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), supplier, INITIAL_AMOUNT);
        deal(address(borrowToken), liquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(borrowToken), externalLiquidator, INITIAL_AMOUNT);

        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), supplier, INITIAL_AMOUNT);
        deal(address(collateralToken), liquidator, INITIAL_AMOUNT);
        deal(address(collateralToken), taggerLiquidator, INITIAL_AMOUNT);
        deal(address(collateralToken), externalLiquidator, INITIAL_AMOUNT);
    }

    function _setupApprovals() internal {
        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(supplier);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidator);
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
    }

    function _setupMarketPermissions() internal {
        vm.startPrank(market.owner());
        IDcfDlbPriorityLiquidationEngine liquidationEngine =
            IDcfDlbPriorityLiquidationEngine(market.liquidationEngine());
        liquidationEngine.setPriorityLiquidator(bob, true);
        liquidationEngine.setPriorityLiquidator(liquidator, true);
        liquidationEngine.setPriorityLiquidator(address(liquidateCallback), true);
        vm.stopPrank();
    }

    function setUp() public {
        liquidateCallback = new LiquidateCallback();
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        oracle = new OracleMock();
        oracleAlwaysReverts = new OracleMockAlwaysReverts();
    }

    function testLiquidateGeneralScenario(uint256 ltv, uint256 depositAmount) public {
        // keeping reasonable ltv and capping it at maxLiquidationLtv
        ltv = bound(ltv, 0.6 ether, 0.8 ether);
        // keeping reasonable deposit amount
        depositAmount = bound(depositAmount, 1e12, 1000_000 ether);

        // creating the market with valid collateral token of 18 decimals and valid oracle price
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36, // 1 USD
            ltv, // LTV
            collateralToken,
            address(oracle)
        );

        deal(address(collateralToken), bob, depositAmount);
        deal(address(borrowToken), supplier, depositAmount);

        // supplying the assets which can be used to borrow
        vm.startPrank(supplier);
        market.addSupply(depositAmount, 0, supplier);
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(bob);
        market.addCollateral(depositAmount, bob);
        uint256 borrowAmount = depositAmount * ltv / 1 ether;
        // borrowing the maximum allowed amount of assets
        market.borrow(borrowAmount, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(liquidator);
        (, uint128 borrowShares,) = market.position(bob);
        assertEq(market.borrowSharesToAmount(borrowShares), borrowAmount, "invalid borrowAmount for borrowShares");
        // adding interest in the market to make position underwater
        uint256 interestAmount = borrowAmount / 2;
        market.addInterest(interestAmount);
        market.accrueInterest();

        // increasing balance of borrow token to the liquidator to be used for liquidation
        deal(address(borrowToken), liquidator, borrowAmount + interestAmount);
        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);

        // asserts that borrowShares represents the correct amount of assets after interest is added
        assertApproxEqAbs(
            market.borrowSharesToAmount(borrowShares),
            borrowAmount + interestAmount,
            1e6,
            "invalid borrowAmount for borrowShares after interest"
        );

        // expecting the liquidation event to be emitted
        vm.expectEmit(true, false, false, false, address(market));
        emit IMarketEvents.Liquidation(bob, liquidator, 0, 0, 0, 0, 0, 0);

        uint256 borrowTokenBalanceOfLiquidatorBefore = borrowToken.balanceOf(liquidator);
        // liquidating the underwater position should always succeed
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(bob, hex"", hex"");

        // asserts that collateral is seized and amount repaid is greater than 0
        assertGt(collateralAmount, 0, "no collateral seized during liquidation");
        assertGt(repayAmount, 0, "no amount repaid during liquidation");

        // asserts that protocol fee is credited to fee recipient
        assertEq(
            imarket.position(FEE_RECEIVER).collateralAssets, protocolFee, "protocol fee not credited to fee recipient"
        );

        // asserts that collateral token balance of market is updated
        assertEq(
            collateralToken.balanceOf(address(market)),
            depositAmount - collateralAmount + protocolFee,
            "collateral token balance of market not updated"
        );

        // asserts that borrow token balance of liquidator is updated
        assertEq(
            borrowToken.balanceOf(liquidator),
            borrowTokenBalanceOfLiquidatorBefore - repayAmount,
            "borrow token balance of liquidator not updated"
        );
        vm.stopPrank();
    }

    function testLiquidateDueToHugeDebtAddition(uint256 ltv, uint256 depositAmount, uint256 interestAmount) public {
        ltv = bound(ltv, 0.6 ether, 0.8 ether);
        depositAmount = bound(depositAmount, 0.0001 ether, 1000_000 ether);
        // huge interest amount will be added to market to make position underwater
        interestAmount = bound(interestAmount, depositAmount * 2, depositAmount * 1000_000);

        // creating the market with valid collateral token of 18 decimals and valid oracle price
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36, // 1 USD
            ltv, // LTV
            collateralToken,
            address(oracle)
        );

        deal(address(collateralToken), bob, depositAmount);
        deal(address(borrowToken), supplier, depositAmount);

        // supplying the assets which can be used to borrow
        vm.startPrank(supplier);
        market.addSupply(depositAmount, 0, supplier);
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(bob);
        market.addCollateral(depositAmount, bob);
        uint256 borrowAmount = depositAmount * ltv / 1 ether;
        // borrowing the maximum allowed amount of assets
        market.borrow(borrowAmount, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(liquidator);
        // adding huge interest rate in market which will make position eligible for full liquidation
        market.addInterest(interestAmount);
        market.accrueInterest();

        // increasing balance of borrow token to the liquidator to be used for liquidation
        deal(address(borrowToken), liquidator, borrowAmount + interestAmount);
        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);

        // expecting the liquidation event to be emitted
        vm.expectEmit(true, false, false, false, address(market));
        emit IMarketEvents.Liquidation(bob, liquidator, 0, 0, 0, 0, 0, 0);

        // liquidating the underwater position should always succeed
        uint256 borrowTokenBalanceOfLiquidatorBefore = borrowToken.balanceOf(liquidator);
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(bob, hex"", hex"");

        // asserts that collateral is seized and amount repaid is greater than 0
        assertGt(collateralAmount, 0, "no collateral seized during liquidation");
        assertGt(repayAmount, 0, "no amount repaid during liquidation");

        // asserts that protocol fee is credited to fee recipient
        assertEq(
            imarket.position(FEE_RECEIVER).collateralAssets, protocolFee, "protocol fee not credited to fee recipient"
        );

        // asserts that collateral token balance of market is updated
        assertEq(
            collateralToken.balanceOf(address(market)),
            depositAmount - collateralAmount + protocolFee,
            "collateral token balance of market not updated"
        );

        // asserts that borrow token balance of liquidator is updated
        assertEq(
            borrowToken.balanceOf(liquidator),
            borrowTokenBalanceOfLiquidatorBefore - repayAmount,
            "borrow token balance of liquidator not updated"
        );

        // asserts that supply shares, borrow shares and collateral assets are 0 after full liquidation
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(supplyShares, 0, "supply shares should be 0 after full liquidation");
        assertEq(borrowShares, 0, "borrow shares should be 0 after full liquidation");
        assertEq(collateralAssets, 0, "collateral assets should be 0 after full liquidation");

        vm.stopPrank();
    }

    function testLiquidateDisbalanceBetweenSharesAndAssets(uint256 ltv, uint256 depositAmount) public {
        ltv = bound(ltv, 0.6 ether, 0.8 ether);
        // keeping deposit amount very low to create disbalance between shares and assets
        depositAmount = bound(depositAmount, 10, 1e12);

        // creating the market with valid collateral token of 18 decimals and valid oracle price
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36, // 1 USD
            ltv, // LTV
            collateralToken,
            address(oracle)
        );

        deal(address(collateralToken), bob, depositAmount);
        deal(address(borrowToken), supplier, depositAmount);

        // supplying the assets which can be used to borrow
        vm.startPrank(supplier);
        market.addSupply(depositAmount, 0, supplier);
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(alice);
        market.addCollateral(2, alice);
        // borrowing 1 wei of shares
        market.borrow(0, 1, alice, alice, "");
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(bob);
        market.addCollateral(depositAmount, bob);
        // borrowing shares of half of deposit amount
        market.borrow(0, depositAmount / 2, bob, bob, "");
        vm.stopPrank();

        // adding sufficient interest in the market to make position underwater
        market.addInterest(1e12);

        // Make borrower2 insolvent
        OracleMock(market.oracle()).setPrice(1e36 / 10);

        vm.startPrank(liquidator);

        vm.expectEmit(true, false, false, false, address(market));
        emit IMarketEvents.Liquidation(bob, liquidator, 0, 0, 0, 0, 0, 0);
        // liquidation of underwater position with low deposit amount should succeed
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(bob, hex"", hex"");

        // asserts that collateral is seized and amount repaid is greater than 0
        assertGt(collateralAmount, 0, "no collateral seized during liquidation");
        assertGt(repayAmount, 0, "no amount repaid during liquidation");
        vm.stopPrank();
    }

    function testLiquidateIrmWithHugeInterestRate(uint256 ltv, uint256 depositAmount) public {
        ltv = bound(ltv, 0.6 ether, 0.8 ether);
        // reasonable deposit amount
        depositAmount = bound(depositAmount, 0.0001 ether, 1000_000 ether);

        // creating the market with valid collateral token of 18 decimals and valid oracle price
        // oracle will be updated with high interest rate IRM
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36, // 1 USD
            ltv, // LTV
            collateralToken,
            address(oracle)
        );

        deal(address(collateralToken), bob, depositAmount);
        deal(address(borrowToken), supplier, depositAmount);

        // supplying the assets which can be used to borrow
        vm.startPrank(supplier);
        market.addSupply(depositAmount, 0, supplier);
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(bob);
        market.addCollateral(depositAmount, bob);
        uint256 borrowAmount = depositAmount * ltv / 1 ether;
        // borrowing the maximum allowed amount of assets
        market.borrow(borrowAmount, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        // Set high interest rate IRM
        vm.startPrank(market.owner());
        market.setIrm(address(new FixedRateIrm(8 ether / uint256(365 days), address(this))), false);
        vm.stopPrank();

        // advancing time to accrue significant interest
        vm.warp(block.timestamp + 200 days);
        market.accrueInterest();

        vm.startPrank(liquidator);

        // increasing balance of borrow token to the liquidator to be used for liquidation
        deal(address(borrowToken), liquidator, type(uint128).max);
        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);

        // expecting the liquidation event to be emitted
        vm.expectEmit(true, false, false, false, address(market));
        emit IMarketEvents.Liquidation(bob, liquidator, 0, 0, 0, 0, 0, 0);

        uint256 borrowTokenBalanceOfLiquidatorBefore = borrowToken.balanceOf(liquidator);
        // liquidating the underwater position should always succeed
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(bob, hex"", hex"");

        // asserts that collateral is seized and amount repaid is greater than 0
        assertGt(collateralAmount, 0, "no collateral seized during liquidation");
        assertGt(repayAmount, 0, "no amount repaid during liquidation");

        // asserts that protocol fee is credited to fee recipient
        assertEq(
            imarket.position(FEE_RECEIVER).collateralAssets, protocolFee, "protocol fee not credited to fee recipient"
        );

        // asserts that collateral token balance of market is updated
        assertEq(
            collateralToken.balanceOf(address(market)),
            depositAmount - collateralAmount + protocolFee,
            "collateral token balance of market not updated"
        );

        // asserts that borrow token balance of liquidator is updated
        assertEq(
            borrowToken.balanceOf(liquidator),
            borrowTokenBalanceOfLiquidatorBefore - repayAmount,
            "borrow token balance of liquidator not updated"
        );

        // asserts that supply shares, borrow shares and collateral assets are 0 after full liquidation
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) = market.position(bob);
        assertEq(supplyShares, 0, "supply shares should be 0 after full liquidation");
        assertEq(borrowShares, 0, "borrow shares should be 0 after full liquidation");
        assertEq(collateralAssets, 0, "collateral assets should be 0 after full liquidation");

        vm.stopPrank();
    }

    function testLiquidateSixDecimalsOfCollateralTokenFuzz(uint256 ltv, uint256 depositAmount) public {
        ltv = bound(ltv, 0.6 ether, 0.8 ether);
        // reasonable deposit amount
        depositAmount = bound(depositAmount, 0.00001 * 10 ** 6, 1000_000 * 10 ** 6);

        // collateral token with 6 decimals
        collateralToken = ERC20Mock(address(new ERC20MockDecimals("Collateral Token", "CTKN", 6)));

        // creating the market with valid collateral token of 6 decimals and valid oracle price
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36 * 1e12, // 1 USD scaled by 1e12
            ltv, // LTV
            collateralToken,
            address(oracle)
        );

        deal(address(collateralToken), bob, depositAmount);
        // borrow token with 18 decimals
        deal(address(borrowToken), supplier, depositAmount * 1e12);

        vm.startPrank(supplier);
        // supplying the assets which can be used to borrow
        // borrow token has 18 decimals
        market.addSupply(depositAmount * 1e12, 0, supplier);
        vm.stopPrank();

        vm.startPrank(bob);
        // adding collateral by the borrower
        market.addCollateral(depositAmount, bob);
        // borrowing the maximum allowed amount of assets
        uint256 borrowAmount = depositAmount * ltv * 1e12 / 1 ether;
        market.borrow(borrowAmount, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(liquidator);
        (, uint128 borrowShares,) = market.position(bob);
        // asserts that borrowShares represents the correct amount of assets
        assertEq(market.borrowSharesToAmount(borrowShares), borrowAmount, "invalid borrowAmount for borrowShares");
        uint256 interestAmount = borrowAmount / 2;
        // adding interest in the market to make position underwater
        market.addInterest(interestAmount);
        market.accrueInterest();

        // increasing balance of borrow token to the liquidator to be used for liquidation
        deal(address(borrowToken), liquidator, borrowAmount + interestAmount);
        (, uint256 protocolFee) = market.calculateLiquidatorAndProtocolFee(bob, true);

        // asserts that borrowShares represents the correct amount of assets after interest is added
        assertApproxEqAbs(
            market.borrowSharesToAmount(borrowShares),
            borrowAmount + interestAmount,
            1e6,
            "invalid borrowAmount for borrowShares after interest"
        );

        // expecting the liquidation event to be emitted
        vm.expectEmit(true, false, false, false, address(market));
        emit IMarketEvents.Liquidation(bob, liquidator, 0, 0, 0, 0, 0, 0);

        uint256 borrowTokenBalanceOfLiquidatorBefore = borrowToken.balanceOf(liquidator);
        // liquidating the underwater position should always succeed
        (uint256 collateralAmount, uint256 repayAmount,) = market.liquidate(bob, hex"", hex"");

        // asserts that collateral is seized and amount repaid is greater than 0
        assertGt(collateralAmount, 0, "no collateral seized during liquidation");
        assertGt(repayAmount, 0, "no amount repaid during liquidation");

        // asserts that protocol fee is credited to fee recipient
        assertEq(
            imarket.position(FEE_RECEIVER).collateralAssets, protocolFee, "protocol fee not credited to fee recipient"
        );

        // asserts that collateral token balance of market is updated
        assertEq(
            collateralToken.balanceOf(address(market)),
            depositAmount - collateralAmount + protocolFee,
            "collateral token balance of market not updated"
        );

        // asserts that borrow token balance of liquidator is updated
        assertEq(
            borrowToken.balanceOf(liquidator),
            borrowTokenBalanceOfLiquidatorBefore - repayAmount,
            "borrow token balance of liquidator not updated"
        );

        vm.stopPrank();
    }

    function testLiquidateFailsWhenOracleReverts() public {
        // creating the market with valid collateral token of 18 decimals and valid oracle price
        // oracle will be updated with new oracle that always reverts
        createMarket(
            LiquidationConfiguration({
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
            }),
            1e36, // 1 USD
            0.75 ether, // LTV
            collateralToken,
            address(oracle)
        );

        // reasonable deposit amount
        uint256 depositAmount = 1000 ether;
        deal(address(collateralToken), bob, depositAmount);
        deal(address(borrowToken), supplier, depositAmount);

        // supplying the assets which can be used to borrow
        vm.startPrank(supplier);
        market.addSupply(depositAmount, 0, supplier);
        vm.stopPrank();

        // adding collateral by the borrower
        vm.startPrank(bob);
        market.addCollateral(depositAmount, bob);
        // borrowing the maximum allowed amount of assets
        uint256 borrowAmount = 750 ether;
        market.borrow(borrowAmount, 0, bob, bob, "");
        market.accrueInterest();
        vm.stopPrank();

        vm.startPrank(liquidator);
        // adding interest in the market to make position underwater
        uint256 interestAmount = 500 ether;
        market.addInterest(interestAmount);
        market.accrueInterest();

        // updating oracle to new oracle that always reverts
        vm.startPrank(market.owner());
        market.setOracle(address(oracleAlwaysReverts));
        vm.stopPrank();

        // expecting the liquidation to revert because oracle always reverts
        vm.expectRevert(OracleAlwaysReverts.selector);
        market.liquidate(bob, hex"", hex"");
        vm.stopPrank();
    }
}
