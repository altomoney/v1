// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./AdapterCommonSetup.t.sol";

import {ErrorsLib as ErrorsLibMarket} from "@alto-monorepo/lending/libraries/ErrorsLib.sol";
import {Position} from "@alto-monorepo/lending/interfaces/IMarket.sol";
import {IAuth} from "@alto-monorepo/utils/interfaces/common/IAuth.sol";

import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {MathRayLib} from "@morpho-org/bundler3/libraries/MathRayLib.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {UtilsLib as MorphoUtilsLib} from "@morpho-blue/libraries/UtilsLib.sol";

contract AltoAdapterTest is AdapterCommonSetup {
    using MathLib for uint256;
    using SharesMathLib for uint256;
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

    function assumeOnBehalf(address onBehalf) internal view {
        vm.assume(onBehalf != address(0));
        vm.assume(onBehalf != address(market));
        vm.assume(onBehalf != address(altoAdapter));
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

        vm.expectRevert(IAuth.INVALID_NONCE.selector);
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

    function _testSupply(uint256 amount, address onBehalf) internal view {
        assertEq(collateralToken.balanceOf(USER), 0, "collateralToken.balanceOf(USER)");
        assertEq(borrowToken.balanceOf(USER), 0, "borrowToken.balanceOf(USER)");

        assertEq(collateralToken.balanceOf(onBehalf), 0, "collateralToken.balanceOf(onBehalf)");
        assertEq(borrowToken.balanceOf(onBehalf), 0, "borrowToken.balanceOf(onBehalf)");

        assertEq(market.position(onBehalf).collateralAssets, 0, "market.position(onBehalf).collateralAssets");
        assertEq(
            market.position(onBehalf).supplyShares,
            amount * SharesMathLib.VIRTUAL_SHARES,
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
        uint256 expectedSupplyShares = amount.toSharesDown(0, 0);
        withdrawnShares = bound(withdrawnShares, 1, expectedSupplyShares);
        uint256 expectedWithdrawnAmount = withdrawnShares.toAssetsDown(amount, expectedSupplyShares);

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
        bundle.push(_marketRemoveCollateral(market, 0, RECEIVER));

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
        altoAdapter.marketBorrow(market, borrowedAssets, 0, 0, RECEIVER);
    }

    function _testSupplyCollateralBorrow(address user, uint256 amount, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), 0, "collateral.balanceOf(RECEIVER)");
        assertEq(borrowToken.balanceOf(RECEIVER), amount, "borrowToken.balanceOf(RECEIVER)");

        assertEq(market.position(user).collateralAssets, collateralAmount, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(
            market.position(user).borrowShares,
            amount * SharesMathLib.VIRTUAL_SHARES,
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

        uint256 collateralAmount = amount.wDivUp(LTV);

        bundle.push(_erc20TransferFrom(address(collateralToken), collateralAmount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketAddCollateral(market, collateralAmount, user));
        bundle.push(_marketBorrow(market, amount, 0, 0, RECEIVER));

        deal(address(collateralToken), user, collateralAmount);

        vm.prank(user);
        bundler3.multicall(bundle);

        _testSupplyCollateralBorrow(user, amount, collateralAmount);
    }

    function testWithdrawCollateralUnauthorized(uint256 collateralAmount) public {
        vm.expectRevert(ErrorsLib.UnauthorizedSender.selector);
        altoAdapter.marketRemoveCollateral(market, collateralAmount, RECEIVER);
    }

    function _testRepayWithdrawCollateral(address user, uint256 collateralAmount) internal view {
        assertEq(collateralToken.balanceOf(RECEIVER), collateralAmount, "collateral.balanceOf(RECEIVER)");
        assertEq(borrowToken.balanceOf(RECEIVER), 0, "borrowToken.balanceOf(RECEIVER)");

        assertEq(market.position(user).collateralAssets, 0, "market.position(user).collateralAssets");
        assertEq(market.position(user).supplyShares, 0, "market.position(user).supplyShares");
        assertEq(market.position(user).borrowShares, 0, "market.position(user).borrowShares");

        if (RECEIVER != user) {
            assertEq(market.position(RECEIVER).collateralAssets, 0, "market.position(RECEIVER).collateralAssets");
            assertEq(market.position(RECEIVER).supplyShares, 0, "market.position(RECEIVER).supplyShares");
            assertEq(market.position(RECEIVER).borrowShares, 0, "market.position(RECEIVER).borrowShares");

            assertEq(collateralToken.balanceOf(user), 0, "collateral.balanceOf(user)");
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

        uint256 collateralAmount = amount.wDivUp(LTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        market.addCollateral(collateralAmount, user);
        market.borrow(amount, 0, user, user);
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRepay(market, amount, 0, type(uint256).max, user));
        bundle.push(_marketRemoveCollateral(market, collateralAmount, RECEIVER));

        vm.prank(user);
        bundler3.multicall(bundle);

        _testRepayWithdrawCollateral(user, collateralAmount);
    }

    function testRepayMaxAndWithdrawCollateral(uint256 privateKey, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        approveERC20ToMarketAndAdapter(user);

        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        deal(address(borrowToken), address(this), amount);
        market.addSupply(amount, 0, SUPPLIER);

        uint256 collateralAmount = amount.wDivUp(LTV);

        deal(address(collateralToken), user, collateralAmount);
        vm.startPrank(user);
        market.addCollateral(collateralAmount, user);
        market.borrow(amount, 0, user, user);
        vm.stopPrank();

        bundle.push(_erc20TransferFrom(address(borrowToken), amount));
        bundle.push(_marketSetAuthorizationWithSig(market, privateKey, true, 0, false));
        bundle.push(_marketRepay(market, type(uint256).max, 0, type(uint256).max, user));
        bundle.push(_marketRemoveCollateral(market, collateralAmount, RECEIVER));

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
        bundle.push(_marketRemoveCollateral(market, type(uint256).max, RECEIVER));

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

        uint256 collateralAmount = amount.wDivUp(LTV);

        deal(address(collateralToken), onBehalf, collateralAmount);
        vm.startPrank(onBehalf);
        market.addCollateral(collateralAmount, onBehalf);
        market.borrow(amount, 0, onBehalf, address(altoAdapter));
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

        uint256 expectedAddedSupplyShares = amount.toSharesDown(vars.expectedTotalSupply, vars.expectedSupplyShares);
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
            vars.expectedSupplyShares.toAssetsDown(vars.expectedTotalSupply, vars.expectedSupplyShares);

        uint256 maxAmount = MorphoUtilsLib.min(supplyBalance, availableLiquidity);
        amount = bound(amount % maxAmount, 1, maxAmount);

        bundle.push(_marketRemoveSupply(market, amount, 0, 0, address(altoAdapter)));
        vars.expectedAdapterLoanBalance += amount;

        uint256 expectedDecreasedSupplyShares = amount.toSharesUp(vars.expectedTotalSupply, vars.expectedSupplyShares);
        vars.expectedTotalSupply -= amount;
        vars.expectedSupplyShares -= expectedDecreasedSupplyShares;
    }

    function _addBorrowData(BundleTransactionsVars memory vars, uint256 shares) internal {
        uint256 availableLiquidity = vars.expectedTotalSupply - vars.expectedTotalBorrow;
        if (availableLiquidity == 0 || vars.expectedCollateral == 0) return;

        uint256 totalBorrowPower = vars.expectedCollateral.wMulDown(LTV);

        uint256 borrowed = vars.expectedBorrowShares.toAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 currentBorrowPower = totalBorrowPower - borrowed;
        if (currentBorrowPower == 0) return;

        uint256 maxShares = MorphoUtilsLib.min(currentBorrowPower, availableLiquidity).toSharesDown(
            vars.expectedTotalBorrow, vars.expectedBorrowShares
        );
        if (maxShares < MIN_AMOUNT) return;
        shares = bound(shares % maxShares, MIN_AMOUNT, maxShares);

        bundle.push(_marketBorrow(market, 0, shares, 0, address(altoAdapter)));
        uint256 expectedBorrowedAmount = shares.toAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedAdapterLoanBalance += expectedBorrowedAmount;

        vars.expectedTotalBorrow += expectedBorrowedAmount;
        vars.expectedBorrowShares += shares;
    }

    function _addRepayData(BundleTransactionsVars memory vars, uint256 amount, address user) internal {
        if (vars.expectedBorrowShares == 0) return;

        uint256 borrowBalance =
            vars.expectedBorrowShares.toAssetsDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        amount = bound(amount % borrowBalance, 1, borrowBalance);

        _transferMissingLoan(vars, amount);

        bundle.push(_marketRepay(market, amount, 0, type(uint256).max, user));
        vars.expectedAdapterLoanBalance -= amount;

        uint256 expectedDecreasedBorrowShares = amount.toSharesDown(vars.expectedTotalBorrow, vars.expectedBorrowShares);
        vars.expectedTotalBorrow -= amount;
        vars.expectedBorrowShares -= expectedDecreasedBorrowShares;
    }

    function _addWithdrawCollateralData(BundleTransactionsVars memory vars, uint256 amount) internal {
        if (vars.expectedCollateral == 0) return;

        uint256 borrowPower = vars.expectedCollateral.wMulDown(LTV);
        uint256 borrowed = vars.expectedBorrowShares.toAssetsUp(vars.expectedTotalBorrow, vars.expectedBorrowShares);

        uint256 withdrawableCollateral = (borrowPower - borrowed).wDivDown(LTV);
        if (withdrawableCollateral == 0) return;

        amount = bound(amount % withdrawableCollateral, 1, withdrawableCollateral);

        bundle.push(_marketRemoveCollateral(market, amount, address(altoAdapter)));
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
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);

        deal(address(borrowToken), address(altoAdapter), assets);

        bundle.push(_marketAddSupply(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageSupplyKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);

        deal(address(borrowToken), address(altoAdapter), assets);

        bundle.push(_marketAddSupply(market, assets, 0, sharePriceE27, address(this)));
        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares));

        deal(address(borrowToken), address(this), assets);
        market.addSupply(assets, 0, address(this));
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketRemoveSupply(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageWithdrawKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
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
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivDown(shares));
        uint256 collateral = assets.wDivUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.setAuthorization(address(altoAdapter), true);

        bundle.push(_marketBorrow(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageBorrowKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivDown(shares) + 1, type(uint256).max);
        uint256 collateral = assets.wDivUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.setAuthorization(address(altoAdapter), true);

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_marketBorrow(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayOK(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, assets.rDivUp(shares), type(uint256).max);
        uint256 collateral = assets.wDivUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.borrow(assets, 0, address(this), address(altoAdapter));

        bundle.push(_marketRepay(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }

    function testSlippageRepayKO(uint256 assets, uint256 sharePriceE27) public {
        assets = bound(assets, MIN_AMOUNT, MAX_AMOUNT);
        uint256 shares = assets.toSharesUp(0, 0);
        sharePriceE27 = bound(sharePriceE27, 0, assets.rDivUp(shares) - 1);
        uint256 collateral = assets.wDivUp(LTV);

        deal(address(borrowToken), address(this), assets);
        deal(address(collateralToken), address(this), collateral);
        market.addSupply(assets, 0, address(this));
        market.addCollateral(collateral, address(this));
        market.borrow(assets, 0, address(this), address(altoAdapter));

        vm.expectRevert(ErrorsLib.SlippageExceeded.selector);
        bundle.push(_marketRepay(market, assets, 0, sharePriceE27, address(this)));
        bundler3.multicall(bundle);
    }
}
