// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {DusdUsmInitParams} from "@alto-test/helpers/UsmDeployer.sol";

/**
 * @title TestUsmSwapFuzz
 * @dev Fuzzing tests for swap functions
 * @dev Bounds for priceRatio: [0.01e18, 100e18]
 * @dev Bounds for fees: [0, 5000]
 * @dev Bounds for underlyingDecimals: [5, 27]
 */
contract TestUsmSwapFuzz is TestDusdBase {
    using PercentageMath for uint256;
    using PercentageMath for uint128;

    struct TestFuzzSwapAssetVars {
        // estimation function 1
        uint256 estAssetAmount1;
        uint256 estDusdAmount1;
        uint256 estGrossAmount1;
        uint256 estFeeAmount1;
        // estimation function 2
        uint256 estAssetAmount2;
        uint256 estDusdAmount2;
        uint256 estGrossAmount2;
        uint256 estFeeAmount2;
        // swap function
        uint256 exactAssetAmount;
        uint256 exactDusdAmount;
    }

    function _checkValidPrice(FixedPriceStrategy priceStrat, uint256 assetAmount, uint256 dusdAmount) internal {
        assertApproxEqAbs(
            priceStrat.getAssetPriceInStableToken(assetAmount, false),
            dusdAmount,
            2,
            "price between asset and dusd amounts is not valid _1"
        );

        assertApproxEqAbs(
            priceStrat.getAssetPriceInStableToken(assetAmount, true),
            dusdAmount,
            2,
            "price between asset and dusd amounts is not valid _2"
        );

        assertApproxEqAbs(
            priceStrat.getStableTokenPriceInAsset(dusdAmount, false),
            assetAmount,
            2,
            "price between asset and dusd amounts is not valid _3"
        );
        assertApproxEqAbs(
            priceStrat.getStableTokenPriceInAsset(dusdAmount, true),
            assetAmount,
            2,
            "price between asset and dusd amounts is not valid _4"
        );
    }

    /**
     * @dev Check there is no way of making money by sell-buy actions
     */
    function testFuzzSellBuyNoArb(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 assetAmount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        TestFuzzSwapAssetVars memory vars;

        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        assetAmount = bound(assetAmount, 1, type(uint64).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        // Strat estimation
        (, vars.estDusdAmount1,,) = gsm.getStableTokenAmountForSellAsset(assetAmount);
        (vars.estAssetAmount2,,,) = gsm.getAssetAmountForBuyAsset(vars.estDusdAmount1);
        assertLe(vars.estAssetAmount2, assetAmount, "getting more assetAmount than provided in estimation");

        // Init GSM with some assets
        (, uint256 aux,,) = gsm.getStableTokenAmountForSellAsset(assetAmount);
        vm.assume(aux > 0);
        vm.startPrank(FAUCET);
        newToken.mint(FAUCET, assetAmount);
        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(assetAmount, FAUCET);
        vm.stopPrank();

        // Arb Strat estimation
        (, vars.estDusdAmount1,,) = gsm.getStableTokenAmountForSellAsset(assetAmount);
        (vars.estAssetAmount2,,,) = gsm.getAssetAmountForBuyAsset(vars.estDusdAmount1);
        assertLe(vars.estAssetAmount2, assetAmount, "getting more assetAmount than provided in estimation");

        // Top up Alice
        vm.prank(FAUCET);
        newToken.mint(ALICE, assetAmount);

        // Arb Strat
        vm.startPrank(ALICE);
        uint256 aliceBalanceBefore = newToken.balanceOf(ALICE);
        newToken.approve(address(gsm), type(uint256).max);
        DUSD_TOKEN.approve(address(gsm), type(uint256).max);

        (, vars.exactDusdAmount) = gsm.sellAsset(assetAmount, ALICE);
        (vars.estAssetAmount1,,,) = gsm.getAssetAmountForBuyAsset(vars.exactDusdAmount);
        assertLe(vars.estAssetAmount1, assetAmount, "getting more assetAmount than provided in estimation");
        vm.assume(vars.estAssetAmount1 > 0); // 0 value is a valid for the property to hold, but buyAsset op would fail
        (vars.exactAssetAmount,) = gsm.buyAsset(vars.estAssetAmount1, ALICE);

        assertLe(vars.exactAssetAmount, assetAmount, "getting more assetAmount than provided in swap");
        assertLe(newToken.balanceOf(ALICE), aliceBalanceBefore, "asset balance more than before");
        vm.stopPrank();
    }

    /**
     * @dev It is possible to use values for price ratio that creates unbalance in the GSM, so all DUSD cannot be burned.
     * e.g. With (1e16 + 1) priceRatio, a user gets 1e11 dusd for selling 1 asset but gets 1 asset by selling 1e11+1 dusd
     */
    function testFuzzPriceRatioRoundingUnbalance(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        // Get dusd amount for selling assets
        (uint256 assetSold,, uint256 dusdMinted,) = gsm.getStableTokenAmountForSellAsset(amount);
        (,, uint256 dusdToBurn,) = gsm.getStableTokenAmountForBuyAsset(assetSold);

        // 1 unit of imprecision due to rounding
        assertTrue(dusdToBurn <= dusdMinted + 1, "unexpected gsm unbalance");

        // Get amount of assets can be purchased based on minted DUSD amount
        (, uint256 dusdAmount,,) = gsm.getAssetAmountForBuyAsset(dusdMinted);
        assertTrue(dusdAmount <= dusdMinted);
    }

    /**
     * @dev Checks that passing an amount higher than 2*128-1 (`maxUint128`) to a swap function reverts
     */
    function testFuzzSwapAmountAbove128(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max) + type(uint128).max; // avoiding a bug in forge-std where bound will revert

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (uint256 dusdBought,,,) = gsm.getStableTokenAmountForSellAsset(amount);
        vm.assume(dusdBought > type(uint128).max);

        vm.startPrank(FAUCET);
        newToken.mint(FAUCET, amount);
        newToken.approve(address(gsm), amount);
        vm.expectRevert();
        gsm.sellAsset(amount, ALICE);
        vm.stopPrank();
    }

    /**
     * @dev Tests to ensure a revert when the GSM holds the maximum amount of asset possible and a user attempts to buy
     * 1 more unit of the asset than is available
     */
    function testFuzzBuyAmountAboveMaximum(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        uint256 amount = newPriceStrategy.getStableTokenPriceInAsset(type(uint128).max, false);
        if (amount > type(uint128).max) {
            amount = type(uint128).max;
        }

        vm.startPrank(FAUCET);
        newToken.mint(FAUCET, amount);
        newToken.approve(address(gsm), amount);
        gsm.sellAsset(amount, ALICE);
        vm.stopPrank();

        dusdFaucet(BOB, type(uint128).max);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(gsm), type(uint128).max);
        vm.expectRevert();
        gsm.buyAsset(amount + 1, BOB);
        vm.stopPrank();
    }

    /**
     * @dev Checks behaviour of getStableTokenAmountForSellAsset
     */
    function testFuzzgetStableTokenAmountForSellAsset(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (uint256 exactAssetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            gsm.getStableTokenAmountForSellAsset(amount);
        assertTrue(exactAssetAmount <= amount, "maximum asset amount exceeded");
        assertTrue(dusdBought <= grossAmount, "gross amount lower than dusdBought");
        _checkValidPrice(newPriceStrategy, exactAssetAmount, grossAmount);

        // In case of 0 sellFee
        if (sellFeeBps == 0) {
            assertEq(grossAmount, dusdBought, "unexpected gross amount");
            assertEq(fee, 0, "unexpected fee");
        }
    }

    /**
     * @dev Checks behaviour of getStableTokenAmountForBuyAsset
     */
    function testFuzzgetStableTokenAmountForBuyAsset(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (uint256 exactAssetAmount, uint256 dusdSold, uint256 grossAmount, uint256 fee) =
            gsm.getStableTokenAmountForBuyAsset(amount);
        assertTrue(exactAssetAmount >= amount, "minimum asset amount not reached");
        assertTrue(dusdSold >= grossAmount, "gross amount lower than dusdSold");
        _checkValidPrice(newPriceStrategy, exactAssetAmount, grossAmount);

        // In case of 0 buyFee
        if (buyFeeBps == 0) {
            assertEq(grossAmount, dusdSold, "unexpected gross amount");
            assertEq(fee, 0, "unexpected fee");
        }
    }

    /**
     * @dev Checks behaviour of getAssetAmountForSellAsset
     */
    function testFuzzGetAssetAmountForSellAsset(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (uint256 exactAssetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            gsm.getAssetAmountForSellAsset(amount);
        assertTrue(dusdBought > 0, "unexpected 0 value for dusdBought");
        assertTrue(dusdBought >= amount, "minimum dusd amount not reached");
        assertTrue(dusdBought <= grossAmount, "gross amount lower than dusdBought");
        _checkValidPrice(newPriceStrategy, exactAssetAmount, grossAmount);

        // In case of 0 sellFee
        if (sellFeeBps == 0) {
            assertEq(grossAmount, dusdBought, "unexpected gross amount");
            assertEq(fee, 0, "unexpected fee");
        }
    }

    /**
     * @dev Checks behaviour of getAssetAmountForBuyAsset
     */
    function testFuzzGetAssetAmountForBuyAsset(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 amount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        amount = bound(amount, 1, type(uint128).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (uint256 exactAssetAmount, uint256 dusdSold, uint256 grossAmount, uint256 fee) =
            gsm.getAssetAmountForBuyAsset(amount);
        assertTrue(dusdSold <= amount, "maximum dusd amount exceeded");
        assertTrue(dusdSold >= grossAmount, "gross amount lower than dusdSold");
        _checkValidPrice(newPriceStrategy, exactAssetAmount, grossAmount);

        // In case of 0 buyFee
        if (buyFeeBps == 0) {
            assertEq(grossAmount, dusdSold, "unexpected gross amount");
            assertEq(fee, 0, "unexpected fee");
        }
    }

    /**
     * @dev Checks invariant between inverse functions to query amounts for the sell action: getStableTokenAmountForSellAsset
     * and getAssetAmountForSellAsset.
     */
    function testFuzzSellEstimation(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 assetAmount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        TestFuzzSwapAssetVars memory vars;

        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        assetAmount = bound(assetAmount, 1, type(uint64).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: uint128(assetAmount),
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (vars.estAssetAmount1, vars.estDusdAmount1, vars.estGrossAmount1, vars.estFeeAmount1) =
            gsm.getStableTokenAmountForSellAsset(assetAmount);
        vm.assume(vars.estDusdAmount1 > 0);
        (vars.estAssetAmount2, vars.estDusdAmount2, vars.estGrossAmount2, vars.estFeeAmount2) =
            gsm.getAssetAmountForSellAsset(vars.estDusdAmount1);

        assertTrue(
            assetAmount >= vars.estAssetAmount1, "exact asset amount being used is higher than the amount passed"
        );
        assertTrue(
            assetAmount >= vars.estAssetAmount2, "exact asset amount being used is higher than the amount passed"
        );
        assertEq(vars.estDusdAmount1, vars.estDusdAmount2, "bought dusd amount do not match");
        assertEq(vars.estAssetAmount1, vars.estAssetAmount2, "given assetAmount and estimated do not match");
        // 1 wei precision error
        assertApproxEqAbs(vars.estGrossAmount1, vars.estGrossAmount2, 1, "estimated gross amounts do not match");
        assertApproxEqAbs(vars.estFeeAmount1, vars.estFeeAmount2, 1, "estimated fees do not match");

        // In case of 0 sellFee
        if (sellFeeBps == 0) {
            assertEq(vars.estGrossAmount1, vars.estDusdAmount1, "unexpected grossAmount1 and dusdBought");
            assertEq(vars.estGrossAmount2, vars.estDusdAmount1, "unexpected grossAmount2 and dusdBought");
            assertEq(vars.estFeeAmount1, 0, "expected fee1");
            assertEq(vars.estFeeAmount2, 0, "expected fee2");
        }
    }

    /**
     * @dev Checks invariant between inverse functions to query amounts for the buy action: getStableTokenAmountForBuyAsset
     * and getAssetAmountForBuyAsset.
     */
    function testFuzzBuyEstimation(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 assetAmount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        TestFuzzSwapAssetVars memory vars;

        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        assetAmount = bound(assetAmount, 1, type(uint64).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: uint128(assetAmount),
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        (vars.estAssetAmount1, vars.estDusdAmount1, vars.estGrossAmount1, vars.estFeeAmount1) =
            gsm.getStableTokenAmountForBuyAsset(assetAmount);
        vm.assume(vars.estDusdAmount1 > 0);
        (vars.estAssetAmount2, vars.estDusdAmount2, vars.estGrossAmount2, vars.estFeeAmount2) =
            gsm.getAssetAmountForBuyAsset(vars.estDusdAmount1);

        assertTrue(vars.estAssetAmount1 >= assetAmount, "exact asset amount being used is less than the amount passed");
        assertTrue(vars.estAssetAmount2 >= assetAmount, "exact asset amount being used is less than the amount passed");
        assertEq(vars.estDusdAmount1, vars.estDusdAmount2, "sold dusd amount do not match");
        assertEq(vars.estAssetAmount1, vars.estAssetAmount2, "given assetAmount and estimated do not match");
        assertEq(vars.estGrossAmount1, vars.estGrossAmount2, "estimated gross amounts do not match");
        assertEq(vars.estFeeAmount1, vars.estFeeAmount2, "estimated fees do not match");

        // In case of 0 buyFee
        if (buyFeeBps == 0) {
            assertEq(vars.estGrossAmount1, vars.estDusdAmount1, "unexpected grossAmount1 and dusdSold");
            assertEq(vars.estGrossAmount2, vars.estDusdAmount1, "unexpected grossAmount2 and dusdSold");
            assertEq(vars.estFeeAmount1, 0, "expected fee1");
            assertEq(vars.estFeeAmount2, 0, "expected fee2");
        }
    }

    /**
     * @dev Checks sellAsset is aligned with getAssetAmountForSellAsset and getStableTokenAmountForSellAsset
     */
    function testFuzzSellAssetWithEstimation(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 assetAmount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        TestFuzzSwapAssetVars memory vars;

        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        assetAmount = bound(assetAmount, 1, type(uint64).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);
        vm.prank(FAUCET);
        newToken.mint(ALICE, assetAmount);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: uint128(assetAmount),
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        vm.startPrank(ALICE);
        newToken.approve(address(gsm), type(uint256).max);

        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        // Calculate DUSD amount to purchase with given asset amount, bail if 0
        (, vars.estDusdAmount1, vars.estGrossAmount1, vars.estFeeAmount1) =
            gsm.getStableTokenAmountForSellAsset(assetAmount);
        vm.assume(vars.estDusdAmount1 > 0);

        (vars.exactAssetAmount, vars.exactDusdAmount) = gsm.sellAsset(assetAmount, ALICE);

        // Calculate asset amount needed for the amount of DUSD required to buy
        (vars.estAssetAmount2,, vars.estGrossAmount2, vars.estFeeAmount2) =
            gsm.getAssetAmountForSellAsset(vars.exactDusdAmount);

        assertEq(
            userAssetBefore - newToken.balanceOf(ALICE),
            vars.exactAssetAmount,
            "real assets sold are not equal to the exact amount"
        );
        assertTrue(
            userAssetBefore - newToken.balanceOf(ALICE) <= assetAmount, "real assets sold are more than the input"
        );
        assertEq(
            DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore,
            vars.exactDusdAmount,
            "real dusd bought does not match returned value"
        );
        assertEq(
            DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore,
            vars.estDusdAmount1,
            "real dusd bought does not match estimated value"
        );
        assertEq(
            userAssetBefore - newToken.balanceOf(ALICE),
            vars.estAssetAmount2,
            "real assets sold does not match estimated value"
        );

        // 1 wei precision error
        assertApproxEqAbs(vars.estGrossAmount1, vars.estGrossAmount2, 1, "estimated gross amounts do not match");
        assertApproxEqAbs(vars.estFeeAmount1, vars.estFeeAmount2, 1, "estimated fees do not match");

        // In case of 0 sellFeeBps
        if (sellFeeBps == 0) {
            assertEq(vars.estGrossAmount1, vars.exactDusdAmount, "unexpected grossAmount1 and dusdBought");
            assertEq(vars.estGrossAmount2, vars.exactDusdAmount, "unexpected grossAmount2 and dusdBought");
            assertEq(vars.estFeeAmount1, 0, "expected fee1");
            assertEq(vars.estFeeAmount2, 0, "expected fee2");
        }

        vm.stopPrank();
    }

    /**
     * @dev Checks buyAsset is aligned with getAssetAmountForBuyAsset and getStableTokenAmountForBuyAsset
     */
    function testFuzzBuyAssetWithEstimation(
        uint8 underlyingDecimals,
        uint256 priceRatio,
        uint256 assetAmount,
        uint256 buyFeeBps,
        uint256 sellFeeBps
    ) public {
        TestFuzzSwapAssetVars memory vars;

        underlyingDecimals = uint8(bound(underlyingDecimals, 5, 27));
        buyFeeBps = bound(buyFeeBps, 0, 5000 - 1);
        sellFeeBps = bound(sellFeeBps, 0, 5000 - 1);
        priceRatio = bound(priceRatio, 0.01e18, 100e18);
        assetAmount = bound(assetAmount, 1, type(uint64).max - 1);

        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", underlyingDecimals);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(priceRatio, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        if (buyFeeBps > 0 || sellFeeBps > 0) {
            FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(buyFeeBps, sellFeeBps, address(this));
            gsm.updateFeeStrategy(address(newFeeStrategy));
        }

        // Alice sells some assets to the GSM, so the purchase is doable
        uint256 sellAssetAmount = newPriceStrategy.getStableTokenPriceInAsset(type(uint128).max, false);
        if (sellAssetAmount > type(uint128).max) {
            sellAssetAmount = type(uint128).max;
        }

        vm.prank(FAUCET);
        newToken.mint(ALICE, sellAssetAmount);

        vm.startPrank(ALICE);
        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(sellAssetAmount, ALICE);
        vm.stopPrank();

        // rough estimation of DUSD funds needed for buyAsset
        (, uint256 estDusdBought,,) = gsm.getStableTokenAmountForBuyAsset(assetAmount);
        dusdFaucet(ALICE, estDusdBought * 20);

        // Buy
        vm.startPrank(ALICE);
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        // Calculate DUSD amount to sell with given asset amount
        (, vars.estDusdAmount1, vars.estGrossAmount1, vars.estFeeAmount1) =
            gsm.getStableTokenAmountForBuyAsset(assetAmount);

        userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        userAssetBefore = newToken.balanceOf(ALICE);

        DUSD_TOKEN.approve(address(gsm), type(uint256).max);
        (vars.exactAssetAmount, vars.exactDusdAmount) = gsm.buyAsset(assetAmount, ALICE);

        // Calculate asset amount can be bought for the amount of DUSD available
        (vars.estAssetAmount2, vars.estDusdAmount2, vars.estGrossAmount2, vars.estFeeAmount2) =
            gsm.getAssetAmountForBuyAsset(vars.exactDusdAmount);

        assertEq(
            newToken.balanceOf(ALICE) - userAssetBefore,
            vars.exactAssetAmount,
            "real assets bought are not equal to the exact amount"
        );
        assertTrue(
            newToken.balanceOf(ALICE) - userAssetBefore >= assetAmount, "real assets bought are less than the input"
        );
        assertEq(
            newToken.balanceOf(ALICE) - userAssetBefore,
            vars.estAssetAmount2,
            "real assets bought does not match estimated value"
        );
        assertEq(
            userDusdBefore - DUSD_TOKEN.balanceOf(ALICE),
            vars.exactDusdAmount,
            "real dusd sold does not match returned value"
        );
        assertEq(
            userDusdBefore - DUSD_TOKEN.balanceOf(ALICE),
            vars.estDusdAmount1,
            "real dusd sold does not match estimated value"
        );

        assertEq(vars.estDusdAmount1, vars.estDusdAmount2, "estimated gross amounts do not match");
        assertEq(vars.estFeeAmount1, vars.estFeeAmount2, "estimated fees do not match");

        // In case of 0 buyFeeBps
        if (buyFeeBps == 0) {
            assertEq(vars.estDusdAmount1, vars.exactDusdAmount, "unexpected grossAmount1 and dusdSold");
            assertEq(vars.estDusdAmount2, vars.exactDusdAmount, "unexpected grossAmount2 and dusdSold");
            assertEq(vars.estFeeAmount1, 0, "expected fee1");
            assertEq(vars.estFeeAmount2, 0, "expected fee2");
        }

        vm.stopPrank();
    }
}
