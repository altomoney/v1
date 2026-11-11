// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IAltoBorrowMarket} from "@alto/lending/interfaces/IAltoBorrowMarket.sol";

contract ERC4626Test is IntegrationTest {
    using AltoBalancesLib for address;

    IERC4626 internal erc4626Vault;

    function setUp() public override {
        super.setUp();

        erc4626Vault = IERC4626(address(vault));

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();
    }

    function testDecimals(uint8 decimals) public {
        vm.mockCall(address(loanToken), abi.encodeWithSignature("decimals()"), abi.encode(decimals));

        vault = IAltoVault(
            address(new AltoVault(OWNER, TIMELOCK, address(loanToken), "Alto Vault", "AV", address(marketRegistry)))
        );

        assertEq(ERC20(address(vault)).decimals(), Math.max(18, decimals), "decimals");
    }

    function testMint(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 shares = erc4626Vault.convertToShares(assets);

        loanToken.setBalance(SUPPLIER, assets);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 deposited = erc4626Vault.mint(shares, ONBEHALF);

        assertGt(deposited, 0, "deposited");
        assertEq(loanToken.balanceOf(address(erc4626Vault)), 0, "balanceOf(vault)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), assets, "expectedSupplyAssets(vault)");
    }

    function testDeposit(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets() + assets);
        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        assertEq(loanToken.balanceOf(address(erc4626Vault)), 0, "balanceOf(vault)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares, "balanceOf(ONBEHALF)");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), assets, "expectedSupplyAssets(vault)");
    }

    function testRedeem(uint256 deposited, uint256 redeemed) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        redeemed = bound(redeemed, 0, shares);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets() - erc4626Vault.convertToAssets(redeemed));
        vm.prank(ONBEHALF);
        erc4626Vault.redeem(redeemed, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(erc4626Vault)), 0, "balanceOf(vault)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
    }

    function testWithdraw(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets() - withdrawn);
        vm.prank(ONBEHALF);
        uint256 redeemed = erc4626Vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(erc4626Vault)), 0, "balanceOf(vault)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
    }

    function testWithdrawIdle(uint256 deposited, uint256 withdrawn) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        withdrawn = bound(withdrawn, 0, deposited);

        _setCap(allMarkets[0], 0);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        vm.expectEmit();
        emit IAltoVaultEvents.UpdateLastTotalAssets(erc4626Vault.totalAssets() - withdrawn);
        vm.prank(ONBEHALF);
        uint256 redeemed = erc4626Vault.withdraw(withdrawn, RECEIVER, ONBEHALF);

        assertEq(loanToken.balanceOf(address(erc4626Vault)), 0, "balanceOf(vault)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares - redeemed, "balanceOf(ONBEHALF)");
        assertEq(_idle(), deposited - withdrawn, "idle");
    }

    function testRedeemTooMuch(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited * 2);

        vm.startPrank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);
        vm.stopPrank();

        vm.prank(SUPPLIER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, shares, shares + 1)
        );
        erc4626Vault.redeem(shares + 1, RECEIVER, SUPPLIER);
    }

    function testWithdrawAll(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 minted = erc4626Vault.deposit(assets, ONBEHALF);

        assertEq(erc4626Vault.maxWithdraw(ONBEHALF), assets, "maxWithdraw(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 shares = erc4626Vault.withdraw(assets, RECEIVER, ONBEHALF);

        assertEq(shares, minted, "shares");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), assets, "loanToken.balanceOf(RECEIVER)");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testRedeemAll(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 minted = erc4626Vault.deposit(deposited, ONBEHALF);

        assertEq(erc4626Vault.maxRedeem(ONBEHALF), minted, "maxRedeem(ONBEHALF)");

        vm.prank(ONBEHALF);
        uint256 assets = erc4626Vault.redeem(minted, RECEIVER, ONBEHALF);

        assertEq(assets, deposited, "assets");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), 0, "balanceOf(ONBEHALF)");
        assertEq(loanToken.balanceOf(RECEIVER), deposited, "loanToken.balanceOf(RECEIVER)");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), 0, "expectedSupplyAssets(vault)");
    }

    function testRedeemNotDeposited(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        vm.prank(SUPPLIER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, SUPPLIER, 0, shares));
        erc4626Vault.redeem(shares, SUPPLIER, SUPPLIER);
    }

    function testRedeemNotApproved(uint256 deposited) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, shares));
        erc4626Vault.redeem(shares, RECEIVER, ONBEHALF);
    }

    function testWithdrawNotApproved(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(assets, ONBEHALF);

        uint256 shares = erc4626Vault.previewWithdraw(assets);
        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, RECEIVER, 0, shares));
        erc4626Vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testTransferFrom(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, shares);

        vm.prank(ONBEHALF);
        erc4626Vault.approve(SUPPLIER, toTransfer);

        vm.prank(SUPPLIER);
        erc4626Vault.transferFrom(ONBEHALF, RECEIVER, toTransfer);

        assertEq(erc4626Vault.balanceOf(ONBEHALF), shares - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(erc4626Vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
        assertEq(erc4626Vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
    }

    function testTransferFromNotApproved(uint256 deposited, uint256 amount) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited, ONBEHALF);

        amount = bound(amount, 0, shares);

        vm.prank(SUPPLIER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SUPPLIER, 0, shares));
        erc4626Vault.transferFrom(ONBEHALF, RECEIVER, shares);
    }

    function testWithdrawMoreThanBalanceButLessThanTotalAssets(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.startPrank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(deposited / 2, ONBEHALF);
        erc4626Vault.deposit(deposited / 2, SUPPLIER);
        vm.stopPrank();

        assets = bound(assets, deposited / 2 + 1, erc4626Vault.totalAssets());

        uint256 sharesBurnt = erc4626Vault.previewWithdraw(assets);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ONBEHALF, shares, sharesBurnt)
        );
        vm.prank(ONBEHALF);
        erc4626Vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testWithdrawMoreThanTotalAssets(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        vm.prank(ONBEHALF);
        vm.expectRevert(IAltoVaultErrors.NotEnoughLiquidity.selector);
        erc4626Vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testWithdrawMoreThanBalanceAndLiquidity(uint256 deposited, uint256 assets) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(deposited, ONBEHALF);

        assets = bound(assets, deposited + 1, type(uint256).max / (deposited + 1));

        collateralToken.setBalance(BORROWER, type(uint128).max);

        // Borrow liquidity.
        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(type(uint128).max, BORROWER);
        IMarket(allMarkets[0]).borrow(1, 0, BORROWER, BORROWER, hex"");

        vm.startPrank(ONBEHALF);
        vm.expectRevert(IAltoVaultErrors.NotEnoughLiquidity.selector);
        erc4626Vault.withdraw(assets, RECEIVER, ONBEHALF);
    }

    function testTransfer(uint256 deposited, uint256 toTransfer) public {
        deposited = bound(deposited, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, deposited);

        vm.prank(SUPPLIER);
        uint256 minted = erc4626Vault.deposit(deposited, ONBEHALF);

        toTransfer = bound(toTransfer, 0, minted);

        vm.prank(ONBEHALF);
        erc4626Vault.transfer(RECEIVER, toTransfer);

        assertEq(erc4626Vault.balanceOf(SUPPLIER), 0, "balanceOf(SUPPLIER)");
        assertEq(erc4626Vault.balanceOf(ONBEHALF), minted - toTransfer, "balanceOf(ONBEHALF)");
        assertEq(erc4626Vault.balanceOf(RECEIVER), toTransfer, "balanceOf(RECEIVER)");
    }

    function testMaxWithdraw(uint256 depositedAssets, uint256 borrowedAssets) public {
        depositedAssets = bound(depositedAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAssets = bound(borrowedAssets, MIN_TEST_ASSETS, depositedAssets);

        loanToken.setBalance(SUPPLIER, depositedAssets);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(depositedAssets, ONBEHALF);

        collateralToken.setBalance(BORROWER, type(uint128).max);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(type(uint128).max, BORROWER);
        IMarket(allMarkets[0]).borrow(borrowedAssets, 0, BORROWER, BORROWER, hex"");

        assertEq(erc4626Vault.maxWithdraw(ONBEHALF), depositedAssets - borrowedAssets, "maxWithdraw(ONBEHALF)");
    }

    function testMaxDeposit() public {
        _setCap(allMarkets[0], 1 ether);

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];

        vm.prank(ALLOCATOR);
        IAltoVault(address(erc4626Vault)).setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, 1 ether);
        collateralToken.setBalance(BORROWER, 2 ether);

        vm.prank(SUPPLIER);
        IMarket(allMarkets[0]).addSupply(1 ether, 0, SUPPLIER);

        vm.startPrank(BORROWER);
        IMarket(allMarkets[0]).addCollateral(2 ether, BORROWER);
        IMarket(allMarkets[0]).borrow(1 ether, 0, BORROWER, BORROWER, hex"");
        vm.stopPrank();

        _forward(1_000);

        loanToken.setBalance(SUPPLIER, 1 ether);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1 ether, ONBEHALF);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0);
    }

    function testMaxDepositAndDepositRespectMarketSupplyCap() public {
        uint256 marketSupplyCap = 1 ether;

        vm.prank(MARKET_OWNER);
        IAltoBorrowMarket(allMarkets[0]).setSupplyCap(uint128(marketSupplyCap));

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), marketSupplyCap, "incorrect max deposit");

        loanToken.setBalance(SUPPLIER, marketSupplyCap + 1);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(marketSupplyCap + 1, ONBEHALF);

        uint256 previewedShares = erc4626Vault.previewDeposit(marketSupplyCap);
        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(marketSupplyCap, ONBEHALF);

        assertEq(shares, previewedShares, "received shares differ from previewDeposit");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), marketSupplyCap, "incorrect market supply");
        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0, "market supply capacity remains");
    }

    function testMaxDepositAndDepositTreatZeroMarketSupplyCapAsUnlimited() public {
        uint256 vaultSupplyCap = 2 ether;

        _setCap(allMarkets[0], vaultSupplyCap);

        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        assertEq(IAltoBorrowMarket(allMarkets[0]).supplyCapAssets(), 0, "market supply should be uncapped");
        assertEq(erc4626Vault.maxDeposit(SUPPLIER), vaultSupplyCap, "incorrect max deposit");

        loanToken.setBalance(SUPPLIER, vaultSupplyCap + 1);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(vaultSupplyCap + 1, ONBEHALF);

        uint256 previewedShares = erc4626Vault.previewDeposit(vaultSupplyCap);
        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(vaultSupplyCap, ONBEHALF);

        assertEq(shares, previewedShares, "received shares differ from previewDeposit");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), vaultSupplyCap, "incorrect market supply");
        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0, "vault supply capacity remains");
    }

    function testMaxDepositAndDepositFillMarketsUpToTheirSupplyCaps() public {
        uint256 firstMarketSupplyCap = 1 ether;
        uint256 secondMarketSupplyCap = 3 ether;
        uint256 otherSupplierAssets = 0.4 ether;

        _setCap(allMarkets[1], CAP);
        _setSupplyQueue(allMarkets[0], allMarkets[1]);

        vm.startPrank(MARKET_OWNER);
        IAltoBorrowMarket(allMarkets[0]).setSupplyCap(uint128(firstMarketSupplyCap));
        IAltoBorrowMarket(allMarkets[1]).setSupplyCap(uint128(secondMarketSupplyCap));
        vm.stopPrank();

        // Supply from outside the vault uses up part of the first market's supply cap.
        loanToken.setBalance(SUPPLIER, otherSupplierAssets);
        vm.prank(SUPPLIER);
        IMarket(allMarkets[0]).addSupply(otherSupplierAssets, 0, SUPPLIER);

        uint256 firstMarketRoom = firstMarketSupplyCap - otherSupplierAssets;
        uint256 expectedMaxDeposit = firstMarketRoom + secondMarketSupplyCap;

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), expectedMaxDeposit, "incorrect max deposit");

        loanToken.setBalance(SUPPLIER, expectedMaxDeposit + 1);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(expectedMaxDeposit + 1, ONBEHALF);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(expectedMaxDeposit, ONBEHALF);

        // The first market is filled up to its supply cap and the remainder goes to the second market.
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), firstMarketRoom, "first market supply");
        assertEq(
            allMarkets[1].expectedSupplyAssets(address(erc4626Vault)), secondMarketSupplyCap, "second market supply"
        );
        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0, "market supply capacity remains");
    }

    function testMaxDepositIsZeroWhenMarketSupplyCapIsBelowTotalSupply() public {
        _setSupplyQueue(allMarkets[0]);

        loanToken.setBalance(SUPPLIER, 2 ether + 1);
        vm.prank(SUPPLIER);
        IMarket(allMarkets[0]).addSupply(2 ether, 0, SUPPLIER);

        vm.prank(MARKET_OWNER);
        IAltoBorrowMarket(allMarkets[0]).setSupplyCap(1 ether);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0, "incorrect max deposit");
        assertEq(erc4626Vault.maxMint(SUPPLIER), 0, "incorrect max mint");

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1, ONBEHALF);
    }

    function testMaxMintAndMintRespectMarketSupplyCap() public {
        uint256 marketSupplyCap = 1 ether;

        vm.prank(MARKET_OWNER);
        IAltoBorrowMarket(allMarkets[0]).setSupplyCap(uint128(marketSupplyCap));

        _setSupplyQueue(allMarkets[0]);

        uint256 maxShares = erc4626Vault.maxMint(SUPPLIER);

        assertEq(maxShares, erc4626Vault.convertToShares(marketSupplyCap), "incorrect max mint");

        loanToken.setBalance(SUPPLIER, erc4626Vault.previewMint(maxShares + 1));

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.mint(maxShares + 1, ONBEHALF);

        uint256 previewedAssets = erc4626Vault.previewMint(maxShares);
        vm.prank(SUPPLIER);
        uint256 assets = erc4626Vault.mint(maxShares, ONBEHALF);

        assertEq(assets, previewedAssets, "paid assets differ from previewMint");
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), assets, "incorrect market supply");
        assertEq(erc4626Vault.maxMint(SUPPLIER), 0, "market supply capacity remains");
    }

    function testMaxDepositAndMaxMintExcludePausedMarket() public {
        _testMaxDepositAndMaxMintExcludeMarket(PAUSE_TYPE);
    }

    function testMaxDepositAndMaxMintExcludeFrozenMarket() public {
        _testMaxDepositAndMaxMintExcludeMarket(FROZEN_TYPE);
    }

    /// @dev A market paused with `pauseType` cannot accept supply, so its capacity must not be quoted.
    function _testMaxDepositAndMaxMintExcludeMarket(bytes32 pauseType) internal {
        uint256 firstMarketCap = 1 ether;
        uint256 secondMarketCap = 2 ether;

        _setCap(allMarkets[0], firstMarketCap);
        _setCap(allMarkets[1], secondMarketCap);
        _setSupplyQueue(allMarkets[0], allMarkets[1]);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), firstMarketCap + secondMarketCap, "max deposit before pause");

        vm.prank(MARKET_OWNER);
        IMarket(allMarkets[0]).pause(pauseType, true);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), secondMarketCap, "max deposit with one market paused");
        assertEq(
            erc4626Vault.maxMint(SUPPLIER),
            erc4626Vault.convertToShares(secondMarketCap),
            "max mint with one market paused"
        );

        loanToken.setBalance(SUPPLIER, secondMarketCap + 1);

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(secondMarketCap + 1, ONBEHALF);

        vm.prank(SUPPLIER);
        erc4626Vault.deposit(secondMarketCap / 2, ONBEHALF);

        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), 0, "paused market supply");
        assertEq(erc4626Vault.maxDeposit(SUPPLIER), secondMarketCap / 2, "max deposit after deposit");

        vm.prank(MARKET_OWNER);
        IMarket(allMarkets[1]).pause(pauseType, true);

        assertEq(erc4626Vault.maxDeposit(SUPPLIER), 0, "max deposit with all markets paused");
        assertEq(erc4626Vault.maxMint(SUPPLIER), 0, "max mint with all markets paused");

        vm.expectRevert(IAltoVaultErrors.AllCapsReached.selector);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(1, ONBEHALF);
    }

    function _setSupplyQueue(address market) internal {
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = market;

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);
    }

    function _setSupplyQueue(address firstMarket, address secondMarket) internal {
        address[] memory supplyQueue = new address[](2);
        supplyQueue[0] = firstMarket;
        supplyQueue[1] = secondMarket;

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);
    }

    function testDepositSkipsPausedMarketAndFallsBackToNextMarket(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        // Enable a second market as fallback.
        _setCap(allMarkets[1], CAP);
        _sortSupplyQueueIdleLast();

        // Pause allMarkets[0] so accrueInterest and addSupply revert.
        vm.prank(MARKET_OWNER);
        IMarket(allMarkets[0]).pause(PAUSE_TYPE, true);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        // allMarkets[0] is paused so supply must have gone elsewhere (allMarkets[1] or idle).
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), 0, "paused market supply");
        assertGt(
            allMarkets[1].expectedSupplyAssets(address(erc4626Vault))
                + idleMarket.expectedSupplyAssets(address(erc4626Vault)),
            0,
            "fallback market supply"
        );
    }

    function testDepositWorksWhenMarketPaused(uint256 assets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        // Pause market, for other markets cap is set to 0 for now
        vm.prank(MARKET_OWNER);
        IMarket(allMarkets[0]).pause(PAUSE_TYPE, true);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        uint256 shares = erc4626Vault.deposit(assets, ONBEHALF);

        assertGt(shares, 0, "shares");
        // All assets must have landed in the idle market.
        assertEq(allMarkets[0].expectedSupplyAssets(address(erc4626Vault)), 0, "paused market supply");
        assertEq(_idle(), assets, "idle assets");
    }

    function testWithdrawFromMarketsWorksWhenOneMarketPaused() public {
        // Seed allMarkets[0] with liquidity via the vault.
        uint256 depositAmount = 1e18;
        loanToken.setBalance(SUPPLIER, depositAmount);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(depositAmount, ONBEHALF);

        _setCap(allMarkets[1], CAP);

        // Pause allMarkets[0]
        vm.prank(MARKET_OWNER);
        IMarket(allMarkets[0]).pause(PAUSE_TYPE, true);

        // Seed allMarkets[1] with liquidity via the vault so that we can withdraw from it while first market is paused
        loanToken.setBalance(SUPPLIER, depositAmount);
        vm.prank(SUPPLIER);
        erc4626Vault.deposit(depositAmount, ONBEHALF);

        uint256 sharesToRedeem = erc4626Vault.balanceOf(ONBEHALF) / 2;
        vm.prank(ONBEHALF);
        uint256 assetsReceived = erc4626Vault.redeem(sharesToRedeem, RECEIVER, ONBEHALF);

        assertEq(assetsReceived, depositAmount, "assetsReceived");
        assertEq(loanToken.balanceOf(RECEIVER), depositAmount, "receiver loanToken balance");
    }
}
