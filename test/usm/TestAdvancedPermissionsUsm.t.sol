// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestDusdBase} from "./TestDusdBase.t.sol";
import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {IAdvancedPermissionsUsm, DirectionAccess} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TestAdvancedPermissionsUsm is TestDusdBase {
    AdvancedPermissionsFeeStrategy FEE_STRATEGY;

    /// Main USM used for fee, quote, update, and general swap tests
    DUSDAdvancedPermissionsUsm USM;

    /// Access-specific USMs
    DUSDAdvancedPermissionsUsm PERMISSIONED_BUY_USM; // PERMISSIONED buy / PERMISSIONLESS sell
    DUSDAdvancedPermissionsUsm PERMISSIONED_SELL_USM; // PERMISSIONLESS buy / PERMISSIONED sell (pre-seeded)

    bytes32 constant BUY_SWAPPER_ROLE = keccak256("BUY_SWAPPER_ROLE");
    bytes32 constant SELL_SWAPPER_ROLE = keccak256("SELL_SWAPPER_ROLE");

    // Fee tiers (basis points)
    uint16 constant BUY_FEE = 100; // 1%    – default
    uint16 constant SELL_FEE = 200; // 2%    – default
    uint16 constant ROLE_BUY_FEE = 50; // 0.5%  – BOB (BUY_SWAPPER_ROLE holder)
    uint16 constant ROLE_SELL_FEE = 100; // 1%    – BOB (SELL_SWAPPER_ROLE holder)
    uint16 constant OVERRIDE_BUY_FEE = 75; // 0.75% – CHARLES (address override)
    uint16 constant OVERRIDE_SELL_FEE = 125; // 1.25% – CHARLES (address override)

    // Derived fee amounts for DEFAULT_USM_DUSD_AMOUNT = 100e18 at 1:1 price
    uint256 constant ALICE_BUY_FEE = 1e18; // 100e18 * 100 / 10000
    uint256 constant ALICE_SELL_FEE = 2e18; // 100e18 * 200 / 10000
    uint256 constant BOB_BUY_FEE = 0.5e18; // 100e18 *  50 / 10000
    uint256 constant BOB_SELL_FEE = 1e18; // 100e18 * 100 / 10000
    uint256 constant CHARLES_BUY_FEE = 0.75e18; // 100e18 *  75 / 10000
    uint256 constant CHARLES_SELL_FEE = 1.25e18; // 100e18 * 125 / 10000

    function setUp() public override {
        FEE_STRATEGY = new AdvancedPermissionsFeeStrategy(BUY_FEE, SELL_FEE, address(this));
        FEE_STRATEGY.setBuyFeeByRoleHash(BUY_SWAPPER_ROLE, _feeData(ROLE_BUY_FEE));
        FEE_STRATEGY.setSellFeeByRoleHash(SELL_SWAPPER_ROLE, _feeData(ROLE_SELL_FEE));
        FEE_STRATEGY.overrideBuyFee(CHARLES, _feeData(OVERRIDE_BUY_FEE));
        FEE_STRATEGY.overrideSellFee(CHARLES, _feeData(OVERRIDE_SELL_FEE));
        FEE_STRATEGY.setUserBuyFeeRole(BOB, BUY_SWAPPER_ROLE);
        FEE_STRATEGY.setUserSellFeeRole(BOB, SELL_SWAPPER_ROLE);

        // Main USM - buy and sell are PERMISSIONLESS
        USM = _makeUsm(DirectionAccess.PERMISSIONLESS, DirectionAccess.PERMISSIONLESS);

        // Access-specific USMs
        PERMISSIONED_BUY_USM = _makeUsm(DirectionAccess.PERMISSIONED, DirectionAccess.PERMISSIONLESS);
        PERMISSIONED_SELL_USM = _makeUsm(DirectionAccess.PERMISSIONLESS, DirectionAccess.PERMISSIONED);

        // PERMISSIONED_SELL_USM: seed via BOB who holds SELL_SWAPPER_ROLE
        _seedLiquidityAs(PERMISSIONED_SELL_USM, BOB, DEFAULT_USM_USDC_AMOUNT);
    }

    function testConstructor() public {
        DUSDAdvancedPermissionsUsm usm = new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        assertEq(usm.STABLE_TOKEN(), address(DUSD_TOKEN));
        assertEq(usm.UNDERLYING_ASSET(), address(USDC_TOKEN));
        assertEq(usm.getExposureCap(), 0);
    }

    function testRevertConstructorZeroAddress() public {
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new DUSDAdvancedPermissionsUsm(address(0), address(USDC_TOKEN));
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(0));
    }

    function testInitialize() public {
        DUSDAdvancedPermissionsUsm usm = _deployUsm(DirectionAccess.PERMISSIONED, DirectionAccess.PERMISSIONLESS);
        assertEq(usm.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE);
        assertEq(uint8(usm.getBuyAccess()), uint8(DirectionAccess.PERMISSIONED));
        assertEq(uint8(usm.getSellAccess()), uint8(DirectionAccess.PERMISSIONLESS));
        assertEq(usm.USM_REVISION(), 1);
    }

    function testInitialize_EmitsAccessConfigUpdated() public {
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""
        );
        vm.expectEmit(false, false, false, true, proxy);
        emit IAdvancedPermissionsUsm.AccessConfigUpdated(DirectionAccess.PERMISSIONED, DirectionAccess.PERMISSIONED);
        DUSDAdvancedPermissionsUsm(proxy)
            .initialize(
                address(this),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                DirectionAccess.PERMISSIONED,
                DirectionAccess.PERMISSIONED
            );
    }

    function testRevertInitializeZeroAdmin() public {
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""
        );
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        DUSDAdvancedPermissionsUsm(proxy)
            .initialize(
                address(0),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                DirectionAccess.PERMISSIONLESS,
                DirectionAccess.PERMISSIONLESS
            );
    }

    function testRevertInitializeTreasuryZeroAddress() public {
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""
        );
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        DUSDAdvancedPermissionsUsm(proxy)
            .initialize(
                address(this),
                address(0),
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                DirectionAccess.PERMISSIONLESS,
                DirectionAccess.PERMISSIONLESS
            );
    }

    function testRevertInitializeInvalidPriceStrategy() public {
        FixedPriceStrategy wrongStrategy = new FixedPriceStrategy(1e18, address(DUSD_TOKEN), address(this));
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""
        );
        vm.expectRevert("INVALID_PRICE_STRATEGY");
        DUSDAdvancedPermissionsUsm(proxy)
            .initialize(
                address(this),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(wrongStrategy),
                DirectionAccess.PERMISSIONLESS,
                DirectionAccess.PERMISSIONLESS
            );
    }

    function testRevertInitializeTwice() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        USM.initialize(
            address(this),
            TREASURY,
            DEFAULT_USM_USDC_EXPOSURE,
            address(DUSD_USM_FIXED_PRICE_STRATEGY),
            DirectionAccess.PERMISSIONLESS,
            DirectionAccess.PERMISSIONLESS
        );
    }

    function testRevertInitializeOnImplementation() public {
        DUSDAdvancedPermissionsUsm impl = new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        impl.initialize(
            address(this),
            TREASURY,
            DEFAULT_USM_USDC_EXPOSURE,
            address(DUSD_USM_FIXED_PRICE_STRATEGY),
            DirectionAccess.PERMISSIONLESS,
            DirectionAccess.PERMISSIONLESS
        );
    }

    function testGetBuyAccess_InitializedCorrectly() public view {
        assertEq(uint8(USM.getBuyAccess()), uint8(DirectionAccess.PERMISSIONLESS));
        assertEq(uint8(PERMISSIONED_BUY_USM.getBuyAccess()), uint8(DirectionAccess.PERMISSIONED));
    }

    function testGetSellAccess_InitializedCorrectly() public view {
        assertEq(uint8(USM.getSellAccess()), uint8(DirectionAccess.PERMISSIONLESS));
        assertEq(uint8(PERMISSIONED_SELL_USM.getSellAccess()), uint8(DirectionAccess.PERMISSIONED));
    }

    function testUpdateBuyAccess_OnlyConfigurator() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        USM.updateBuyAccess(DirectionAccess.PERMISSIONED);

        vm.expectEmit(false, false, false, true, address(USM));
        emit IAdvancedPermissionsUsm.AccessConfigUpdated(DirectionAccess.PERMISSIONED, DirectionAccess.PERMISSIONLESS);
        USM.updateBuyAccess(DirectionAccess.PERMISSIONED);

        assertEq(uint8(USM.getBuyAccess()), uint8(DirectionAccess.PERMISSIONED));
        assertEq(uint8(USM.getSellAccess()), uint8(DirectionAccess.PERMISSIONLESS));
    }

    function testUpdateSellAccess_OnlyConfigurator() public {
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        USM.updateSellAccess(DirectionAccess.PERMISSIONED);

        vm.expectEmit(false, false, false, true, address(USM));
        emit IAdvancedPermissionsUsm.AccessConfigUpdated(DirectionAccess.PERMISSIONLESS, DirectionAccess.PERMISSIONED);
        USM.updateSellAccess(DirectionAccess.PERMISSIONED);

        assertEq(uint8(USM.getBuyAccess()), uint8(DirectionAccess.PERMISSIONLESS));
        assertEq(uint8(USM.getSellAccess()), uint8(DirectionAccess.PERMISSIONED));
    }

    function testRevertUpdateBuyAccess_SameAccess() public {
        vm.expectRevert("SAME_ACCESS");
        USM.updateBuyAccess(DirectionAccess.PERMISSIONLESS); // already PERMISSIONLESS
    }

    function testRevertUpdateSellAccess_SameAccess() public {
        vm.expectRevert("SAME_ACCESS");
        USM.updateSellAccess(DirectionAccess.PERMISSIONLESS); // already PERMISSIONLESS
    }

    function testUpdateBuyAccess_ChangesSwapBehavior() public {
        _seedLiquidity(DEFAULT_USM_USDC_AMOUNT);

        // After restricting to PERMISSIONED, non-role user is blocked
        USM.updateBuyAccess(DirectionAccess.PERMISSIONED);
        dusdFaucet(ALICE, DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(USM), DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.expectRevert("NOT PERMISSIONED");
        USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // After loosening back to PERMISSIONLESS, the same user succeeds
        USM.updateBuyAccess(DirectionAccess.PERMISSIONLESS);
        vm.prank(ALICE);
        USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        assertEq(USDC_TOKEN.balanceOf(ALICE), DEFAULT_USM_USDC_AMOUNT);
    }

    function testBuyAsset_Permissionless_AnyoneCanBuy() public {
        _seedLiquidity(DEFAULT_USM_USDC_AMOUNT);
        dusdFaucet(ALICE, DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(USM), DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        (uint256 assetOut,) = USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
        assertEq(assetOut, DEFAULT_USM_USDC_AMOUNT);
    }

    function testRevertBuyAsset_Permissioned_NoRole() public {
        // PERMISSIONED_BUY_USM: buy is PERMISSIONED, ALICE has no BUY_SWAPPER_ROLE
        vm.prank(ALICE);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_BUY_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
    }

    function testBuyAsset_Permissioned_WithRole() public {
        // BOB has BUY_SWAPPER_ROLE on PERMISSIONED_BUY_USM
        _seedLiquidityAs(PERMISSIONED_BUY_USM, FAUCET, DEFAULT_USM_USDC_AMOUNT);
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(PERMISSIONED_BUY_USM), DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        (uint256 assetOut,) = PERMISSIONED_BUY_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
        assertEq(assetOut, DEFAULT_USM_USDC_AMOUNT);
    }

    function testSellAsset_Permissionless_AnyoneCanSell() public {
        _mintUsdcAndApprove(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.prank(ALICE);
        (, uint256 dusdOut) = USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        assertEq(dusdOut, DEFAULT_USM_DUSD_AMOUNT - ALICE_SELL_FEE);
    }

    function testRevertSellAsset_Permissioned_NoRole() public {
        // PERMISSIONED_SELL_USM: sell is PERMISSIONED, ALICE has no SELL_SWAPPER_ROLE
        vm.prank(ALICE);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_SELL_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
    }

    function testSellAsset_Permissioned_WithRole() public {
        // BOB has SELL_SWAPPER_ROLE on PERMISSIONED_SELL_USM
        vm.prank(FAUCET);
        USDC_TOKEN.mint(BOB, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(BOB);
        USDC_TOKEN.approve(address(PERMISSIONED_SELL_USM), DEFAULT_USM_USDC_AMOUNT);
        (, uint256 dusdOut) = PERMISSIONED_SELL_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
        assertEq(dusdOut, DEFAULT_USM_DUSD_AMOUNT - BOB_SELL_FEE);
    }

    function testBuyPermissioned_SellPermissionless() public {
        // PERMISSIONED_BUY_USM: sell is open for anyone, buy requires BUY_SWAPPER_ROLE
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(PERMISSIONED_BUY_USM), DEFAULT_USM_USDC_AMOUNT);
        (, uint256 dusdOut) = PERMISSIONED_BUY_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
        assertGt(dusdOut, 0);

        // ALICE cannot buy (no BUY_SWAPPER_ROLE)
        dusdFaucet(ALICE, DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(PERMISSIONED_BUY_USM), DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_BUY_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // BOB (has BUY_SWAPPER_ROLE) can buy
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(PERMISSIONED_BUY_USM), DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        (uint256 assetOut,) = PERMISSIONED_BUY_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
        assertEq(assetOut, DEFAULT_USM_USDC_AMOUNT);
    }

    function testSellPermissioned_BuyPermissionless() public {
        // PERMISSIONED_SELL_USM: buy is open for anyone, sell requires SELL_SWAPPER_ROLE

        // ALICE can buy (no role needed)
        dusdFaucet(ALICE, DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(PERMISSIONED_SELL_USM), DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        (uint256 assetOut,) = PERMISSIONED_SELL_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
        assertEq(assetOut, DEFAULT_USM_USDC_AMOUNT);

        // ALICE cannot sell (no SELL_SWAPPER_ROLE)
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(PERMISSIONED_SELL_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_SELL_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // BOB (has SELL_SWAPPER_ROLE) can sell
        vm.prank(FAUCET);
        USDC_TOKEN.mint(BOB, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(BOB);
        USDC_TOKEN.approve(address(PERMISSIONED_SELL_USM), DEFAULT_USM_USDC_AMOUNT);
        (, uint256 dusdOut) = PERMISSIONED_SELL_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
        assertGt(dusdOut, 0);
    }

    function testSellAsset_ThreeFeeUsers_FeeTiersApplied() public {
        uint256 aliceFee = _doSell(ALICE, DEFAULT_USM_USDC_AMOUNT); // default  2%
        uint256 bobFee = _doSell(BOB, DEFAULT_USM_USDC_AMOUNT); // role     1%
        uint256 charlesFee = _doSell(CHARLES, DEFAULT_USM_USDC_AMOUNT); // override 1.25%

        assertEq(aliceFee, ALICE_SELL_FEE, "ALICE default sell fee");
        assertEq(bobFee, BOB_SELL_FEE, "BOB role sell fee");
        assertEq(charlesFee, CHARLES_SELL_FEE, "CHARLES override sell fee");

        assertGt(aliceFee, charlesFee); // ALICE > CHARLES > BOB
        assertGt(charlesFee, bobFee);
    }

    function testBuyAsset_ThreeFeeUsers_FeeTiersApplied() public {
        _seedLiquidity(3 * DEFAULT_USM_USDC_AMOUNT);

        uint256 aliceFee = _doBuy(ALICE, DEFAULT_USM_USDC_AMOUNT); // default  1%
        uint256 bobFee = _doBuy(BOB, DEFAULT_USM_USDC_AMOUNT); // role     0.5%
        uint256 charlesFee = _doBuy(CHARLES, DEFAULT_USM_USDC_AMOUNT); // override 0.75%

        assertEq(aliceFee, ALICE_BUY_FEE, "ALICE default buy fee");
        assertEq(bobFee, BOB_BUY_FEE, "BOB role buy fee");
        assertEq(charlesFee, CHARLES_BUY_FEE, "CHARLES override buy fee");

        assertGt(aliceFee, charlesFee); // ALICE > CHARLES > BOB
        assertGt(charlesFee, bobFee);
    }

    function testSellAsset_EmitsSellAssetEvent_WithCorrectFee() public {
        _mintUsdcAndApprove(BOB, DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(USM));
        emit IAdvancedPermissionsUsm.SellAsset(BOB, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, BOB_SELL_FEE);
        vm.prank(BOB);
        USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
    }

    function testBuyAsset_EmitsBuyAssetEvent_WithCorrectFee() public {
        _seedLiquidity(DEFAULT_USM_USDC_AMOUNT);
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(USM), DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE);
        vm.expectEmit(true, true, true, true, address(USM));
        emit IAdvancedPermissionsUsm.BuyAsset(
            BOB, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT + BOB_BUY_FEE, BOB_BUY_FEE
        );
        USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
    }

    function testQuoteForSell_ReflectsUserFee() public {
        (, uint256 aliceDusd,, uint256 aliceFee) = USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        (, uint256 bobDusd,, uint256 bobFee) = USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        (, uint256 charlesDusd,, uint256 charlesFee) =
            USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, CHARLES);

        assertEq(aliceFee, ALICE_SELL_FEE, "ALICE quoted sell fee");
        assertEq(bobFee, BOB_SELL_FEE, "BOB quoted sell fee");
        assertEq(charlesFee, CHARLES_SELL_FEE, "CHARLES quoted sell fee");

        assertGt(bobDusd, charlesDusd); // lower fee → more DUSD received
        assertGt(charlesDusd, aliceDusd);
    }

    function testQuoteForBuy_ReflectsUserFee() public {
        (, uint256 aliceDusd,, uint256 aliceFee) = USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        (, uint256 bobDusd,, uint256 bobFee) = USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        (, uint256 charlesDusd,, uint256 charlesFee) =
            USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, CHARLES);

        assertEq(aliceFee, ALICE_BUY_FEE, "ALICE quoted buy fee");
        assertEq(bobFee, BOB_BUY_FEE, "BOB quoted buy fee");
        assertEq(charlesFee, CHARLES_BUY_FEE, "CHARLES quoted buy fee");

        assertGt(aliceDusd, charlesDusd); // lower fee → less DUSD spent
        assertGt(charlesDusd, bobDusd);
    }

    function testGetAssetAmountForSell_ConsistentWithSellQuote() public {
        (, uint256 dusdBought,, uint256 fee) = USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        (uint256 assetAmount, uint256 exactDusdBought,, uint256 fee2) =
            USM.getAssetAmountForSellAsset(dusdBought, ALICE);
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT);
        assertEq(exactDusdBought, dusdBought);
        assertEq(fee, fee2);
    }

    function testGetAssetAmountForBuy_ConsistentWithBuyQuote() public {
        (, uint256 dusdSold,, uint256 fee) = USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        (uint256 assetAmount, uint256 exactDusdSold,, uint256 fee2) = USM.getAssetAmountForBuyAsset(dusdSold, ALICE);
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT);
        assertEq(exactDusdSold, dusdSold);
        assertEq(fee, fee2);
    }

    function testSellAsset_ActualMatchesQuote() public {
        (, uint256 quotedDusd,,) = USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        _mintUsdcAndApprove(BOB, DEFAULT_USM_USDC_AMOUNT);
        vm.prank(BOB);
        (, uint256 actualDusd) = USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        assertEq(actualDusd, quotedDusd);
    }

    function testBuyAsset_ActualMatchesQuote() public {
        _seedLiquidity(DEFAULT_USM_USDC_AMOUNT);
        (, uint256 quotedDusd,,) = USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        dusdFaucet(BOB, quotedDusd);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(USM), quotedDusd);
        (, uint256 actualDusd) = USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
        assertEq(actualDusd, quotedDusd);
    }

    function testRoleConstants() public view {
        assertEq(USM.BUY_SWAPPER_ROLE(), BUY_SWAPPER_ROLE);
        assertEq(USM.SELL_SWAPPER_ROLE(), SELL_SWAPPER_ROLE);
        assertEq(USM.CONFIGURATOR_ROLE(), USM_CONFIGURATOR_ROLE);
        assertEq(USM.USM_REVISION(), 1);
        // Verify buy and sell roles are distinct
        assertTrue(BUY_SWAPPER_ROLE != SELL_SWAPPER_ROLE, "roles should be distinct");
    }

    function testRoleIsolation_BuyRoleDoesNotGrantSellAccess() public {
        // Create a USM where buy is PERMISSIONLESS but sell is PERMISSIONED
        DUSDAdvancedPermissionsUsm usm = _makeUsm(DirectionAccess.PERMISSIONLESS, DirectionAccess.PERMISSIONED);

        // Grant only BUY_SWAPPER_ROLE to ALICE (not SELL_SWAPPER_ROLE)
        usm.grantRole(BUY_SWAPPER_ROLE, ALICE);

        // ALICE should NOT be able to sell (sell requires SELL_SWAPPER_ROLE)
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(usm), DEFAULT_USM_USDC_AMOUNT);
        vm.expectRevert("NOT PERMISSIONED");
        usm.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
    }

    function testRoleIsolation_SellRoleDoesNotGrantBuyAccess() public {
        // Create a USM where sell is PERMISSIONLESS but buy is PERMISSIONED
        DUSDAdvancedPermissionsUsm usm = _makeUsm(DirectionAccess.PERMISSIONED, DirectionAccess.PERMISSIONLESS);
        _seedLiquidityAs(usm, FAUCET, DEFAULT_USM_USDC_AMOUNT);

        // Grant only SELL_SWAPPER_ROLE to ALICE (not BUY_SWAPPER_ROLE)
        usm.grantRole(SELL_SWAPPER_ROLE, ALICE);

        // ALICE should NOT be able to buy (buy requires BUY_SWAPPER_ROLE)
        dusdFaucet(ALICE, DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(usm), DEFAULT_USM_DUSD_AMOUNT + ALICE_BUY_FEE);
        vm.expectRevert("NOT PERMISSIONED");
        usm.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
    }

    function testQuoteWorks_EvenWhenPermissioned() public {
        // PERMISSIONED_BUY_USM has buy PERMISSIONED, but quotes are pure view functions open to anyone
        (, uint256 buyDusd,,) = PERMISSIONED_BUY_USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        assertGt(buyDusd, 0, "buy quote should work");

        (, uint256 sellDusd,,) = PERMISSIONED_BUY_USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        assertGt(sellDusd, 0, "sell quote should work");

        (uint256 buyAsset,,,) = PERMISSIONED_BUY_USM.getAssetAmountForBuyAsset(DEFAULT_USM_DUSD_AMOUNT, ALICE);
        assertGt(buyAsset, 0, "getAssetAmountForBuyAsset should work");

        (uint256 sellAsset,,,) = PERMISSIONED_BUY_USM.getAssetAmountForSellAsset(DEFAULT_USM_DUSD_AMOUNT, ALICE);
        assertGt(sellAsset, 0, "getAssetAmountForSellAsset should work");
    }

    /// @dev Deploy a bare USM proxy (no fee strategy, no roles beyond admin)
    function _deployUsm(DirectionAccess buy, DirectionAccess sell) internal returns (DUSDAdvancedPermissionsUsm) {
        address impl = address(new DUSDAdvancedPermissionsUsm(address(DUSD_TOKEN), address(USDC_TOKEN)));
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            impl,
            abi.encodeCall(
                DUSDAdvancedPermissionsUsm.initialize,
                (address(this), TREASURY, DEFAULT_USM_USDC_EXPOSURE, address(DUSD_USM_FIXED_PRICE_STRATEGY), buy, sell)
            )
        );
        DUSDAdvancedPermissionsUsm usm = DUSDAdvancedPermissionsUsm(proxy);
        DUSD_TOKEN.setMinterStatus(address(usm), true);
        DUSD_TOKEN.setMinterCeiling(address(usm), DEFAULT_CAPACITY);
        DUSD_TOKEN.setBurnerStatus(address(usm), true);
        return usm;
    }

    /// @dev Deploy a ready-to-use USM: fee strategy wired, BOB granted both swapper roles
    function _makeUsm(DirectionAccess buy, DirectionAccess sell) internal returns (DUSDAdvancedPermissionsUsm) {
        DUSDAdvancedPermissionsUsm usm = _deployUsm(buy, sell);
        usm.updateFeeRecipient(FEE_RECIPIENT);
        usm.updateFeeStrategy(address(FEE_STRATEGY));
        usm.grantRole(BUY_SWAPPER_ROLE, BOB);
        usm.grantRole(SELL_SWAPPER_ROLE, BOB);
        return usm;
    }

    /// @dev Mint USDC to `user` and approve the main USM
    function _mintUsdcAndApprove(address user, uint256 amount) internal {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(user, amount);
        vm.prank(user);
        USDC_TOKEN.approve(address(USM), amount);
    }

    /// @dev Seed liquidity into the main USM (requires sell to be PERMISSIONLESS)
    function _seedLiquidity(uint256 usdcAmount) internal {
        _seedLiquidityAs(USM, FAUCET, usdcAmount);
    }

    /// @dev Seed `usm` with USDC via a specific `seller`; DUSD minted to FAUCET to avoid balance side-effects
    function _seedLiquidityAs(DUSDAdvancedPermissionsUsm usm, address seller, uint256 usdcAmount) internal {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(seller, usdcAmount);
        vm.startPrank(seller);
        USDC_TOKEN.approve(address(usm), usdcAmount);
        usm.sellAsset(usdcAmount, FAUCET); // receiver = FAUCET so user balances stay clean
        vm.stopPrank();
    }

    /// @dev Sell `usdcAmount` on the main USM as `user`. Returns fee paid.
    function _doSell(address user, uint256 usdcAmount) internal returns (uint256 fee) {
        (,, uint256 gross, uint256 expectedFee) = USM.getStableTokenAmountForSellAsset(usdcAmount, user);
        _mintUsdcAndApprove(user, usdcAmount);
        vm.prank(user);
        USM.sellAsset(usdcAmount, user);
        assertEq(DUSD_TOKEN.balanceOf(user), gross - expectedFee, "sell: dusd balance mismatch");
        return expectedFee;
    }

    /// @dev Buy `usdcAmount` on the main USM as `user`; funds via quote. Returns fee paid.
    function _doBuy(address user, uint256 usdcAmount) internal returns (uint256 fee) {
        (, uint256 totalDusd,, uint256 expectedFee) = USM.getStableTokenAmountForBuyAsset(usdcAmount, user);
        dusdFaucet(user, totalDusd);
        vm.startPrank(user);
        DUSD_TOKEN.approve(address(USM), totalDusd);
        USM.buyAsset(usdcAmount, user);
        vm.stopPrank();
        assertEq(USDC_TOKEN.balanceOf(user), usdcAmount, "buy: usdc balance mismatch");
        return expectedFee;
    }

    function _feeData(uint256 fee) internal pure returns (IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory) {
        return IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: uint16(fee)});
    }
}
