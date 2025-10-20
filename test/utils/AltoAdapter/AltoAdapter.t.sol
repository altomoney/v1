// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./AdapterCommonSetup.t.sol";

import {StakingPosition, StakingContainer} from "@alto/staking/interfaces/IAltoStaking.sol";
import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";

import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {MathRayLib} from "@morpho-org/bundler3/libraries/MathRayLib.sol";
import {Call} from "@morpho-org/bundler3/Bundler3.sol";

import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AltoAdapterTest is AdapterCommonSetup {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using MathRayLib for uint256;

    function setUp() public override {
        super.setUp();

        vm.startPrank(USER);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(altoAdapter), type(uint256).max);
        collateralToken.approve(address(altoAdapter), type(uint256).max);
        vm.stopPrank();

        vm.prank(LIQUIDATOR);
        borrowToken.approve(address(altoAdapter), type(uint256).max);
    }

    function approveERC20ToMarketAndAdapter(address user) internal {
        vm.startPrank(user);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(altoAdapter), type(uint256).max);
        collateralToken.approve(address(altoAdapter), type(uint256).max);
        vm.stopPrank();
    }

    function approvePaymentTokenToAdapter(address user) internal {
        vm.startPrank(user);
        paymentToken.approve(address(altoAdapter), type(uint256).max);
        vm.stopPrank();
    }

    function approveRewardTokenToAdapter(address user) internal {
        vm.startPrank(user);
        rewardToken.approve(address(altoAdapter), type(uint256).max);
        vm.stopPrank();
    }

    function assumeOnBehalf(address onBehalf) internal view {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(market));
        vm.assume(onBehalf != address(altoAdapter));
        vm.assume(onBehalf != address(leverage));
        vm.assume(onBehalf != address(swapper));
    }

    function testSetAuthorizationWithSig(uint256 privateKey, uint32 deadline) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, true));

        bundler3.multicall(bundle);

        assertTrue(market.isAuthorized(user, address(altoAdapter)), "isAuthorized(user, altoAdapter)");
    }

    function testSetAuthorizationWithSigRevert(uint256 privateKey, uint32 deadline) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));

        vm.expectRevert(IAuth.AuthInvalidNonce.selector);
        bundler3.multicall(bundle);
    }

    function testSupplyOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_marketAddSupply(market, assets, 0, type(uint256).max, address(altoAdapter)));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function testSupplyCollateralOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_marketAddCollateral(market, assets, address(altoAdapter)));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function testRepayOnBehalfAdapterAddress(uint256 assets) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_marketRepay(market, assets, 0, type(uint256).max, address(altoAdapter)));

        vm.expectRevert(ErrorsLib.AdapterAddress.selector);
        bundler3.multicall(bundle);
    }

    function testMarketAddSupplyNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketAddSupply(nonMarket, MIN_AMOUNT, 0, 0, USER));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testMarketRemoveSupplyNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketRemoveSupply(nonMarket, MIN_AMOUNT, 0, 0, USER));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testMarketAddCollateralNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketAddCollateral(nonMarket, MIN_AMOUNT, USER));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testMarketRemoveCollateralNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketRemoveCollateral(nonMarket, MIN_AMOUNT, USER, hex""));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testMarketBorrowNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketBorrow(nonMarket, MIN_AMOUNT, 0, 0, USER, hex""));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testMarketRepayNotApproved() public {
        IMarket nonMarket = IMarket(makeAddr("NonMarket"));

        bundle.push(_marketRepay(nonMarket, MIN_AMOUNT, 0, 0, USER));
        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function _testSupply(uint256 amount, address onBehalf) internal view {
        assertEq(collateralToken.balanceOf(USER), 0, "collateralToken.balanceOf(USER)");
        assertEq(borrowToken.balanceOf(USER), 0, "borrowToken.balanceOf(USER)");

        assertEq(collateralToken.balanceOf(onBehalf), 0, "collateralToken.balanceOf(onBehalf)");
        assertEq(borrowToken.balanceOf(onBehalf), 0, "borrowToken.balanceOf(onBehalf)");

        assertEq(market.position(onBehalf).collateralAssets, 0, "market.position(onBehalf).collateralAssets");
        assertEq(
            market.position(onBehalf).supplyShares,
            amount * AssetShareConversionMath.VIRTUAL_SHARES,
            "market.position(onBehalf).supplyShares"
        );
        assertEq(market.position(onBehalf).borrowShares, 0, "market.position(onBehalf).borrowShares");

        if (onBehalf != USER) {
            assertEq(market.position(USER).collateralAssets, 0, "market.position(USER).collateralAssets");
            assertEq(market.position(USER).supplyShares, 0, "market.position(USER).supplyShares");
            assertEq(market.position(USER).borrowShares, 0, "market.position(USER).borrowShares");
        }

        assertEq(
            borrowToken.allowance(address(altoAdapter), address(market)),
            type(uint256).max,
            "loanToken.allowance(altoAdapter, market)"
        );
    }

    function testSupply(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketAddSupply(market, amount, 0, type(uint256).max, onBehalf));

        deal(address(borrowToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupply(amount, onBehalf);
    }

    function testSupplyShares(uint256 shares, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        shares = bound(shares, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(borrowToken), type(uint128).max));
        bundle.push(_marketAddSupply(market, 0, shares, type(uint256).max, onBehalf));

        deal(address(borrowToken), USER, type(uint128).max);

        vm.prank(USER);
        bundler3.multicall(bundle);

        assertEq(market.position(onBehalf).supplyShares, shares);
    }

    function testSupplyMax(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketAddSupply(market, type(uint256).max, 0, type(uint256).max, onBehalf));

        deal(address(borrowToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupply(amount, onBehalf);
    }

    function _testSupplyCollateral(uint256 amount, address onBehalf) internal view {
        assertEq(collateralToken.balanceOf(USER), 0, "collateralToken.balanceOf(USER)");
        assertEq(borrowToken.balanceOf(USER), 0, "borrowToken.balanceOf(USER)");

        assertEq(collateralToken.balanceOf(onBehalf), 0, "collateralToken.balanceOf(onBehalf)");
        assertEq(borrowToken.balanceOf(onBehalf), 0, "borrowToken.balanceOf(onBehalf)");

        assertEq(market.position(onBehalf).collateralAssets, amount, "market.position(onBehalf).collateralAssets");
        assertEq(market.position(onBehalf).supplyShares, 0, "market.position(onBehalf).supplyShares");
        assertEq(market.position(onBehalf).borrowShares, 0, "market.position(onBehalf).borrowShares");

        if (onBehalf != USER) {
            assertEq(market.position(USER).collateralAssets, 0, "market.position(USER).collateralAssets");
            assertEq(market.position(USER).supplyShares, 0, "market.position(USER).supplyShares");
            assertEq(market.position(USER).borrowShares, 0, "market.position(USER).borrowShares");
        }
    }

    function testSupplyCollateral(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(collateralToken), amount));
        bundle.push(_marketAddCollateral(market, amount, onBehalf));

        deal(address(collateralToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupplyCollateral(amount, onBehalf);
    }

    function testSupplyCollateralMax(uint256 amount, address onBehalf) public {
        assumeOnBehalf(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_erc20TransferFrom(address(collateralToken), amount));
        bundle.push(_marketAddCollateral(market, type(uint256).max, onBehalf));

        deal(address(collateralToken), USER, amount);

        vm.prank(USER);
        bundler3.multicall(bundle);

        _testSupplyCollateral(amount, onBehalf);
    }

    function testWithdrawUnauthorized(uint256 withdrawnShares) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        altoAdapter.marketRemoveSupply(market, 0, withdrawnShares, 0, RECEIVER);
    }

    function testWithdraw(uint256 privateKey, uint256 amount, uint256 withdrawnShares) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        uint256 expectedSupplyShares = amount.convertToSharesUp(0, 0);
        withdrawnShares = bound(withdrawnShares, 1, expectedSupplyShares);
        uint256 expectedWithdrawnAmount = withdrawnShares.convertToAssetsDown(amount, expectedSupplyShares);

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRemoveSupply(market, 0, withdrawnShares, 0, user));

        deal(address(borrowToken), user, amount);

        vm.startPrank(user);
        market.addSupply(amount, 0, user);

        bundler3.multicall(bundle);
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(user), expectedWithdrawnAmount, "borrowToken.balanceOf(user)");
        assertEq(borrowToken.balanceOf(address(altoAdapter)), 0, "borrowToken.balanceOf(address(altoAdapter)");
        assertEq(
            borrowToken.balanceOf(address(market)),
            amount - expectedWithdrawnAmount,
            "borrowToken.balanceOf(address(market))"
        );

        assertEq(market.position(user).collateralAssets, 0, "market.position(user).collateralAssets");
        assertEq(
            market.position(user).supplyShares,
            expectedSupplyShares - withdrawnShares,
            "market.position(user).supplyShares"
        );
        assertEq(market.position(user).borrowShares, 0, "market.position(user).borrowShares");
    }

    function testMarketSupplyMaxAssetsZero() public {
        bundle.push(_marketAddSupply(market, type(uint256).max, 0, type(uint256).max, address(this)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMarketSupplyCollateralMaxZero() public {
        bundle.push(_marketAddCollateral(market, type(uint256).max, address(this)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMarketSupplyCollateralZero(uint256 amount) public {
        deal(address(collateralToken), address(altoAdapter), amount);
        bundle.push(_marketAddCollateral(market, 0, address(this)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMarketRepayMaxAssetsZero() public {
        bundle.push(_marketRepay(market, type(uint256).max, 0, type(uint256).max, address(this)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testMarketRepayMaxSharesZero() public {
        bundle.push(_marketRepay(market, 0, type(uint256).max, type(uint256).max, address(this)));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawZeroMaxSupply() public {
        bundle.push(_marketRemoveSupply(market, 0, type(uint256).max, 0, RECEIVER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawCollateralZero() public {
        bundle.push(_marketRemoveCollateral(market, 0, RECEIVER, hex""));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);
    }

    function testWithdrawMaxSupply(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRemoveSupply(market, 0, type(uint256).max, 0, user));

        deal(address(borrowToken), user, amount);

        vm.startPrank(user);
        market.addSupply(amount, 0, user);

        bundler3.multicall(bundle);
        vm.stopPrank();

        assertEq(borrowToken.balanceOf(user), amount, "borrowToken.balanceOf(user)");
        assertEq(borrowToken.balanceOf(address(altoAdapter)), 0, "borrowToken.balanceOf(address(altoAdapter)");
        assertEq(borrowToken.balanceOf(address(market)), 0, "borrowToken.balanceOf(address(market))");

        assertEq(market.position(user).collateralAssets, 0, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(market.position(user).borrowShares, 0, "market.position(user).borrowShares");
    }

    function testBorrowUnauthorized(uint256 borrowedAssets) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        altoAdapter.marketBorrow(market, borrowedAssets, 0, 0, RECEIVER, hex"");
    }

    function _testSupplyCollateralBorrow(address user, uint256 amount, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), 0, "collateral.balanceOf(RECEIVER)");
        assertEq(borrowToken.balanceOf(RECEIVER), amount, "borrowToken.balanceOf(RECEIVER)");

        assertEq(market.position(user).collateralAssets, collateralAmount, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(
            market.position(user).borrowShares,
            amount * AssetShareConversionMath.VIRTUAL_SHARES,
            "market.position(user).borrowShares"
        );

        if (RECEIVER != user) {
            assertEq(market.position(RECEIVER).collateralAssets, 0, "market.position(RECEIVER).collateralAssets");
            assertEq(market.position(RECEIVER).supplyShares, 0, "market.position(RECEIVER).supplyShares");
            assertEq(market.position(RECEIVER).borrowShares, 0, "market.position(RECEIVER).borrowShares");

            assertEq(collateralToken.balanceOf(user), 0, "collateral.balanceOf(user)");
            assertEq(borrowToken.balanceOf(user), 0, "borrowToken.balanceOf(user)");
        }
    }

    function testSupplyCollateralBorrow(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.divideWithPrecisionUp(LTV);

        bundle.push(_erc20TransferFrom(address(collateralToken), collateralAmount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketAddCollateral(market, collateralAmount, user));
        bundle.push(_marketBorrow(market, amount, 0, 0, RECEIVER, hex""));

        deal(address(collateralToken), user, collateralAmount);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testSupplyCollateralBorrow(user, amount, collateralAmount);
    }

    function _testSupplyCollateralBorrowLeverage(address user, uint256 amount, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(user), 0, "collateral.balanceOf(user)");
        assertEq(borrowToken.balanceOf(user), 0, "borrowToken.balanceOf(user)");

        assertEq(market.position(user).collateralAssets, collateralAmount, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(
            market.position(user).borrowShares,
            amount * AssetShareConversionMath.VIRTUAL_SHARES,
            "market.position(user).borrowShares"
        );
    }

    function testSupplyCollateralBorrowLeverage(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 maxMultiplier = MATH_PRECISION.divideWithPrecisionDown(MATH_PRECISION - LTV);
        uint256 targetCollateralAmount = amount.divideWithPrecisionUp(LTV);
        uint256 initialCollateralAmount = targetCollateralAmount.divideWithPrecisionDown(maxMultiplier);
        uint256 collateralAmountToAdd = targetCollateralAmount - initialCollateralAmount;

        bytes memory leverageData = _marketPrepareLeverageData(collateralAmountToAdd, hex"");

        bundle.push(_erc20TransferFrom(address(collateralToken), initialCollateralAmount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketAddCollateral(market, initialCollateralAmount, user));
        bundle.push(_marketBorrow(market, amount, 0, 0, address(leverage), leverageData));

        deal(address(collateralToken), user, initialCollateralAmount);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testSupplyCollateralBorrowLeverage(user, amount, targetCollateralAmount);
    }

    function testWithdrawCollateralUnauthorized(uint256 collateralAmount) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        altoAdapter.marketRemoveCollateral(market, collateralAmount, RECEIVER, hex"");
    }

    function _testRepayWithdrawCollateral(address user, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), collateralAmount, "collateralToken.balanceOf(RECEIVER)");
        assertEq(borrowToken.balanceOf(RECEIVER), 0, "borrowToken.balanceOf(RECEIVER)");

        assertEq(market.position(user).collateralAssets, 0, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(market.position(user).borrowShares, 0, "market.position(user).borrowShares");

        if (RECEIVER != user) {
            assertEq(market.position(RECEIVER).collateralAssets, 0, "market.position(RECEIVER).collateralAssets");
            assertEq(market.position(RECEIVER).supplyShares, 0, "market.position(RECEIVER).supplyShares");
            assertEq(market.position(RECEIVER).borrowShares, 0, "market.position(RECEIVER).borrowShares");

            assertEq(collateralToken.balanceOf(user), 0, "collateralToken.balanceOf(user)");
            assertEq(borrowToken.balanceOf(user), 0, "borrowToken.balanceOf(user)");
        }
    }

    function testRepayWithdrawCollateral(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.divideWithPrecisionUp(LTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        market.addCollateral(collateralAmount, user);
        market.borrow(amount, 0, user, user, "");
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRepay(market, amount, 0, type(uint256).max, user));
        bundle.push(_marketRemoveCollateral(market, collateralAmount, RECEIVER, hex""));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function _testRepayWithdrawCollateralDeleverage(
        address user,
        uint256 collateralAmount,
        uint256 borrowBalanceBefore
    ) internal view {
        assertEq(collateralToken.balanceOf(user), collateralAmount, "collateralToken.balanceOf(user)");
        assertEq(borrowToken.balanceOf(user), borrowBalanceBefore, "borrowToken.balanceOf(user)");

        assertEq(market.position(user).collateralAssets, 0, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(market.position(user).borrowShares, 0, "market.position(user).borrowShares");
    }

    function testRepayWithdrawCollateralDeleverage(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.divideWithPrecisionUp(LTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        market.addCollateral(collateralAmount, user);
        market.borrow(amount, 0, user, user, "");
        vm.stopPrank();

        bytes memory leverageData = _marketPrepareLeverageData(amount, hex"");

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRemoveCollateral(market, amount, address(leverage), leverageData));
        bundle.push(_marketRemoveCollateral(market, collateralAmount - amount, user, hex""));

        uint256 borrowBalanceBefore = borrowToken.balanceOf(user);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateralDeleverage(user, collateralAmount - amount, borrowBalanceBefore);
    }

    function testRepayMaxAndWithdrawCollateral(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.divideWithPrecisionUp(LTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        market.addCollateral(collateralAmount, user);
        market.borrow(amount, 0, user, user, "");
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRepay(market, type(uint256).max, 0, type(uint256).max, user));
        bundle.push(_marketRemoveCollateral(market, collateralAmount, RECEIVER, hex""));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function testWithdrawMaxCollateral(uint256 privateKey, uint256 collateralAmount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        collateralAmount = bound(collateralAmount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(collateralToken), user, collateralAmount);
        vm.prank(user);
        market.addCollateral(collateralAmount, user);

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRemoveCollateral(market, type(uint256).max, RECEIVER, hex""));

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(collateralToken.balanceOf(RECEIVER), collateralAmount, "collateral.balanceOf(RECEIVER)");
    }

    function testRepayMaxShares(uint256 privateKey, uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(altoAdapter));
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);
        approveERC20ToMarketAndAdapter(onBehalf);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.divideWithPrecisionUp(LTV);

        deal(address(collateralToken), onBehalf, collateralAmount);
        vm.startPrank(onBehalf);
        market.addCollateral(collateralAmount, onBehalf);
        market.borrow(amount, 0, onBehalf, address(altoAdapter), "");
        vm.stopPrank();

        bundle.push(_marketRepay(market, 0, type(uint256).max, type(uint256).max, onBehalf));

        assertGt(market.position(onBehalf).borrowShares, 0, "before: market.position(onBehalf).borrowShares");

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(borrowToken.balanceOf(user), 0, "after: borrowToken.balanceOf(user)");
        assertEq(market.position(onBehalf).borrowShares, 0, "after: market.position(onBehalf).borrowShares");
        assertEq(borrowToken.balanceOf(address(altoAdapter)), 0, "borrowToken.balanceOf(address(altoAdapter)");
        assertEq(borrowToken.balanceOf(address(market)), amount, "borrowToken.balanceOf(address(market))");
    }

    struct BundleTransactionsVars {
        uint256 expectedSupplyShares;
        uint256 expectedBorrowShares;
        uint256 expectedTotalSupply;
        uint256 expectedTotalBorrow;
        uint256 expectedCollateral;
        uint256 expectedAdapterLoanBalance;
        uint256 expectedAdapterCollateralBalance;
        uint256 initialUserLoanBalance;
        uint256 initialUserCollateralBalance;
    }

    function testBundleTransactions(uint256 privateKey, uint256 size, uint256 seedAction, uint256 seedAmount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));

        seedAction = bound(seedAction, 0, type(uint256).max - 30);
        seedAmount = bound(seedAmount, 0, type(uint256).max - 30);

        BundleTransactionsVars memory vars;

        for (uint256 i; i < size % 30; ++i) {
            uint256 actionId = uint256(keccak256(abi.encode(seedAmount + i))) % 11;
            uint256 amount = uint256(keccak256(abi.encode(seedAction + i)));
            if (actionId < 3) _addSupplyData(vars, amount, user);
            else if (actionId < 6) _addSupplyCollateralData(vars, amount, user);
            else if (actionId < 8) _addBorrowData(vars, amount);
            else if (actionId < 9) _addRepayData(vars, amount, user);
            else if (actionId < 10) _addWithdrawData(vars, amount);
            else if (actionId == 10) _addWithdrawCollateralData(vars, amount);
        }

        deal(address(borrowToken), user, vars.initialUserLoanBalance);
        deal(address(collateralToken), user, vars.initialUserCollateralBalance);

        vm.prank(user);
        bundler3.multicall(bundle);

        assertEq(market.position(user).supplyShares, vars.expectedSupplyShares, "User's supply shares");
        assertEq(market.position(user).borrowShares, vars.expectedBorrowShares, "User's borrow shares");
        assertEq(market.totalSupply().shares, vars.expectedSupplyShares, "Total supply shares");
        assertEq(market.totalBorrowed().shares, vars.expectedBorrowShares, "Total borrow shares");
        assertEq(market.totalSupply().assets, vars.expectedTotalSupply, "Total supply");
        assertEq(market.totalBorrowed().assets, vars.expectedTotalBorrow, "Total borrow");
        assertEq(market.position(user).collateralAssets, vars.expectedCollateral, "User's collateral");

        assertEq(borrowToken.balanceOf(user), 0, "User's loan balance");
        assertEq(collateralToken.balanceOf(user), 0, "User's collateral balance");
        assertEq(
            borrowToken.balanceOf(address(market)),
            vars.expectedTotalSupply - vars.expectedTotalBorrow,
            "User's loan balance"
        );
        assertEq(collateralToken.balanceOf(address(market)), vars.expectedCollateral, "Market's collateral balance");
        assertEq(
            borrowToken.balanceOf(address(altoAdapter)),
            vars.expectedAdapterLoanBalance,
            unicode"Adapter's loan balance"
        );
        assertEq(
            collateralToken.balanceOf(address(altoAdapter)),
            vars.expectedAdapterCollateralBalance,
            "Adapter's collateral balance"
        );
    }

    function _addSupplyData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        amount = bound(amount % MAX_AMOUNT, MIN_AMOUNT, MAX_AMOUNT);

        _transferMissingLoan(vars, amount);

        bundle.push(_marketAddSupply(market, amount, 0, type(uint256).max, user));
        vars.expectedAdapterLoanBalance -= amount;

        uint256 expectedAddedSupplyShares =
            amount.convertToSharesDown(vars.expectedTotalSupply, vars.expectedSupplyShares);
        vars.expectedTotalSupply += amount;
        vars.expectedSupplyShares += expectedAddedSupplyShares;
    }

    function _addSupplyCollateralData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        amount = bound(amount % MAX_AMOUNT, MIN_AMOUNT, MAX_AMOUNT);

        _transferMissingCollateral(vars, amount);

        bundle.push(_marketAddCollateral(market, amount, user));
        vars.expectedAdapterCollateralBalance -= amount;

        vars.expectedCollateral += amount;
    }

    function _addWithdrawData(BundleTransactionsVars memory vars, uint256 amount) internal {
        uint256 availableLiquidity = vars.expectedTotalSupply - vars.expectedTotalBorrow;
        if (availableLiquidity == 0 || vars.expectedSupplyShares == 0) return;

        uint256 supplyBalance =
            vars.expectedSupplyShares.convertToAssetsDown(vars.expectedTotalSupply, vars.expectedSupplyShares);

        uint256 maxAmount = Math.min(supplyBalance, availableLiquidity);
        amount = bound(amount % maxAmount, 1, maxAmount);

        bundle.push(_marketRemoveSupply(market, amount, 0, 0, address(altoAdapter)));
        vars.expectedAdapterLoanBalance += amount;

        uint256 expectedDecreasedSupplyShares =
            amount.convertToSharesUp(vars.expectedTotalSupply, vars.expectedSupplyShares);
        vars.expectedTotalSupply -= amount;
        vars.expectedSupplyShares -= expectedDecreasedSupplyShares;
    }

    function _addBorrowData(BundleTransactionsVars memory vars, uint256 shares) internal {
        uint256 availableLiquidity = vars.expectedTotalSupply - vars.expectedTotalBorrow;
        if (availableLiquidity == 0 || vars.expectedCollateral == 0) return;

        uint256 totalBorrowPower = vars.expectedCollateral.multiplyWithPrecision(LTV);

        uint256 borrowed =
            vars.expectedBorrowShares.convertToAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 currentBorrowPower = totalBorrowPower - borrowed;
        if (currentBorrowPower == 0) return;

        uint256 maxShares = Math.min(currentBorrowPower, availableLiquidity)
            .convertToSharesDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        if (maxShares < MIN_AMOUNT) return;
        shares = bound(shares % maxShares, MIN_AMOUNT, maxShares);

        bundle.push(_marketBorrow(market, 0, shares, 0, address(altoAdapter), hex""));
        uint256 expectedBorrowedAmount = shares.convertToAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedAdapterLoanBalance += expectedBorrowedAmount;

        vars.expectedTotalBorrow += expectedBorrowedAmount;
        vars.expectedBorrowShares += shares;
    }

    function _addRepayData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        if (vars.expectedBorrowShares == 0) return;

        uint256 borrowBalance =
            vars.expectedBorrowShares.convertToAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        amount = bound(amount % borrowBalance, 1, borrowBalance);

        _transferMissingLoan(vars, amount);

        bundle.push(_marketRepay(market, amount, 0, type(uint256).max, user));
        vars.expectedAdapterLoanBalance -= amount;

        uint256 expectedDecreasedBorrowShares =
            amount.convertToSharesDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedTotalBorrow -= amount;
        vars.expectedBorrowShares -= expectedDecreasedBorrowShares;
    }

    function _addWithdrawCollateralData(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (vars.expectedCollateral == 0) return;

        uint256 borrowPower = vars.expectedCollateral.multiplyWithPrecision(LTV);
        uint256 borrowed =
            vars.expectedBorrowShares.convertToAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 withdrawableCollateral = (borrowPower - borrowed).divideWithPrecisionDown(LTV);
        if (withdrawableCollateral == 0) return;

        amount = bound(amount % withdrawableCollateral, 1, withdrawableCollateral);

        bundle.push(_marketRemoveCollateral(market, amount, address(altoAdapter), hex""));
        vars.expectedAdapterCollateralBalance += amount;

        vars.expectedCollateral -= amount;
    }

    function _transferMissingLoan(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (amount > vars.expectedAdapterLoanBalance) {
            uint256 missingAmount = amount - vars.expectedAdapterLoanBalance;
            bundle.push(_erc20TransferFrom(address(borrowToken), missingAmount));
            vars.initialUserLoanBalance += missingAmount;
            vars.expectedAdapterLoanBalance += missingAmount;
        }
    }

    function _transferMissingCollateral(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (amount > vars.expectedAdapterCollateralBalance) {
            uint256 missingAmount = amount - vars.expectedAdapterCollateralBalance;
            bundle.push(_erc20TransferFrom(address(collateralToken), missingAmount));
            vars.initialUserCollateralBalance += missingAmount;
            vars.expectedAdapterCollateralBalance += missingAmount;
        }
    }

    function testSlippageSupplyOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);

        deal(address(borrowToken), address(altoAdapter), assets);

        bundle.push(_marketAddSupply(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageSupplyKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);

        deal(address(borrowToken), address(altoAdapter), assets);

        bundle.push(_marketAddSupply(market, assets, 0, sharePriceE27, address(this)));
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares));

        deal(address(borrowToken), address(this), assets);
        market.addSupply(assets, 0, address(this));
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketRemoveSupply(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivDown(shares) + 1, type(uint256).max);

        deal(address(borrowToken), address(this), assets);
        market.addSupply(assets, 0, address(this));
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketRemoveSupply(market, assets, 0, sharePriceE27, address(this)));
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);
    }

    function testSlippageBorrowOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivDown(shares));
        uint256 collateral = assets.divideWithPrecisionUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketBorrow(market, assets, 0, sharePriceE27, address(this), hex""));
        bundler3.multicall(bundle);
    }

    function testSlippageBorrowKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivDown(shares) + 1, type(uint256).max);
        uint256 collateral = assets.divideWithPrecisionUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.setAuthorization(address(altoAdapter), true);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_marketBorrow(market, assets, 0, sharePriceE27, address(this), hex""));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);
        uint256 collateral = assets.divideWithPrecisionUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.borrow(assets, 0, address(this), address(altoAdapter), "");

        bundle.push(_marketRepay(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.convertToSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);
        uint256 collateral = assets.divideWithPrecisionUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.borrow(assets, 0, address(this), address(altoAdapter), "");

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_marketRepay(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    /*//////////////////////////////////////////////////////////////
                        UNWRAP NATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUnwrapNativeRevertWhenAmountMaxAndAdapterHasZeroWrappedBalance() public {
        vm.startPrank(USER);

        // Ensure adapter has zero wrapped balance
        assertEq(altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter)), 0);

        bundle.push(_unwrapNative(type(uint256).max, USER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function testUnwrapNativeRevertWhenAmountIsZero() public {
        vm.startPrank(USER);

        bundle.push(_unwrapNative(0, USER));

        vm.expectRevert(ErrorsLib.ZeroAmount.selector);
        bundler3.multicall(bundle);

        vm.stopPrank();
    }

    function testUnwrapNativeWithSpecifiedAmountAndAdapterReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 1 ether;

        // Give ETH to USER, deposit to WETH, then transfer WETH to adapter
        vm.deal(USER, amount);
        altoAdapter.WRAPPED_NATIVE().deposit{value: amount}();
        altoAdapter.WRAPPED_NATIVE().transfer(address(altoAdapter), amount);

        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;

        bundle.push(_unwrapNative(amount, address(altoAdapter)));
        bundler3.multicall(bundle);

        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;

        assertEq(adapterWrappedBalanceAfter, adapterWrappedBalanceBefore - amount);
        assertEq(adapterNativeBalanceAfter, adapterNativeBalanceBefore + amount);

        vm.stopPrank();
    }

    function testUnwrapNativeWithSpecifiedAmountAndExternalReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 1 ether;

        // Give ETH to USER, deposit to WETH, then transfer WETH to adapter
        vm.deal(USER, amount);
        altoAdapter.WRAPPED_NATIVE().deposit{value: amount}();
        altoAdapter.WRAPPED_NATIVE().transfer(address(altoAdapter), amount);

        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 receiverNativeBalanceBefore = RECEIVER.balance;

        bundle.push(_unwrapNative(amount, RECEIVER));
        bundler3.multicall(bundle);

        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 receiverNativeBalanceAfter = RECEIVER.balance;

        assertEq(adapterWrappedBalanceAfter, adapterWrappedBalanceBefore - amount);
        assertEq(receiverNativeBalanceAfter, receiverNativeBalanceBefore + amount);

        vm.stopPrank();
    }

    function testUnwrapNativeWithMaxAmountAndAdapterReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 2 ether;

        // Give ETH to USER, deposit to WETH, then transfer WETH to adapter
        vm.deal(USER, amount);
        altoAdapter.WRAPPED_NATIVE().deposit{value: amount}();
        altoAdapter.WRAPPED_NATIVE().transfer(address(altoAdapter), amount);

        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 adapterNativeBalanceBefore = address(altoAdapter).balance;

        bundle.push(_unwrapNative(type(uint256).max, address(altoAdapter)));
        bundler3.multicall(bundle);

        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 adapterNativeBalanceAfter = address(altoAdapter).balance;

        assertEq(adapterWrappedBalanceAfter, 0);
        assertEq(adapterNativeBalanceAfter, adapterNativeBalanceBefore + amount);

        vm.stopPrank();
    }

    function testUnwrapNativeWithMaxAmountAndExternalReceiver() public {
        vm.startPrank(USER);

        uint256 amount = 2 ether;

        // Give ETH to USER, deposit to WETH, then transfer WETH to adapter
        vm.deal(USER, amount);
        altoAdapter.WRAPPED_NATIVE().deposit{value: amount}();
        altoAdapter.WRAPPED_NATIVE().transfer(address(altoAdapter), amount);

        uint256 adapterWrappedBalanceBefore = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 receiverNativeBalanceBefore = RECEIVER.balance;

        bundle.push(_unwrapNative(type(uint256).max, RECEIVER));
        bundler3.multicall(bundle);

        uint256 adapterWrappedBalanceAfter = altoAdapter.WRAPPED_NATIVE().balanceOf(address(altoAdapter));
        uint256 receiverNativeBalanceAfter = RECEIVER.balance;

        assertEq(adapterWrappedBalanceAfter, 0);
        assertEq(receiverNativeBalanceAfter, receiverNativeBalanceBefore + amount);

        vm.stopPrank();
    }

    function _unwrapNative(uint256 amount, address receiver) internal view returns (Call memory) {
        return _call(altoAdapter, abi.encodeCall(altoAdapter.unwrapNative, (amount, receiver)));
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorRevertWhenWNativeIsZeroAddress() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new AltoAdapter(address(bundler3), address(0), OWNER);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS DISTRIBUTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testRewardsDistributorClaimWithERC20TransferNotApproved() public {
        IRewardsDistributor nonRewards = IRewardsDistributor(makeAddr("NonRewardsDistributor"));

        bytes32[] memory proof;
        bundle.push(
            _rewardsDistributorClaimRewardTokensWithERC20Transfer(
                nonRewards, 0, proof, 0, 0, address(paymentToken), 0, false, 0
            )
        );

        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testClaimRewardTokens(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approvePaymentTokenToAdapter(user);

        amount = bound(amount, MIN_AMOUNT, USER_AVAILABLE);

        // Fund user with payment tokens for purchasing rewards
        deal(address(paymentToken), user, 100000 ether);

        uint256 paymentBalanceUserBefore = paymentToken.balanceOf(user);
        uint256 paymentBalanceRewardsDistributorBefore = paymentToken.balanceOf(address(rewardsDistributor));

        assertEq(paymentBalanceUserBefore, 100000 ether);
        assertEq(paymentBalanceRewardsDistributorBefore, 0);

        // Create a merkle tree for this specific user
        bytes32[] memory proof = _createMerkleProofForUser(user);

        // Use signature-based authorization
        bundle.push(
            _rewardsDistributorSetAuthorizationWithSig(
                rewardsDistributor, privateKey, true, 0, false, address(altoAdapter)
            )
        );

        // We don't need to to bundle.push(_erc20TransferFrom(address(paymentToken), 100000 ether));
        // because we are using rewardsDistributorClaimRewardTokensWithERC20Transfer
        // which will transfer the exact amount of payment tokens
        bundle.push(
            _rewardsDistributorClaimRewardTokensWithERC20Transfer(
                rewardsDistributor,
                USER_AVAILABLE,
                proof,
                amount,
                BASE_DISCOUNT,
                address(paymentToken),
                100000 ether,
                false,
                0
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        uint256 paymentBalanceUserAfter = paymentToken.balanceOf(user);
        uint256 paymentBalanceRewardsDistributorAfter = paymentToken.balanceOf(address(rewardsDistributor));

        // Verify the user has received the payment tokens not used for purchasing rewards (100000 ether is burtal overpayment)
        assertEq(paymentBalanceUserAfter, 100000 ether - paymentBalanceRewardsDistributorAfter);
        // Verify the rewards distributor has received the payment tokens
        assertGt(paymentBalanceRewardsDistributorAfter, 0);

        // Verify the user received reward tokens
        assertGt(rewardToken.balanceOf(user), 0, "User should have received reward tokens");
    }

    function testClaimRewardTokensWithStaking(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approvePaymentTokenToAdapter(user);

        amount = bound(amount, MIN_AMOUNT, USER_AVAILABLE);

        // Fund user with payment tokens for purchasing rewards
        deal(address(paymentToken), user, 100000 ether);

        uint256 paymentBalanceUserBefore = paymentToken.balanceOf(user);
        uint256 paymentBalanceRewardsDistributorBefore = paymentToken.balanceOf(address(rewardsDistributor));

        assertEq(paymentBalanceUserBefore, 100000 ether);
        assertEq(paymentBalanceRewardsDistributorBefore, 0);

        // Create a merkle tree for this specific user
        bytes32[] memory proof = _createMerkleProofForUser(user);

        // Use signature-based authorization
        bundle.push(
            _rewardsDistributorSetAuthorizationWithSig(
                rewardsDistributor, privateKey, true, 0, false, address(altoAdapter)
            )
        );
        bundle.push(
            _stakingSetAuthorizationWithSig(stakingContract, privateKey, true, 0, false, address(rewardsDistributor))
        );
        // We don't need to to bundle.push(_erc20TransferFrom(address(paymentToken), 100000 ether));
        // because we are using rewardsDistributorClaimRewardTokensWithERC20Transfer
        // which will transfer the exact amount of payment tokens
        bundle.push(
            _rewardsDistributorClaimRewardTokensWithERC20Transfer(
                rewardsDistributor,
                USER_AVAILABLE,
                proof,
                amount,
                BASE_DISCOUNT,
                address(paymentToken),
                100000 ether,
                true,
                1000
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        uint256 paymentBalanceUserAfter = paymentToken.balanceOf(user);
        uint256 paymentBalanceRewardsDistributorAfter = paymentToken.balanceOf(address(rewardsDistributor));

        assertEq(paymentBalanceUserAfter, 100000 ether - paymentBalanceRewardsDistributorAfter);
        assertGt(paymentBalanceRewardsDistributorAfter, 0);

        // Verify the user has not received reward tokens
        assertEq(rewardToken.balanceOf(user), 0, "User should have received reward tokens");

        // Verify that staking contract has received the reward tokens
        assertEq(
            rewardToken.balanceOf(address(stakingContract)),
            amount,
            "Staking contract should have received the reward tokens"
        );

        // Verify that staking position was created
        uint256 containerId = stakingContract.maxMultiplierStakingContainerId();
        StakingContainer memory container = stakingContract.stakingContainerById(containerId);
        assertEq(container.multiplier, 0.6 ether, "Container multiplier should be the max multiplier");
        assertEq(containerId, 1, "Container id should be the max multiplier container");
        StakingPosition memory position = stakingContract.getPosition(user, containerId);
        assertEq(position.amountLocked, amount, "Position should have the correct amount locked");
    }

    function _createMerkleProofForUser(address user) internal returns (bytes32[] memory) {
        // Create a simple single-leaf merkle tree for this specific user
        bytes32 userLeaf = keccak256(bytes.concat(keccak256(abi.encode(user, USER_AVAILABLE, BASE_DISCOUNT))));

        // Update the rewards distributor with this new root
        vm.startPrank(OWNER);
        AltoRewardsDistributor(address(rewardsDistributor)).submitNewPendingRoot(userLeaf, bytes32(0));
        AltoRewardsDistributor(address(rewardsDistributor)).acceptPendingRoot(userLeaf);
        vm.stopPrank();

        // Return empty proof for single-leaf tree
        bytes32[] memory emptyProof = new bytes32[](0);
        return emptyProof;
    }

    /*//////////////////////////////////////////////////////////////
                        STAKING TESTS
    //////////////////////////////////////////////////////////////*/

    function testStakingLockNotApproved() public {
        IAltoStaking nonStaking = IAltoStaking(makeAddr("NonStaking"));

        bundle.push(_stakingLock(nonStaking, 1, 1, false, 1));

        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testStakingUnlockNotApproved() public {
        IAltoStaking nonStaking = IAltoStaking(makeAddr("NonStaking"));

        bundle.push(_stakingUnlock(nonStaking, USER, 1));

        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testStakingLock(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveRewardTokenToAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // Fund user with payment tokens for purchasing rewards
        deal(address(rewardToken), user, amount);

        bundle.push(_erc20TransferFrom(address(rewardToken), amount));
        bundle.push(_stakingSetAuthorizationWithSig(stakingContract, privateKey, true, 0, false, address(altoAdapter)));
        bundle.push(_stakingLock(stakingContract, amount, 1, false, 1000));

        vm.prank(user);
        bundler3.multicall(bundle);

        // Verify that staking position was created
        StakingPosition memory position = stakingContract.getPosition(user, 1);
        assertEq(position.amountLocked, amount, "Position should have the correct amount locked");
    }

    function testStakingUnlock(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveRewardTokenToAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        // Fund user with payment tokens for purchasing rewards
        deal(address(rewardToken), user, amount);

        bundle.push(_erc20TransferFrom(address(rewardToken), amount));
        bundle.push(_stakingSetAuthorizationWithSig(stakingContract, privateKey, true, 0, false, address(altoAdapter)));
        bundle.push(_stakingLock(stakingContract, amount, 1, false, 1000));

        vm.prank(user);
        bundler3.multicall(bundle);

        delete bundle;

        StakingPosition memory positionBefore = stakingContract.getPosition(user, 1);
        vm.warp(positionBefore.expiryTimestamp + 1);

        bundle.push(_stakingUnlock(stakingContract, user, 1));
        vm.prank(user);
        bundler3.multicall(bundle);

        // Verify that staking position was created
        StakingPosition memory position = stakingContract.getPosition(user, 1);
        assertEq(position.amountLocked, 0, "Position should have the correct amount locked");
        assertEq(position.expiryTimestamp, 0, "Position should have the correct expiry timestamp");
        assertEq(position.lockedTimestamp, 0, "Position should have the correct locked timestamp");
    }

    /*//////////////////////////////////////////////////////////////
                        UNIVERSAL REWARDS DISTRIBUTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testUniversalRewardsDistributorClaimNotApproved() public {
        IUniversalRewardsDistributor nonUniversal =
            IUniversalRewardsDistributor(makeAddr("NonUniversalRewardsDistributor"));

        bytes32[] memory proof;
        bundle.push(_universalRewardsDistributorClaimRewardTokens(nonUniversal, address(rewardToken), 0, proof));

        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testClaimRewardTokensUniversalRewardsDistributor(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        amount = bound(amount, MIN_AMOUNT, USER_AVAILABLE);
        deal(address(rewardToken), address(universalRewardsDistributor), amount);

        // Create a merkle tree for this specific user
        bytes32[] memory proof = _createMerkleProofForUserUniversalRewardsDistributor(user, amount);

        bundle.push(
            _universalRewardsDistributorSetAuthorizationWithSig(
                universalRewardsDistributor, privateKey, true, 0, false, address(altoAdapter)
            )
        );
        bundle.push(
            _universalRewardsDistributorClaimRewardTokens(
                universalRewardsDistributor, address(rewardToken), amount, proof
            )
        );

        vm.prank(user);
        bundler3.multicall(bundle);

        // Verify the user received reward tokens
        assertGt(rewardToken.balanceOf(user), 0, "User should have received reward tokens");
    }

    function _createMerkleProofForUserUniversalRewardsDistributor(address user, uint256 amount)
        internal
        returns (bytes32[] memory)
    {
        // Create a simple single-leaf merkle tree for this specific user
        bytes32 userLeaf = keccak256(bytes.concat(keccak256(abi.encode(user, address(rewardToken), amount))));

        // Update the rewards distributor with this new root
        vm.startPrank(OWNER);
        UniversalRewardsDistributorInstance(address(universalRewardsDistributor))
            .submitNewPendingRoot(userLeaf, bytes32(0));
        UniversalRewardsDistributorInstance(address(universalRewardsDistributor)).acceptPendingRoot(userLeaf);
        vm.stopPrank();

        // Return empty proof for single-leaf tree
        bytes32[] memory emptyProof = new bytes32[](0);
        return emptyProof;
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testVestingClaimNotApproved() public {
        IAltoVesting nonVesting = IAltoVesting(makeAddr("NonVesting"));

        VestingInfo memory vestingInfo =
            VestingInfo({startAt: block.timestamp, vestingDuration: VESTING_DURATION, totalVestingAmount: 0});
        bytes32[] memory proof;

        bundle.push(_claimVestedTokens(nonVesting, USER, vestingInfo, proof));

        vm.expectRevert(AdapterContractApproval.AdapterContractApprovalUnapprovedContract.selector);
        bundler3.multicall(bundle);
    }

    function testClaimVestedTokensVesting(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        amount = bound(amount, MIN_AMOUNT, USER_AVAILABLE);
        deal(address(rewardToken), address(vestingContract), amount);

        // Create a merkle tree for this specific user
        (VestingInfo memory vestingInfo, bytes32[] memory proof) = _createMerkleProofForUserVesting(user, amount);

        bundle.push(_vestingSetAuthorizationWithSig(vestingContract, privateKey, true, 0, false, address(altoAdapter)));
        bundle.push(_claimVestedTokens(vestingContract, user, vestingInfo, proof));

        vm.warp(block.timestamp + VESTING_DURATION);

        vm.prank(user);
        bundler3.multicall(bundle);

        // Verify the user received reward tokens
        assertEq(rewardToken.balanceOf(user), amount, "User should have received reward tokens");
    }

    function _createMerkleProofForUserVesting(address user, uint256 amount)
        internal
        returns (VestingInfo memory, bytes32[] memory)
    {
        VestingInfo memory vestingInfo = VestingInfo({
            startAt: block.timestamp, vestingDuration: VESTING_DURATION, totalVestingAmount: amount
        });
        // Create a simple single-leaf merkle tree for this specific user
        bytes32 userLeaf = keccak256(bytes.concat(keccak256(abi.encode(user, vestingInfo))));

        // Update the vesting contract with this new root
        vm.startPrank(OWNER);
        VestingInstance(address(vestingContract)).submitNewPendingRoot(userLeaf, bytes32(0));
        VestingInstance(address(vestingContract)).acceptPendingRoot(userLeaf);
        vm.stopPrank();

        // Return empty proof for single-leaf tree
        bytes32[] memory emptyProof = new bytes32[](0);
        return (vestingInfo, emptyProof);
    }
}
