// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {DusdUsmInitParams} from "@alto-test/helpers/UsmDeployer.sol";

contract TestUsmSwapEdge is TestDusdBase {
    using PercentageMath for uint256;
    using PercentageMath for uint128;

    /**
     * @dev Edge case where it is not possible to burn all DUSD minted due to rounding issues.
     * e.g. With (1e16 + 1) priceRatio, a user gets 1e11 dusd for selling 1 asset but gets 1 asset by selling 1e11+1 dusd
     */
    function testCannotBuyAllUnderlying() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 5);
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            10000000000000001, // 1e16 + 1
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: type(uint128).max,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), type(uint128).max);

        // Sell 2 assets for 2e11DUSD
        vm.prank(FAUCET);
        newToken.mint(ALICE, 2);

        vm.startPrank(ALICE);
        newToken.approve(address(gsm), 2);
        gsm.sellAsset(2, ALICE);
        vm.stopPrank();

        // Top up withDUSD
        (, uint256 estDusdBought,,) = gsm.getStableTokenAmountForBuyAsset(2);
        dusdFaucet(ALICE, estDusdBought * 20);

        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(gsm), type(uint256).max);

        // Try to buy all, which is 2 assets for 2e11+1DUSD
        uint256 allUnderlying = gsm.getAvailableLiquidity();
        vm.expectRevert();
        gsm.buyAsset(allUnderlying, ALICE);

        // Buy a portion
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        (uint256 exactAssetAmount, uint256 exactDusdAmount) = gsm.buyAsset(1, ALICE);

        assertEq(
            newToken.balanceOf(ALICE) - userAssetBefore, exactAssetAmount, "unexpected underlying balance of ALICE"
        );
        assertEq(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE), exactDusdAmount, "unexpected DUSD balance of ALICE");

        assertTrue(gsm.getAvailableLiquidity() > 0, "unexpected remaining liquidity");
        vm.stopPrank();
    }

    /**
     * @dev Edge case where it is not possible to sell less than the minimum amount because would lead to 0 DUSD.
     */
    function testGetAssetAmountForSellAssetBelowMinimumAmount() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 18);
        FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(4900, 4900, address(this));
        FixedPriceStrategy newPriceStrategy =
            new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: 100_000_000e18,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        gsm.updateFeeRecipient(FEE_RECIPIENT);
        gsm.updateFeeStrategy(address(newFeeStrategy));
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        // Get asset amount required to receive 1DUSD
        (uint256 assetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) = gsm.getAssetAmountForSellAsset(1);

        assertEq(assetAmount, 2, "Unexpected asset to sell");
        assertEq(dusdBought, 1, "Unexpected dusd amount bought");
        assertEq(grossAmount, 2, "Unexpected gross amount");
        assertEq(fee, 1, "Unexpected fee");

        // Using 1 wei less than the assetAmount will round down the asset amount to 0, so should revert
        vm.expectRevert("INVALID_AMOUNT");
        gsm.sellAsset(assetAmount - 1, address(this));

        _sellAsset(gsm, newToken, ALICE, assetAmount);
        assertEq(DUSD_TOKEN.balanceOf(ALICE), 1, "Unexpected DUSD balance");
    }

    /**
     * @dev Sell asset function meets the maximum amount to be sold and does not over-charge the user.
     * e.g. if the GSM can provide 10 DUSD for 12 assets, it charges only 12 even if the user provides more than 12.
     */
    function testSellAssetWithMinimumAmount() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 18);
        FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(3000, 3000, address(this));
        FixedPriceStrategy newPriceStrategy =
            new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(newToken), address(this));
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: 100_000_000e18,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        gsm.updateFeeRecipient(FEE_RECIPIENT);
        gsm.updateFeeStrategy(address(newFeeStrategy));
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        // Get asset amount required to receive 10000DUSD
        (uint256 assetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            gsm.getAssetAmountForSellAsset(10000);

        assertEq(assetAmount, 14286, "Unexpected asset to sell");
        assertEq(dusdBought, 10000, "Unexpected dusd amount bought");
        assertEq(grossAmount, 14286, "Unexpected gross amount");
        assertEq(fee, 4286, "Unexpected fee");

        assertEq(newToken.balanceOf(ALICE), 0, "Unexpected asset amount before");

        // Mint 1 more asset than required (14286) to receive 10000DUSD
        vm.prank(FAUCET);
        newToken.mint(ALICE, assetAmount + 1);

        vm.startPrank(ALICE);
        newToken.approve(address(gsm), assetAmount);
        // Sell 1 more asset than required to receive 10000DUSD
        gsm.sellAsset(assetAmount + 1, ALICE);
        vm.stopPrank();
        assertEq(DUSD_TOKEN.balanceOf(ALICE), 10000, "Unexpected DUSD balance");
        // Should have 1 "leftover" asset, as sellAsset prevents "overpaying" so only assetAmount spent
        assertEq(newToken.balanceOf(ALICE), 1, "Unexpected ending asset amount");
    }

    /**
     * @dev Checks sellAsset does not charge more asset than needed
     * in case the underlying asset has more decimals than DUSD (18)
     */
    function testSellAssetWithHigherDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 24);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e24);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e24,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        vm.startPrank(ALICE);
        newToken.approve(address(gsm), type(uint256).max);

        // Less than 1e6 results in 0DUSD
        vm.expectRevert("INVALID_AMOUNT");
        gsm.sellAsset(0.9e6, ALICE);

        // Lowest amount that can be sold is 1e6
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        gsm.sellAsset(1e6, ALICE);

        assertEq(DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, 1, "unexpected amount of DUSD purchased");
        assertEq(userAssetBefore - newToken.balanceOf(ALICE), 1e6, "unexpected amount of asset sold");

        // It does not overcharge in case of non-divisible amount of assets
        userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        userAssetBefore = newToken.balanceOf(ALICE);

        (uint256 assetAmount, uint256 dusdBought) = gsm.sellAsset(1.9e6, ALICE);

        assertEq(DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, 1, "unexpected amount of DUSD purchased");
        assertEq(dusdBought, 1, "unexpected amount of returned DUSD purchased");
        assertEq(assetAmount, 1e6, "Unexpected asset amount sold");
        assertEq(userAssetBefore - newToken.balanceOf(ALICE), 1e6, "unexpected amount of asset sold");

        vm.stopPrank();
    }

    /**
     * @dev Checks buyAsset does not provide more asset than the corresponding to the
     * dusd amount charged, in case the underlying asset has more decimals than DUSD (18)
     */
    function testBuyAssetWithHigherDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 24);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e24);
        dusdFaucet(ALICE, DEFAULT_CAPACITY);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e24,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        vm.startPrank(ALICE);
        // Alice sells some asset to the GSM
        newToken.approve(address(gsm), type(uint256).max);
        DUSD_TOKEN.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(1_000_000e24, ALICE);

        // The minimum amount of assets that can be bought is 1e6, and the contract recalculates
        // the corresponding amount of assets to the exact DUSD burned.
        // User buys more asset than it should due to price conversion
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        (uint256 assetAmount, uint256 dusdSold) = gsm.buyAsset(1.9e6, ALICE); // should by just 1e6 asset in exchange of 1DUSD

        assertEq(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE), 2, "unexpected amount of DUSD spent");
        assertEq(dusdSold, 2, "unexpected amount of returned DUSD spent");
        assertEq(assetAmount, 2e6, "Unexpected asset amount bought");
        assertEq(newToken.balanceOf(ALICE) - userAssetBefore, 2e6, "unexpected amount of assets purchased");

        vm.stopPrank();
    }

    /**
     * @dev Checks sellAsset function is aligned with getAssetAmountForSellAsset,
     * in case the underlying asset has less decimals than DUSD (18)
     */
    function testSellAssetByDusdAmountWithLowerDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 6);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e6);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e6,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        // User wants to know how much asset must sell to get 1.9e12DUSD
        vm.startPrank(ALICE);
        uint256 dusdAmountToGet = 1.9e12; // this is the minimum that must get
        (uint256 estSellAssetAmount, uint256 exactDusdToGet,,) = gsm.getAssetAmountForSellAsset(dusdAmountToGet);
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(estSellAssetAmount, ALICE);

        assertEq(
            DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, exactDusdToGet, "exact dusd amount to get does not match"
        );
        assertGt(DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, dusdAmountToGet, "minimum dusd to get not reached");

        assertEq(userAssetBefore - newToken.balanceOf(ALICE), estSellAssetAmount, "sold assets above maximum amount");

        vm.stopPrank();
    }

    /**
     * @dev Checks sellAsset function is aligned with getAssetAmountForSellAsset,
     * in case the underlying asset has more decimals than DUSD (18)
     */
    function testSellAssetByDusdAmountWithHigherDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 24);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e24);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e24,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        // User wants to know how much asset must sell to get 1DUSD
        vm.startPrank(ALICE);
        uint256 dusdAmountToGet = 1; // this is the lowest DUSD that can be purchased
        (uint256 estSellAssetAmount, uint256 exactDusdToGet,,) = gsm.getAssetAmountForSellAsset(dusdAmountToGet);
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(estSellAssetAmount, ALICE);

        assertEq(
            DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, exactDusdToGet, "exact dusd amount to get does not match"
        );
        assertEq(DUSD_TOKEN.balanceOf(ALICE) - userDusdBefore, dusdAmountToGet, "unexpected amount of DUSD purchased");
        assertEq(userAssetBefore - newToken.balanceOf(ALICE), estSellAssetAmount, "unexpected amount of asset sold");

        vm.stopPrank();
    }

    /**
     * @dev Checks buyAsset function is aligned with getAssetAmountForBuyAsset,
     * in case the underlying asset has less decimals than DUSD (18)
     */
    function testBuyAssetByDusdAmountWithLowerDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 6);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e6);
        dusdFaucet(ALICE, DEFAULT_CAPACITY);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e6,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        vm.startPrank(ALICE);
        // Alice sells some asset to the GSM
        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(1_000_000e6, ALICE);

        // User wants to know how much asset can buy with 1.9e12DUSD
        uint256 dusdAmountToSpend = 1.9e12; // this is the maximum that can spend
        (uint256 estBuyAssetAmount, uint256 exactDusdSpent,,) = gsm.getAssetAmountForBuyAsset(dusdAmountToSpend);
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        DUSD_TOKEN.approve(address(gsm), type(uint256).max);
        gsm.buyAsset(estBuyAssetAmount, ALICE);

        assertTrue(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE) <= dusdAmountToSpend, "dusd spend above maximum amount");
        assertEq(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE), exactDusdSpent, "dusd spent does not match");
        assertEq(
            newToken.balanceOf(ALICE) - userAssetBefore, estBuyAssetAmount, "bought assets and amount diff do not match"
        );

        vm.stopPrank();
    }

    /**
     * @dev Checks buyAsset function is aligned with getAssetAmountForBuyAsset,
     * in case the underlying asset has more decimals than DUSD (18)
     */
    function testBuyAssetByDusdAmountWithHigherDecimals() public {
        ERC20MockMintableDecimals newToken = new ERC20MockMintableDecimals("Test Coin", "TEST", 24);
        vm.prank(FAUCET);
        newToken.mint(ALICE, 1_000_000e24);
        dusdFaucet(ALICE, DEFAULT_CAPACITY);

        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, // 1e18
            address(newToken),
            address(this)
        );
        DUSDUsm gsm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(newToken),
            DusdUsmInitParams({
                admin: ALICE,
                stableTokenTreasury: TREASURY,
                exposureCap: 1_000_000e24,
                priceStrategy: address(newPriceStrategy),
                accessMode: AccessMode.PERMISSIONLESS,
                feeRecipient: FEE_RECIPIENT
            })
        );
        DUSD_TOKEN.setMinterStatus(address(gsm), true);
        DUSD_TOKEN.setBurnerStatus(address(gsm), true);
        DUSD_TOKEN.setMinterCeiling(address(gsm), DEFAULT_CAPACITY);

        vm.startPrank(ALICE);
        // Alice sells some asset to the GSM
        newToken.approve(address(gsm), type(uint256).max);
        gsm.sellAsset(1_000_000e24, ALICE);

        // User wants to know how much asset can buy with 1DUSD
        uint256 dusdAmountToSpend = 1; // this is the lowest amount that can spend
        (uint256 estBuyAssetAmount, uint256 exactDusdSpent,,) = gsm.getAssetAmountForBuyAsset(dusdAmountToSpend);
        uint256 userDusdBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 userAssetBefore = newToken.balanceOf(ALICE);

        DUSD_TOKEN.approve(address(gsm), type(uint256).max);
        gsm.buyAsset(estBuyAssetAmount, ALICE);

        assertEq(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE), exactDusdSpent, "exact dusd spent does not match");
        assertEq(userDusdBefore - DUSD_TOKEN.balanceOf(ALICE), dusdAmountToSpend, "unexpected amount of DUSD spent");
        assertEq(
            newToken.balanceOf(ALICE) - userAssetBefore, estBuyAssetAmount, "unexpected amount of assets purchased"
        );

        vm.stopPrank();
    }
}
