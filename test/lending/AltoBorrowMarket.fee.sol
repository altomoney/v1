// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {AltoBorrowMarket, LiquidationConfiguration} from "../../contracts/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "../../contracts/lending/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {OracleMock} from "../../contracts/lending/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "../../contracts/lending/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "../../contracts/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath, MATH_PRECISION} from "../../contracts/lending/libraries/FixedPointMath.sol";
import {Erc20Mock} from "../helpers/Erc20Mock.sol";
import {console2} from "forge-std/console2.sol";
import {IMarket} from "@alto-monorepo/lending/interfaces/IMarket.sol";

contract AltoBorrowMarketMock is AltoBorrowMarket {
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

    function borrowAmountToShares(uint256 amount) external view returns (uint256) {
        return amount.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);
    }

    function supplySharesToAssets(uint256 shares) external view returns (uint256) {
        return shares.convertToAssetsDown(totalSupply.assets, totalSupply.shares);
    }
}

contract AltoBorrowMarketFeeTest is Test {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    Erc20Mock borrowToken;
    Erc20Mock collateralToken;

    uint256 internal constant LTV = 0.75 ether;
    uint256 constant MIN_AMOUNT = 1000;
    uint256 constant MAX_AMOUNT = 2 ** 64;

    address internal immutable FEE_RECIPIENT = makeAddr("Fee Recipient");
    address internal immutable SUPPLIER = makeAddr("Supplier");
    address internal immutable USER = makeAddr("User");
    address internal immutable USER2 = makeAddr("User2");

    function setUp() public {
        borrowToken = new Erc20Mock("borrow", "B");
        collateralToken = new Erc20Mock("collateral", "C");

        deal(address(borrowToken), address(this), type(uint256).max);
        deal(address(collateralToken), address(this), type(uint256).max);
    }

    function _createMarketWithOpeningFee(uint256 openingFee) internal returns (AltoBorrowMarketMock) {
        address irm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address oracle = address(new OracleMock());
        OracleMock(oracle).setPrice(ORACLE_PRICE_PRECISION);

        AltoBorrowMarketMock market = new AltoBorrowMarketMock(
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
                minPenaltyPercentage: 0.01 ether
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

        AltoBorrowMarketMock market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecision(openingFee);

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
        openingFee = bound(openingFee, 0, 1000 ether);
        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, 1 ether, MAX_AMOUNT);

        AltoBorrowMarketMock market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecision(openingFee);

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
        openingFee = bound(openingFee, 0, 1000 ether);
        targetLtv = bound(targetLtv, 0.001 ether, LTV);
        amount = bound(amount, 1 ether, MAX_AMOUNT);

        AltoBorrowMarketMock market = _createMarketWithOpeningFee(openingFee);
        IMarket imarket = IMarket(address(market));

        market.addSupply(amount, 0, SUPPLIER);

        market.addCollateral(amount, USER);

        assertEq(amount, imarket.position(USER).collateralAssets);

        uint256 borrowAmount = amount.multiplyWithPrecision(targetLtv);

        // we need to subtract the opening fee from the borrow amount
        borrowAmount = borrowAmount.divideWithPrecisionDown(MATH_PRECISION + openingFee);
        uint256 feeAssets = borrowAmount.multiplyWithPrecision(openingFee);
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

    function _depositCollateralAndBorrow(
        AltoBorrowMarketMock market,
        uint256 amount,
        uint256 borrowAmount,
        address user
    ) internal returns (uint256) {
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

        AltoBorrowMarketMock market = _createMarketWithOpeningFee(openingFee);
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
