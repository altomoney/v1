// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Usm} from "@alto/usm/Usm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestDusdBase} from "./TestDusdBase.t.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {DusdUsmInitParams} from "@alto-test/helpers/UsmDeployer.sol";
import {IAuth, Authorization, Signature} from "@alto/utils/interfaces/IAuth.sol";
import {SigUtils} from "@alto-test/helpers/SigUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";

contract TestUsm is TestDusdBase {
    using PercentageMath for uint256;
    using PercentageMath for uint128;

    address internal usmSignerAddr;
    uint256 internal usmSignerKey;

    function setUp() public override {
        (usmSignerAddr, usmSignerKey) = makeAddrAndKey("usmSigner");
    }

    function testConstructor() public {
        DUSDUsm usm = new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        assertEq(usm.STABLE_TOKEN(), address(DUSD_TOKEN), "Unexpected DUSD token address");
        assertEq(usm.UNDERLYING_ASSET(), address(USDC_TOKEN), "Unexpected underlying asset address");
        assertEq(usm.getExposureCap(), 0, "Unexpected exposure capacity");
        assertEq(uint8(usm.USM_TYPE()), uint8(UsmType.STANDARD));
    }

    function testRevertInitializeOnImplementation() public {
        DUSDUsm usm = new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN));
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        DUSDUsm(usm)
            .initialize(
                address(this),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                AccessMode.PERMISSIONLESS
            );
    }

    function testRevertInitializeInvalidPriceStrategy() public {
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(1e18, address(DUSD_TOKEN), address(this));
        DUSDUsm usm =
            DUSDUsm(UnsafeUpgrades.deployUUPSProxy(address(new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""));
        vm.expectRevert("INVALID_PRICE_STRATEGY");
        DUSDUsm(usm)
            .initialize(
                address(this), TREASURY, DEFAULT_USM_USDC_EXPOSURE, address(newPriceStrategy), AccessMode.PERMISSIONLESS
            );
    }

    function testRevertConstructorZeroAddressParams() public {
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new DUSDUsm(address(0), address(USDC_TOKEN));

        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new DUSDUsm(address(DUSD_TOKEN), address(0));
    }

    function testInitialize() public {
        address usmProxy =
            UnsafeUpgrades.deployUUPSProxy(address(new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), "");
        DUSDUsm usm = DUSDUsm(usmProxy);
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, address(this), address(this));
        vm.expectEmit(true, true, false, true);
        emit IUsm.StableTokenTreasuryUpdated(address(0), address(TREASURY));
        vm.expectEmit(true, true, false, true);
        emit IUsm.ExposureCapUpdated(0, DEFAULT_USM_USDC_EXPOSURE);
        usm.initialize(
            address(this),
            TREASURY,
            DEFAULT_USM_USDC_EXPOSURE,
            address(DUSD_USM_FIXED_PRICE_STRATEGY),
            AccessMode.PERMISSIONLESS
        );
        usm.updateFeeRecipient(FEE_RECIPIENT);
        assertEq(usm.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testRevertInitializeZeroAdmin() public {
        DUSDUsm usm =
            DUSDUsm(UnsafeUpgrades.deployUUPSProxy(address(new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""));
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        DUSDUsm(usm)
            .initialize(
                address(0),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                AccessMode.PERMISSIONLESS
            );
    }

    function testRevertInitializeTwice() public {
        address usmProxy = UnsafeUpgrades.deployUUPSProxy(
            address(new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN))),
            abi.encodeCall(
                DUSDUsm.initialize,
                (
                    address(this),
                    TREASURY,
                    DEFAULT_USM_USDC_EXPOSURE,
                    address(DUSD_USM_FIXED_PRICE_STRATEGY),
                    AccessMode.PERMISSIONLESS
                )
            )
        );
        DUSDUsm usm = DUSDUsm(usmProxy);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        DUSDUsm(usm)
            .initialize(
                address(this),
                TREASURY,
                DEFAULT_USM_USDC_EXPOSURE,
                address(DUSD_USM_FIXED_PRICE_STRATEGY),
                AccessMode.PERMISSIONLESS
            );
    }

    function testSellAssetZeroFee() public {
        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.FeeStrategyUpdated(address(DUSD_USM_FIXED_FEE_STRATEGY), address(0));
        DUSD_USM.updateFeeStrategy(address(0));

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, 0);
        (uint256 assetAmount, uint256 dusdBought) = DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        assertEq(dusdBought, DEFAULT_USM_DUSD_AMOUNT, "Unexpected DUSD amount bought");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount sold");
        assertEq(USDC_TOKEN.balanceOf(ALICE), 0, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), DEFAULT_USM_DUSD_AMOUNT, "Unexpected final DUSD balance");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testSellAsset() public {
        uint256 fee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT - fee;

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, fee);
        (uint256 assetAmount, uint256 dusdBought) = DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        assertEq(dusdBought, DEFAULT_USM_DUSD_AMOUNT - fee, "Unexpected DUSD amount bought");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount sold");
        assertEq(USDC_TOKEN.balanceOf(ALICE), 0, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), dusdOut, "Unexpected final DUSD balance");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testSellAssetPermissioned() public {
        uint256 fee = 0;
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT;

        vm.prank(FAUCET);
        USDC_TOKEN.mint(multisigTreasury, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(multisigTreasury);
        USDC_TOKEN.approve(address(PERMISSIONED_DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(PERMISSIONED_DUSD_USM));
        emit IUsm.SellAsset(multisigTreasury, multisigTreasury, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, 0);
        (uint256 assetAmount, uint256 dusdBought) =
            PERMISSIONED_DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, multisigTreasury);
        vm.stopPrank();

        assertEq(dusdBought, DEFAULT_USM_DUSD_AMOUNT - fee, "Unexpected DUSD amount bought");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount sold");
        assertEq(USDC_TOKEN.balanceOf(multisigTreasury), 0, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(multisigTreasury), dusdOut, "Unexpected final DUSD balance");
        assertEq(PERMISSIONED_DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testRevertSellAssetPermissionedIfNotPermissioned() public {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(multisigTreasury, DEFAULT_USM_USDC_AMOUNT);

        address notPermissioned = makeAddr("notPermissioned");
        vm.startPrank(notPermissioned);
        USDC_TOKEN.approve(address(PERMISSIONED_DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, notPermissioned);
        vm.stopPrank();
    }

    function testSellAssetSendToOther() public {
        uint256 fee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT - fee;

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, fee);
        (uint256 assetAmount, uint256 dusdBought) = DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();

        assertEq(dusdBought, DEFAULT_USM_DUSD_AMOUNT - fee, "Unexpected DUSD amount bought");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount sold");
        assertEq(USDC_TOKEN.balanceOf(ALICE), 0, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), 0, "Unexpected final DUSD balance");
        assertEq(DUSD_TOKEN.balanceOf(BOB), dusdOut, "Unexpected final DUSD balance");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testRevertSellAssetZeroAmount() public {
        vm.prank(ALICE);
        vm.expectRevert("INVALID_AMOUNT");
        DUSD_USM.sellAsset(0, ALICE);
    }

    function testRevertSellAssetNoAsset() public {
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(ALICE), 0, DEFAULT_USM_USDC_AMOUNT
            )
        );
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
    }

    function testRevertSellAssetNoAllowance() public {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(DUSD_USM), 0, DEFAULT_USM_USDC_AMOUNT
            )
        );
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
    }

    function testRevertSellAssetNoBucketCap() public {
        DUSDUsm usm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(USDC_TOKEN),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: DEFAULT_USM_USDC_EXPOSURE,
                priceStrategy: address(DUSD_USM_FIXED_PRICE_STRATEGY),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );

        DUSD_TOKEN.setMinterStatus(address(usm), true);
        DUSD_TOKEN.setMinterCeiling(address(usm), DEFAULT_CAPACITY - 1);
        uint256 defaultCapInUsdc = DEFAULT_CAPACITY / (10 ** (18 - USDC_TOKEN.decimals()));

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, defaultCapInUsdc);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(usm), defaultCapInUsdc);
        vm.expectRevert(abi.encodeWithSelector(IDUSD.DUSDInvalidInput.selector));
        usm.sellAsset(defaultCapInUsdc, ALICE);
        vm.stopPrank();
    }

    function testRevertSellAssetTooMuchUnderlyingExposure() public {
        DUSDUsm usm = deployDusdUsm(
            address(DUSD_TOKEN),
            address(USDC_TOKEN),
            DusdUsmInitParams({
                admin: address(this),
                stableTokenTreasury: TREASURY,
                exposureCap: DEFAULT_USM_USDC_EXPOSURE - 1,
                priceStrategy: address(DUSD_USM_FIXED_PRICE_STRATEGY),
                accessMode: AccessMode.PERMISSIONLESS
            })
        );
        DUSD_TOKEN.setMinterStatus(address(usm), true);
        DUSD_TOKEN.setMinterCeiling(address(usm), DEFAULT_CAPACITY);

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_EXPOSURE);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(usm), DEFAULT_USM_USDC_EXPOSURE);
        vm.expectRevert("EXOGENOUS_ASSET_EXPOSURE_TOO_HIGH");
        usm.sellAsset(DEFAULT_USM_USDC_EXPOSURE, ALICE);
        vm.stopPrank();
    }

    function testGetDusdAmountForSellAsset() public {
        (uint256 exactAssetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT);

        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);

        assertEq(
            DEFAULT_USM_USDC_AMOUNT - USDC_TOKEN.balanceOf(ALICE), exactAssetAmount, "Unexpected asset amount sold"
        );
        assertEq(dusdBought + fee, grossAmount, "Unexpected DUSD gross amount");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), dusdBought, "Unexpected DUSD bought amount");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), fee, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdBought, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForSellAsset(dusdBought);
        assertEq(DUSD_TOKEN.balanceOf(ALICE), exactDusdBought, "Unexpected DUSD bought amount");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected estimation of sold assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testGetDusdAmountForSellAssetWithZeroFee() public {
        DUSD_USM.updateFeeStrategy(address(0));

        (uint256 exactAssetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForSellAsset(DEFAULT_USM_USDC_AMOUNT);
        assertEq(fee, 0, "Unexpected DUSD fee amount");

        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);

        assertEq(
            DEFAULT_USM_USDC_AMOUNT - USDC_TOKEN.balanceOf(ALICE), exactAssetAmount, "Unexpected asset amount sold"
        );
        assertEq(dusdBought, grossAmount, "Unexpected DUSD gross amount");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), dusdBought, "Unexpected DUSD bought amount");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), 0, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdBought, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForSellAsset(dusdBought);
        assertEq(DUSD_TOKEN.balanceOf(ALICE), exactDusdBought, "Unexpected DUSD bought amount");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected estimation of sold assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testGetDusdAmountForSellAssetWithZeroAmount() public {
        (uint256 exactAssetAmount, uint256 dusdBought, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForSellAsset(0);
        assertEq(exactAssetAmount, 0, "Unexpected exact asset amount");
        assertEq(dusdBought, 0, "Unexpected DUSD bought amount");
        assertEq(grossAmount, 0, "Unexpected DUSD gross amount");
        assertEq(fee, 0, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdBought, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForSellAsset(dusdBought);
        assertEq(exactDusdBought, 0, "Unexpected exact DUSD bought");
        assertEq(assetAmount, 0, "Unexpected estimation of sold assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testBuyAssetZeroFee() public {
        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.FeeStrategyUpdated(address(DUSD_USM_FIXED_FEE_STRATEGY), address(0));
        DUSD_USM.updateFeeStrategy(address(0));

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, 0);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // Buy assets as another user
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.BuyAsset(BOB, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, 0);
        (uint256 assetAmount, uint256 dusdBought) = DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();

        assertEq(dusdBought, DEFAULT_USM_DUSD_AMOUNT, "Unexpected DUSD amount sold");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount bought");
        assertEq(USDC_TOKEN.balanceOf(BOB), DEFAULT_USM_USDC_AMOUNT, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), DEFAULT_USM_DUSD_AMOUNT, "Unexpected final DUSD balance");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testBuyAsset() public {
        uint256 sellFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 buyFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_BUY_FEE);
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT - sellFee;

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, sellFee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // Buy assets as another user
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.BuyAsset(BOB, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT + buyFee, buyFee);
        (uint256 assetAmount, uint256 dusdSold) = DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();

        assertEq(dusdSold, DEFAULT_USM_DUSD_AMOUNT + buyFee, "Unexpected DUSD amount sold");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount bought");
        assertEq(USDC_TOKEN.balanceOf(BOB), DEFAULT_USM_USDC_AMOUNT, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), dusdOut, "Unexpected final DUSD balance");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), sellFee + buyFee, "Unexpected GSM DUSD balance");
        assertEq(
            DUSD_USM.getAvailableUnderlyingExposure(),
            DEFAULT_USM_USDC_EXPOSURE,
            "Unexpected available underlying exposure"
        );
        assertEq(DUSD_USM.getAvailableLiquidity(), 0, "Unexpected available liquidity");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testBuyAssetPermissioned() public {
        uint256 sellFee = 0;
        uint256 buyFee = 0;
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT;

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(multisigTreasury, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(multisigTreasury);
        USDC_TOKEN.approve(address(PERMISSIONED_DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(PERMISSIONED_DUSD_USM));
        emit IUsm.SellAsset(
            multisigTreasury, multisigTreasury, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, sellFee
        );
        PERMISSIONED_DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, multisigTreasury);
        vm.stopPrank();

        // Buy assets as another user
        dusdFaucet(multisigTreasury, DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.startPrank(multisigTreasury);
        DUSD_TOKEN.approve(address(PERMISSIONED_DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.expectEmit(true, true, true, true, address(PERMISSIONED_DUSD_USM));
        emit IUsm.BuyAsset(
            multisigTreasury, multisigTreasury, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT + buyFee, buyFee
        );
        (uint256 assetAmount, uint256 dusdSold) =
            PERMISSIONED_DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, multisigTreasury);
        vm.stopPrank();

        assertEq(dusdSold, DEFAULT_USM_DUSD_AMOUNT + buyFee, "Unexpected DUSD amount sold");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount bought");
        assertEq(USDC_TOKEN.balanceOf(multisigTreasury), DEFAULT_USM_USDC_AMOUNT, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(multisigTreasury), dusdOut, "Unexpected final DUSD balance");
        assertEq(DUSD_TOKEN.balanceOf(address(PERMISSIONED_DUSD_USM)), sellFee + buyFee, "Unexpected GSM DUSD balance");
        assertEq(
            PERMISSIONED_DUSD_USM.getAvailableUnderlyingExposure(),
            DEFAULT_USM_USDC_EXPOSURE,
            "Unexpected available underlying exposure"
        );
        assertEq(PERMISSIONED_DUSD_USM.getAvailableLiquidity(), 0, "Unexpected available liquidity");
        assertEq(PERMISSIONED_DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testRevertBuyAssetPermissionedIfNotPermissioned() public {
        address notPermissioned = makeAddr("notPermissioned");
        vm.startPrank(notPermissioned);
        vm.expectRevert("NOT PERMISSIONED");
        PERMISSIONED_DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, notPermissioned);
        vm.stopPrank();
    }

    function testBuyAssetSendToOther() public {
        uint256 sellFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 buyFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_BUY_FEE);
        uint256 dusdOut = DEFAULT_USM_DUSD_AMOUNT - sellFee;

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, sellFee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // Buy assets as another user
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.BuyAsset(BOB, CHARLES, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT + buyFee, buyFee);
        (uint256 assetAmount, uint256 dusdSold) = DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, CHARLES);
        vm.stopPrank();

        assertEq(dusdSold, DEFAULT_USM_DUSD_AMOUNT + buyFee, "Unexpected DUSD amount sold");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected asset amount bought");
        assertEq(USDC_TOKEN.balanceOf(BOB), 0, "Unexpected final USDC balance");
        assertEq(USDC_TOKEN.balanceOf(CHARLES), DEFAULT_USM_USDC_AMOUNT, "Unexpected final USDC balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), dusdOut, "Unexpected final DUSD balance");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), sellFee + buyFee, "Unexpected GSM DUSD balance");
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure capacity");
    }

    function testRevertBuyAssetZeroAmount() public {
        vm.prank(ALICE);
        vm.expectRevert("INVALID_AMOUNT");
        DUSD_USM.buyAsset(0, ALICE);
    }

    function testRevertBuyAssetNoDUSD() public {
        uint256 sellFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 buyFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_BUY_FEE);

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, sellFee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(BOB), 0, DEFAULT_USM_DUSD_AMOUNT + buyFee
            )
        );
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
    }

    function testRevertBuyAssetNoAllowance() public {
        uint256 sellFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 buyFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_BUY_FEE);

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, sellFee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(DUSD_USM), 0, DEFAULT_USM_DUSD_AMOUNT + buyFee
            )
        );
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();
    }

    function testGetDusdAmountForBuyAsset() public {
        (uint256 exactAssetAmount, uint256 dusdSold, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT);

        uint256 topUpAmount = 1_000_000e18;
        dusdFaucet(ALICE, topUpAmount);

        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);

        uint256 dusdBalanceBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 dusdFeesBefore = DUSD_TOKEN.balanceOf(address(DUSD_USM));

        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(DUSD_USM), type(uint256).max);
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        assertEq(DEFAULT_USM_USDC_AMOUNT, exactAssetAmount, "Unexpected asset amount bought");
        assertEq(dusdSold - fee, grossAmount, "Unexpected DUSD gross sold amount");
        assertEq(dusdBalanceBefore - DUSD_TOKEN.balanceOf(ALICE), dusdSold, "Unexpected DUSD sold amount");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)) - dusdFeesBefore, fee, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdSold, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForBuyAsset(dusdSold);
        assertEq(dusdBalanceBefore - DUSD_TOKEN.balanceOf(ALICE), exactDusdSold, "Unexpected DUSD sold exact amount");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected estimation of bought assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testGetDusdAmountForBuyAssetWithZeroFee() public {
        DUSD_USM.updateFeeStrategy(address(0));

        (uint256 exactAssetAmount, uint256 dusdSold, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForBuyAsset(DEFAULT_USM_USDC_AMOUNT);
        assertEq(fee, 0, "Unexpected DUSD fee amount");

        uint256 topUpAmount = 1_000_000e18;
        dusdFaucet(ALICE, topUpAmount);

        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);

        uint256 dusdBalanceBefore = DUSD_TOKEN.balanceOf(ALICE);
        uint256 dusdFeesBefore = DUSD_TOKEN.balanceOf(address(DUSD_USM));

        vm.startPrank(ALICE);
        DUSD_TOKEN.approve(address(DUSD_USM), type(uint256).max);
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        assertEq(DEFAULT_USM_USDC_AMOUNT, exactAssetAmount, "Unexpected asset amount bought");
        assertEq(dusdSold, grossAmount, "Unexpected DUSD gross sold amount");
        assertEq(dusdBalanceBefore - DUSD_TOKEN.balanceOf(ALICE), dusdSold, "Unexpected DUSD sold amount");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), dusdFeesBefore, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdSold, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForBuyAsset(dusdSold);
        assertEq(dusdBalanceBefore - DUSD_TOKEN.balanceOf(ALICE), exactDusdSold, "Unexpected DUSD sold exact amount");
        assertEq(assetAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected estimation of bought assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testGetDusdAmountForBuyAssetWithZeroAmount() public {
        (uint256 exactAssetAmount, uint256 dusdSold, uint256 grossAmount, uint256 fee) =
            DUSD_USM.getStableTokenAmountForBuyAsset(0);
        assertEq(exactAssetAmount, 0, "Unexpected exact asset amount");
        assertEq(dusdSold, 0, "Unexpected DUSD sold amount");
        assertEq(grossAmount, 0, "Unexpected DUSD gross amount");
        assertEq(fee, 0, "Unexpected DUSD fee amount");

        (uint256 assetAmount, uint256 exactDusdSold, uint256 grossAmount2, uint256 fee2) =
            DUSD_USM.getAssetAmountForBuyAsset(dusdSold);
        assertEq(exactDusdSold, 0, "Unexpected exact dusd bought");
        assertEq(assetAmount, 0, "Unexpected estimation of bought assets");
        assertEq(grossAmount, grossAmount2, "Unexpected DUSD gross amount");
        assertEq(fee, fee2, "Unexpected DUSD fee amount");
    }

    function testSwapFreeze() public {
        assertEq(DUSD_USM.getIsFrozen(), false, "Unexpected freeze status before");
        vm.prank(address(DUSD_USM_SWAP_FREEZER));
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.SwapFreeze(address(DUSD_USM_SWAP_FREEZER), true);
        DUSD_USM.setSwapFreeze(true);
        assertEq(DUSD_USM.getIsFrozen(), true, "Unexpected freeze status after");
    }

    function testRevertFreezeNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_SWAP_FREEZER_ROLE
            )
        );
        vm.prank(ALICE);
        DUSD_USM.setSwapFreeze(true);
    }

    function testRevertUpdatePriceStrategyInvalidPriceStrategy() public {
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(WETH), address(this));
        vm.expectRevert("INVALID_PRICE_STRATEGY");
        vm.prank(address(this));
        DUSD_USM.updatePriceStrategy(address(newPriceStrategy));
    }

    function testUpdatePriceStrategy() public {
        address oldPriceStrategy = DUSD_USM.priceStrategy();
        FixedPriceStrategy newPriceStrategy = new FixedPriceStrategy(
            DEFAULT_FIXED_PRICE, FixedPriceStrategy(oldPriceStrategy).UNDERLYING_ASSET(), address(this)
        );
        vm.prank(address(this));
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.PriceStrategyUpdated(oldPriceStrategy, address(newPriceStrategy));
        DUSD_USM.updatePriceStrategy(address(newPriceStrategy));

        assertEq(DUSD_USM.priceStrategy(), address(newPriceStrategy), "Unexpected price strategy");
    }

    function testRevertUpdatePriceStrategyNotAuthorized() public {
        FixedPriceStrategy newPriceStrategy =
            new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(USDC_TOKEN), address(this));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        vm.prank(ALICE);
        DUSD_USM.updatePriceStrategy(address(newPriceStrategy));
    }

    function testRevertSwapFreezeAlreadyFrozen() public {
        vm.startPrank(address(DUSD_USM_SWAP_FREEZER));
        DUSD_USM.setSwapFreeze(true);
        vm.expectRevert("USM_ALREADY_FROZEN");
        DUSD_USM.setSwapFreeze(true);
        vm.stopPrank();
    }

    function testSwapUnfreeze() public {
        vm.startPrank(address(DUSD_USM_SWAP_FREEZER));
        DUSD_USM.setSwapFreeze(true);
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.SwapFreeze(address(DUSD_USM_SWAP_FREEZER), false);
        DUSD_USM.setSwapFreeze(false);
        vm.stopPrank();
    }

    function testRevertUnfreezeNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_SWAP_FREEZER_ROLE
            )
        );
        vm.prank(ALICE);
        DUSD_USM.setSwapFreeze(false);
    }

    function testRevertUnfreezeNotFrozen() public {
        vm.prank(address(DUSD_USM_SWAP_FREEZER));
        vm.expectRevert("USM_ALREADY_UNFROZEN");
        DUSD_USM.setSwapFreeze(false);
    }

    function testRevertBuyAndSellWhenSwapFrozen() public {
        vm.prank(address(DUSD_USM_SWAP_FREEZER));
        DUSD_USM.setSwapFreeze(true);
        vm.expectRevert("USM_FROZEN");
        DUSD_USM.buyAsset(0, ALICE);
        vm.expectRevert("USM_FROZEN");
        DUSD_USM.sellAsset(0, ALICE);
    }

    function testUpdateConfigurator() public {
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IAccessControl.RoleGranted(USM_CONFIGURATOR_ROLE, ALICE, address(this));
        DUSD_USM.grantRole(USM_CONFIGURATOR_ROLE, ALICE);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IAccessControl.RoleRevoked(USM_CONFIGURATOR_ROLE, address(this), address(this));
        DUSD_USM.revokeRole(USM_CONFIGURATOR_ROLE, address(this));
    }

    function testRevertUpdateConfiguratorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, DEFAULT_ADMIN_ROLE)
        );
        vm.prank(ALICE);
        DUSD_USM.grantRole(USM_CONFIGURATOR_ROLE, ALICE);
    }

    function testConfiguratorUpdateMethods() public {
        // Alice as configurator
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IAccessControl.RoleGranted(USM_CONFIGURATOR_ROLE, ALICE, address(this));
        DUSD_USM.grantRole(USM_CONFIGURATOR_ROLE, ALICE);

        vm.startPrank(address(ALICE));

        assertEq(DUSD_USM.getFeeStrategy(), address(DUSD_USM_FIXED_FEE_STRATEGY), "Unexpected fee strategy");
        FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(this));

        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.FeeStrategyUpdated(address(DUSD_USM_FIXED_FEE_STRATEGY), address(newFeeStrategy));
        DUSD_USM.updateFeeStrategy(address(newFeeStrategy));
        assertEq(DUSD_USM.getFeeStrategy(), address(newFeeStrategy), "Unexpected fee strategy");

        address newDusdTreasury = address(DUSD_USM);
        vm.expectEmit(true, true, true, true, address(newDusdTreasury));
        emit IUsm.StableTokenTreasuryUpdated(TREASURY, newDusdTreasury);
        DUSD_USM.updateStableTokenTreasury(newDusdTreasury);
        assertEq(DUSD_USM.getStableTokenTreasury(), newDusdTreasury);

        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.ExposureCapUpdated(DEFAULT_USM_USDC_EXPOSURE, 0);
        DUSD_USM.updateExposureCap(0);
        assertEq(DUSD_USM.getExposureCap(), 0, "Unexpected exposure capacity");

        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.ExposureCapUpdated(0, 1000);
        DUSD_USM.updateExposureCap(1000);
        assertEq(DUSD_USM.getExposureCap(), 1000, "Unexpected exposure capacity");

        vm.stopPrank();
    }

    function testRevertSetFeeRecipientToZeroWithNonZeroFeeStrategy() public {
        // Fee strategy is already set (non-zero) from setup
        assertEq(DUSD_USM.getFeeStrategy(), address(DUSD_USM_FIXED_FEE_STRATEGY), "Fee strategy should be set");
        assertEq(DUSD_USM.getFeeRecipient(), FEE_RECIPIENT, "Fee recipient should be set");

        // Should revert when trying to set fee recipient to 0 while fee strategy is non-zero
        vm.expectRevert("FEE_RECIPIENT_CANNOT_BE_ZERO_WITH_FEE_STRATEGY");
        DUSD_USM.updateFeeRecipient(address(0));
    }

    function testSetFeeRecipientToZeroWithZeroFeeStrategy() public {
        // First set fee strategy to 0
        DUSD_USM.updateFeeStrategy(address(0));
        assertEq(DUSD_USM.getFeeStrategy(), address(0), "Fee strategy should be zero");

        // Now setting fee recipient to 0 should succeed
        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IStableTokenFacilitator.StableTokenFeeRecipientUpdated(FEE_RECIPIENT, address(0));
        DUSD_USM.updateFeeRecipient(address(0));
        assertEq(DUSD_USM.getFeeRecipient(), address(0), "Fee recipient should be zero");
    }

    function testRevertSetFeeStrategyToNonZeroWithZeroFeeRecipient() public {
        // First set fee strategy to 0
        DUSD_USM.updateFeeStrategy(address(0));
        // Then set fee recipient to 0
        DUSD_USM.updateFeeRecipient(address(0));
        assertEq(DUSD_USM.getFeeRecipient(), address(0), "Fee recipient should be zero");
        assertEq(DUSD_USM.getFeeStrategy(), address(0), "Fee strategy should be zero");

        // Should revert when trying to set fee strategy to non-zero while fee recipient is 0
        FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(this));
        vm.expectRevert("FEE_STRATEGY_REQUIRES_FEE_RECIPIENT");
        DUSD_USM.updateFeeStrategy(address(newFeeStrategy));
    }

    function testSetFeeStrategyToNonZeroWithNonZeroFeeRecipient() public {
        // Fee recipient is already set (non-zero) from setup
        assertEq(DUSD_USM.getFeeRecipient(), FEE_RECIPIENT, "Fee recipient should be set");

        // Setting fee strategy to non-zero should succeed when fee recipient is non-zero
        FixedFeeStrategy newFeeStrategy = new FixedFeeStrategy(DEFAULT_USM_BUY_FEE, DEFAULT_USM_SELL_FEE, address(this));
        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.FeeStrategyUpdated(address(DUSD_USM_FIXED_FEE_STRATEGY), address(newFeeStrategy));
        DUSD_USM.updateFeeStrategy(address(newFeeStrategy));
        assertEq(DUSD_USM.getFeeStrategy(), address(newFeeStrategy), "Fee strategy should be updated");
    }

    function testRevertConfiguratorUpdateMethodsNotAuthorized() public {
        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, DEFAULT_ADMIN_ROLE)
        );
        DUSD_USM.grantRole(USM_LIQUIDATOR_ROLE, ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, DEFAULT_ADMIN_ROLE)
        );
        DUSD_USM.grantRole(USM_SWAP_FREEZER_ROLE, ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        DUSD_USM.updateExposureCap(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        DUSD_USM.updateStableTokenTreasury(ALICE);
        vm.stopPrank();
    }

    function testRevertInitializeTreasuryZeroAddress() public {
        DUSDUsm usm =
            DUSDUsm(UnsafeUpgrades.deployUUPSProxy(address(new DUSDUsm(address(DUSD_TOKEN), address(USDC_TOKEN))), ""));
        vm.expectRevert(bytes("ZERO_ADDRESS_NOT_VALID"));
        usm.initialize(
            address(this),
            address(0),
            DEFAULT_USM_USDC_EXPOSURE,
            address(DUSD_USM_FIXED_PRICE_STRATEGY),
            AccessMode.PERMISSIONLESS
        );
    }

    function testUpdateDusdTreasuryRevertIfZero() public {
        vm.expectRevert(bytes("ZERO_ADDRESS_NOT_VALID"));
        DUSD_USM.updateStableTokenTreasury(address(0));
    }

    function testUpdateDusdTreasury() public {
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.StableTokenTreasuryUpdated(TREASURY, ALICE);
        DUSD_USM.updateStableTokenTreasury(ALICE);

        assertEq(DUSD_USM.getStableTokenTreasury(), ALICE);
    }

    function testUnauthorizedUpdateDusdTreasuryRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        vm.prank(ALICE);
        DUSD_USM.updateStableTokenTreasury(ALICE);
    }

    function testRescueTokens() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        vm.prank(FAUCET);
        WETH.mint(address(DUSD_USM), 100e18);
        assertEq(WETH.balanceOf(address(DUSD_USM)), 100e18, "Unexpected GSM WETH before balance");
        assertEq(WETH.balanceOf(ALICE), 0, "Unexpected target WETH before balance");
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.TokensRescued(address(WETH), ALICE, 100e18);
        DUSD_USM.rescueTokens(address(WETH), ALICE, 100e18);
        assertEq(WETH.balanceOf(address(DUSD_USM)), 0, "Unexpected GSM WETH after balance");
        assertEq(WETH.balanceOf(ALICE), 100e18, "Unexpected target WETH after balance");
    }

    function testRevertRescueTokensZeroAmount() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));
        vm.expectRevert("INVALID_AMOUNT");
        DUSD_USM.rescueTokens(address(WETH), ALICE, 0);
    }

    function testRescueDusdTokens() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        dusdFaucet(address(DUSD_USM), 100e18);
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), 100e18, "Unexpected GSM DUSD before balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), 0, "Unexpected target DUSD before balance");
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.TokensRescued(address(DUSD_TOKEN), ALICE, 100e18);
        DUSD_USM.rescueTokens(address(DUSD_TOKEN), ALICE, 100e18);
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), 0, "Unexpected GSM DUSD after balance");
        assertEq(DUSD_TOKEN.balanceOf(ALICE), 100e18, "Unexpected target DUSD after balance");
    }

    function testRescueDusdTokensWithAccruedFees() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        uint256 fee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        assertGt(fee, 0, "Fee not greater than zero");

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, fee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), fee, "Unexpected GSM DUSD balance");

        dusdFaucet(address(DUSD_USM), 1);
        assertEq(DUSD_TOKEN.balanceOf(BOB), 0, "Unexpected target DUSD balance before");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), fee + 1, "Unexpected GSM DUSD balance before");

        vm.expectRevert("INSUFFICIENT_STABLE_TOKEN_TO_RESCUE");
        DUSD_USM.rescueTokens(address(DUSD_TOKEN), BOB, fee);

        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.TokensRescued(address(DUSD_TOKEN), BOB, 1);
        DUSD_USM.rescueTokens(address(DUSD_TOKEN), BOB, 1);

        assertEq(DUSD_TOKEN.balanceOf(BOB), 1, "Unexpected target DUSD balance after");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), fee, "Unexpected GSM DUSD balance after");
    }

    function testRevertRescueDusdTokens() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        vm.expectRevert("INSUFFICIENT_STABLE_TOKEN_TO_RESCUE");
        DUSD_USM.rescueTokens(address(DUSD_TOKEN), ALICE, 1);
    }

    function testRescueUnderlyingTokens() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        vm.prank(FAUCET);
        USDC_TOKEN.mint(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);

        assertEq(USDC_TOKEN.balanceOf(ALICE), 0, "Unexpected USDC balance before");
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.TokensRescued(address(USDC_TOKEN), ALICE, DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.rescueTokens(address(USDC_TOKEN), ALICE, DEFAULT_USM_USDC_AMOUNT);
        assertEq(USDC_TOKEN.balanceOf(ALICE), DEFAULT_USM_USDC_AMOUNT, "Unexpected USDC balance after");
    }

    function testRescueUnderlyingTokensWithAccruedFees() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        uint256 currentGSMBalance = DEFAULT_USM_USDC_AMOUNT;
        assertEq(USDC_TOKEN.balanceOf(address(DUSD_USM)), currentGSMBalance, "Unexpected GSM USDC balance before");

        vm.prank(FAUCET);
        USDC_TOKEN.mint(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        assertEq(
            USDC_TOKEN.balanceOf(address(DUSD_USM)),
            currentGSMBalance + DEFAULT_USM_USDC_AMOUNT,
            "Unexpected GSM USDC balance before, post-mint"
        );
        assertEq(USDC_TOKEN.balanceOf(ALICE), 0, "Unexpected target USDC balance before");

        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.TokensRescued(address(USDC_TOKEN), ALICE, DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.rescueTokens(address(USDC_TOKEN), ALICE, DEFAULT_USM_USDC_AMOUNT);
        assertEq(USDC_TOKEN.balanceOf(address(DUSD_USM)), currentGSMBalance, "Unexpected GSM USDC balance after");
        assertEq(USDC_TOKEN.balanceOf(ALICE), DEFAULT_USM_USDC_AMOUNT, "Unexpected target USDC balance after");
    }

    function testRevertRescueUnderlyingTokens() public {
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, address(this));

        vm.expectRevert("INSUFFICIENT_EXOGENOUS_ASSET_TO_RESCUE");
        DUSD_USM.rescueTokens(address(USDC_TOKEN), ALICE, 1);
    }

    function testSeize() public {
        assertEq(DUSD_USM.getIsSeized(), false, "Unexpected seize status before");

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        assertEq(USDC_TOKEN.balanceOf(TREASURY), 0, "Unexpected USDC before token balance");
        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.Seized(
            address(DUSD_USM_LAST_RESORT_LIQUIDATOR), BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT
        );
        uint256 seizedAmount = DUSD_USM.seize();

        assertEq(DUSD_USM.getIsSeized(), true, "Unexpected seize status after");
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seized amount");
        assertEq(USDC_TOKEN.balanceOf(TREASURY), DEFAULT_USM_USDC_AMOUNT, "Unexpected USDC after token balance");
        assertEq(DUSD_USM.getAvailableLiquidity(), 0, "Unexpected available liquidity");
        assertEq(DUSD_USM.getAvailableUnderlyingExposure(), 0, "Unexpected underlying exposure available");
        assertEq(DUSD_USM.getExposureCap(), 0, "Unexpected exposure capacity");
    }

    function testRevertSeizeWithoutAuthorization() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), USM_LIQUIDATOR_ROLE
            )
        );
        DUSD_USM.seize();
    }

    function testRevertMethodsAfterSeizure() public {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        uint256 seizedAmount = DUSD_USM.seize();
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seized amount");

        vm.expectRevert("USM_SEIZED");
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.expectRevert("USM_SEIZED");
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.expectRevert("USM_SEIZED");
        DUSD_USM.seize();
    }

    function testBurnAfterSeize() public {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        uint256 seizedAmount = DUSD_USM.seize();
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seized amount");

        dusdFaucet(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), DEFAULT_USM_DUSD_AMOUNT);
        vm.startPrank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT);
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.BurnAfterSeize(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), DEFAULT_USM_DUSD_AMOUNT, 0);
        uint256 burnedAmount = DUSD_USM.burnAfterSeize(DEFAULT_USM_DUSD_AMOUNT);
        vm.stopPrank();
        assertEq(burnedAmount, DEFAULT_USM_DUSD_AMOUNT, "Unexpected burned amount of DUSD");

        vm.expectEmit(true, false, false, true, address(DUSD_TOKEN));
        emit IDUSD.SetMinterStatus(address(DUSD_USM), false);
        DUSD_TOKEN.setMinterStatus(address(DUSD_USM), false);
    }

    function testBurnAfterSeizeGreaterAmount() public {
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        uint256 seizedAmount = DUSD_USM.seize();
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seized amount");

        dusdFaucet(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), DEFAULT_USM_DUSD_AMOUNT + 1);
        vm.startPrank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + 1);
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.BurnAfterSeize(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), DEFAULT_USM_DUSD_AMOUNT, 0);
        uint256 burnedAmount = DUSD_USM.burnAfterSeize(DEFAULT_USM_DUSD_AMOUNT + 1);
        vm.stopPrank();
        assertEq(burnedAmount, DEFAULT_USM_DUSD_AMOUNT, "Unexpected burned amount of DUSD");
    }

    function testRevertBurnAfterSeizeNotSeized() public {
        vm.expectRevert("USM_NOT_SEIZED");
        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        DUSD_USM.burnAfterSeize(1);
    }

    function testRevertBurnAfterSeizeUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), USM_LIQUIDATOR_ROLE
            )
        );
        DUSD_USM.burnAfterSeize(1);
    }

    function testDistributeFeesToTreasury() public {
        uint256 fee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);

        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.SellAsset(ALICE, ALICE, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT, fee);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), fee, "Unexpected GSM DUSD balance");
        assertEq(DUSD_USM.getAccruedFees(), fee, "Unexpected GSM accrued fees");

        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IStableTokenFacilitator.FeesDistributedToFeeRecipient(
            FEE_RECIPIENT, address(DUSD_TOKEN), DUSD_TOKEN.balanceOf(address(DUSD_USM))
        );
        DUSD_USM.distributeFeesToFeeRecipient();
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), 0, "Unexpected GSM DUSD balance post-distribution");
        assertEq(DUSD_TOKEN.balanceOf(FEE_RECIPIENT), fee, "Unexpected DUSD balance in fee recipient");
        assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");
    }

    function testDistributeYieldToTreasuryDoNothing() public {
        uint256 gsmBalanceBefore = DUSD_TOKEN.balanceOf(address(DUSD_USM));
        uint256 treasuryBalanceBefore = DUSD_TOKEN.balanceOf(address(TREASURY));
        assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");

        vm.record();
        DUSD_USM.distributeFeesToFeeRecipient();
        (, bytes32[] memory writes) = vm.accesses(address(DUSD_USM));
        assertEq(writes.length, 0, "Unexpected update of accrued fees");

        assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");
        assertEq(
            DUSD_TOKEN.balanceOf(address(DUSD_USM)), gsmBalanceBefore, "Unexpected GSM DUSD balance post-distribution"
        );
        assertEq(DUSD_TOKEN.balanceOf(TREASURY), treasuryBalanceBefore, "Unexpected DUSD balance in treasury");
    }

    function testGetAccruedFees() public {
        assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");

        uint256 sellFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_SELL_FEE);
        uint256 buyFee = DEFAULT_USM_DUSD_AMOUNT.percentMul(DEFAULT_USM_BUY_FEE);

        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);

        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), sellFee, "Unexpected GSM DUSD balance");
        assertEq(DUSD_USM.getAccruedFees(), sellFee, "Unexpected GSM accrued fees");

        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT + buyFee);
        vm.expectEmit(true, true, true, true, address(DUSD_USM));
        emit IUsm.BuyAsset(BOB, BOB, DEFAULT_USM_USDC_AMOUNT, DEFAULT_USM_DUSD_AMOUNT + buyFee, buyFee);
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
        vm.stopPrank();

        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), sellFee + buyFee, "Unexpected GSM DUSD balance");
        assertEq(DUSD_USM.getAccruedFees(), sellFee + buyFee, "Unexpected GSM accrued fees");
    }

    function testGetAccruedFeesWithZeroFee() public {
        vm.expectEmit(true, true, false, true, address(DUSD_USM));
        emit IUsm.FeeStrategyUpdated(address(DUSD_USM_FIXED_FEE_STRATEGY), address(0));
        DUSD_USM.updateFeeStrategy(address(0));

        assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");

        for (uint256 i = 0; i < 10; i++) {
            _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, DEFAULT_USM_USDC_AMOUNT);
            assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");

            dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT);
            vm.startPrank(BOB);
            DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT);
            DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT, BOB);
            vm.stopPrank();

            assertEq(DUSD_USM.getAccruedFees(), 0, "Unexpected GSM accrued fees");
        }
    }

    function testCanSwap() public {
        assertEq(DUSD_USM.canSwap(), true, "Unexpected initial swap state");

        // Freeze the GSM
        vm.startPrank(address(DUSD_USM_SWAP_FREEZER));
        DUSD_USM.setSwapFreeze(true);
        assertEq(DUSD_USM.canSwap(), false, "Unexpected swap state post-freeze");

        // Unfreeze the GSM
        DUSD_USM.setSwapFreeze(false);
        assertEq(DUSD_USM.canSwap(), true, "Unexpected swap state post-unfreeze");
        vm.stopPrank();

        // Seize the GSM
        vm.prank(address(DUSD_USM_LAST_RESORT_LIQUIDATOR));
        DUSD_USM.seize();
        assertEq(DUSD_USM.canSwap(), false, "Unexpected swap state post-seize");
    }

    function testUpdateExposureCapBelowCurrentExposure() public {
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure cap");

        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, 2 * DEFAULT_USM_USDC_AMOUNT);

        // Alice as configurator
        DUSD_USM.grantRole(USM_CONFIGURATOR_ROLE, ALICE);
        vm.startPrank(address(ALICE));

        DUSD_USM.updateFeeStrategy(address(0));

        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);

        assertEq(
            DUSD_USM.getAvailableUnderlyingExposure(),
            DEFAULT_USM_USDC_EXPOSURE - DEFAULT_USM_USDC_AMOUNT,
            "Unexpected available underlying exposure"
        );
        assertEq(DUSD_USM.getExposureCap(), DEFAULT_USM_USDC_EXPOSURE, "Unexpected exposure cap");

        // Update exposure cap to smaller value than current exposure
        uint256 currentExposure = DUSD_USM.getAvailableLiquidity();
        uint256 newExposureCap = currentExposure - 1;
        DUSD_USM.updateExposureCap(uint128(newExposureCap));
        assertEq(DUSD_USM.getExposureCap(), newExposureCap, "Unexpected exposure cap");
        assertEq(DUSD_USM.getAvailableLiquidity(), currentExposure, "Unexpected current exposure");

        // Reducing exposure to 0
        DUSD_USM.updateExposureCap(0);

        // Sell cannot be executed
        vm.expectRevert("EXOGENOUS_ASSET_EXPOSURE_TOO_HIGH");
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);

        // Buy some asset to reduce current exposure
        vm.stopPrank();
        dusdFaucet(BOB, DEFAULT_USM_DUSD_AMOUNT / 2);
        vm.startPrank(BOB);
        DUSD_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_DUSD_AMOUNT / 2);
        DUSD_USM.buyAsset(DEFAULT_USM_USDC_AMOUNT / 2, BOB);

        assertEq(DUSD_USM.getExposureCap(), 0, "Unexpected exposure capacity");
    }
}
