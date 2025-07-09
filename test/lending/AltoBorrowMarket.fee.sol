// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC20Mock} from "../helpers/ERC20Mock.sol";
import {console2} from "forge-std/console2.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {MockMarketDeployer, MockMarket} from "@alto-test/helpers/MockMarket.sol";

contract AltoBorrowMarketFeeTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    ERC20Mock borrowToken;
    ERC20Mock collateralToken;

    uint256 internal constant LTV = 0.75 ether;
    uint256 constant MIN_AMOUNT = 1000;
    uint256 constant MAX_AMOUNT = 2 ** 64;

    address internal immutable FEE_RECIPIENT = makeAddr("Fee Recipient");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable USER = makeAddr("User");
    address internal immutable USER2 = makeAddr("User2");

    function setUp() public {
        borrowToken = new ERC20Mock("borrow", "B");
        collateralToken = new ERC20Mock("collateral", "C");

        deal(address(borrowToken), address(this), type(uint256).max);
        deal(address(collateralToken), address(this), type(uint256).max);
    }

    function _createMarketWithOpeningFee(uint256 openingFee) internal returns (MockMarket) {
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        MockMarket market = MockMarketDeployer.deployMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            address(this),
            address(oracle),
            LTV,
            openingFee,
            FEE_RECIPIENT,
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
            })
        );

        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);

        vm.prank(USER);
        market.setAuthorization(address(this), true);

        vm.prank(USER2);
        market.setAuthorization(address(this), true);

        vm.prank(SUPPLIER);
        market.setAuthorization(address(this), true);

        return market;
    }

    function test_borrowOpeningFeeAssets() public {
        uint256 openingFee = 0.05 ether; // 5%
        uint256 amount = 10 ether;
        uint256 borrowAmount = 5 ether;

        MockMarket market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecisionUp(openingFee);

        market.borrow(borrowAmount, 0, USER, USER, "");

        uint256 supplyFeeAssets = uint256(imarket.position(FEE_RECIPIENT).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the fee recipient should have the same amount of assets as what was created by the opening fee
        assertEq(feeAssets, supplyFeeAssets);

        uint256 supplyAssetsSupplier = uint256(imarket.position(SUPPLIER).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the supplier should have the same amount of assets as the initial amount
        assertEq(supplyAssetsSupplier, amount);
    }

    function testFuzz_borrowOpeningFeeAssets(uint256 amount, uint256 targetLtv, uint256 openingFee) public {
        openingFee = bound(openingFee, 0, 1 ether);
        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, 1 ether, MAX_AMOUNT);

        MockMarket market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecisionUp(openingFee);

        market.borrow(borrowAmount, 0, USER, USER, "");

        uint256 supplyFeeAssets = uint256(imarket.position(FEE_RECIPIENT).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the fee recipient should have the same amount of assets as what was created by the opening fee
        assertEq(feeAssets, supplyFeeAssets);

        uint256 supplyAssetsSupplier = uint256(imarket.position(SUPPLIER).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the supplier should have the same amount of assets as the initial amount
        assertEq(amount, supplyAssetsSupplier);
    }

    function testFuzz_borrowOpeningFeeShares(uint256 amount, uint256 targetLtv, uint256 openingFee) public {
        openingFee = bound(openingFee, 0, 1 ether);
        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, 1 ether, MAX_AMOUNT);

        MockMarket market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecisionUp(openingFee);
        uint256 borrowShares =
            borrowAmount.convertToSharesUp(imarket.totalBorrowed().assets, imarket.totalBorrowed().shares);

        market.borrow(0, borrowShares, USER, USER, "");

        uint256 supplyFeeAssets = uint256(imarket.position(FEE_RECIPIENT).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the fee recipient should have the same amount of assets as what was created by the opening fee
        assertEq(feeAssets, supplyFeeAssets);

        uint256 supplyAssetsSupplier = uint256(imarket.position(SUPPLIER).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the supplier should have the same amount of assets as the initial amount
        assertEq(amount, supplyAssetsSupplier);
    }

    function _depositCollateralAndBorrow(MockMarket market, uint256 amount, uint256 borrowAmount, address user)
        internal
        returns (uint256)
    {
        IMarket imarket = IMarket(address(market));
        uint256 openingFee = market.borrowOpeningFee();

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, user);

        assertEq(amount, imarket.position(user).collateralAssets);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecision(openingFee);

        market.borrow(borrowAmount, 0, user, user, "");

        return feeAssets;
    }

    function test_borrowOpeningFeeAssetsMultipleUsers() public {
        uint256 openingFee = 0.05 ether; // 5%

        MockMarket market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        uint256 feeAssets = _depositCollateralAndBorrow(market, 10 ether, 5 ether, USER);
        vm.warp(block.timestamp + 1 days);
        uint256 feeAssets2 = _depositCollateralAndBorrow(market, 3 ether, 2 ether, USER2);

        uint256 supplyFeeAssets = uint256(imarket.position(FEE_RECIPIENT).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the fee recipient should have the same amount of assets as what was created by the opening fee
        // approximate to account for the interest accrued
        assertApproxEqRel(feeAssets + feeAssets2, supplyFeeAssets, 0.001 ether);

        uint256 supplyAssetsSupplier = uint256(imarket.position(SUPPLIER).supplyShares).convertToAssetsDown(
            imarket.totalSupply().assets, imarket.totalSupply().shares
        );

        // the supplier should have the same amount of assets as the initial amount
        // approximate to account for the interest accrued
        assertApproxEqRel(supplyAssetsSupplier, 13 ether, 0.01 ether);
    }
}
