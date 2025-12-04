// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestDusdBase} from "./TestDusdBase.t.sol";
import {DUSDUsmUpgraded} from "./contracts/DUSDUsmUpgraded.sol";
import {DUSDUsmUpgradedOriginalUsm} from "./contracts/DUSDUsmUpgradedOriginalUsm.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TestUsmUpgraded is TestDusdBase {
    struct UsmData {
        address stableToken;
        address underlyingAsset;
        address priceStrategy;
        address stableTokenTreasury;
        address feeStrategy;
        bool isFrozen;
        bool isSeized;
        uint128 exposureCap;
        uint128 currentExposure;
        uint128 accruedFees;
        address admin;
        uint256 usmRevision;
    }

    function _getAllUsmData() internal view returns (UsmData memory) {
        return UsmData({
            stableToken: DUSD_USM.STABLE_TOKEN(),
            underlyingAsset: DUSD_USM.UNDERLYING_ASSET(),
            priceStrategy: DUSD_USM.priceStrategy(),
            stableTokenTreasury: DUSD_USM.getStableTokenTreasury(),
            feeStrategy: DUSD_USM.getFeeStrategy(),
            isFrozen: DUSD_USM.getIsFrozen(),
            isSeized: DUSD_USM.getIsSeized(),
            exposureCap: DUSD_USM.getExposureCap(),
            currentExposure: uint128(DUSD_USM.getAvailableLiquidity()),
            accruedFees: uint128(DUSD_USM.getAccruedFees()),
            admin: address(this), // Admin is set to address(this) in TestDusdBase setup
            usmRevision: DUSD_USM.USM_REVISION()
        });
    }

    function upgradeProxyExternal(
        address proxy,
        string memory contractName,
        bytes memory data,
        bytes memory constructorData,
        address caller
    ) external {
        Options memory opts;
        opts.constructorData = constructorData;
        vm.startPrank(caller);
        Upgrades.upgradeProxy(proxy, contractName, data, opts);
        vm.stopPrank();
    }

    function upgradeProxyExternalUnsafe(address proxy, address newImpl, bytes memory data) external {
        UnsafeUpgrades.upgradeProxy(proxy, newImpl, data);
    }

    function test_upgradeWhenUsmWasUpgraded() public {
        // Setup some state before upgrade
        dusdFaucet(ALICE, 1000e18);
        vm.startPrank(ALICE);
        USDC_TOKEN.mint(ALICE, 1000e6);
        USDC_TOKEN.approve(address(DUSD_USM), 1000e6);
        DUSD_USM.sellAsset(100e6, ALICE);
        vm.stopPrank();

        UsmData memory usmDataBefore = _getAllUsmData();

        // Sanity check that the USM is not empty
        assertNotEq(usmDataBefore.currentExposure, 0);
        assertNotEq(usmDataBefore.exposureCap, 0);
        assertEq(usmDataBefore.usmRevision, 1);

        vm.startPrank(address(this));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            Options memory opts;
            opts.constructorData = abi.encode(address(DUSD_TOKEN), address(USDC_TOKEN));
            Upgrades.upgradeProxy(
                address(DUSD_USM),
                "DUSDUsmUpgraded.sol",
                abi.encodeCall(DUSDUsmUpgraded.initializeV2, (1, 2, address(0x1))),
                opts
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(DUSD_USM),
                address(new DUSDUsmUpgraded(address(DUSD_TOKEN), address(USDC_TOKEN))),
                abi.encodeCall(DUSDUsmUpgraded.initializeV2, (1, 2, address(0x1)))
            );
        }
        vm.stopPrank();

        // Verify the upgrade was successful by checking the new properties exist
        DUSDUsmUpgraded upgradedUsm = DUSDUsmUpgraded(address(DUSD_USM));

        // Verify the values were initialized
        assertEq(upgradedUsm.addedProperty1(), 1);
        assertEq(upgradedUsm.addedProperty2(), 2);
        assertEq(upgradedUsm.addedProperty3(), address(0x1));

        // Test that the new functions are available
        upgradedUsm.setAddedProperty1(100);
        upgradedUsm.setAddedProperty2(200);
        upgradedUsm.setAddedProperty3(address(0x123));

        // Verify the values were set
        assertEq(upgradedUsm.addedProperty1(), 100);
        assertEq(upgradedUsm.addedProperty2(), 200);
        assertEq(upgradedUsm.addedProperty3(), address(0x123));

        // Verify existing functionality still works
        UsmData memory usmDataAfter = _getAllUsmData();

        // Verify that the USM data is equal to the original USM
        assertEq(usmDataBefore.stableToken, usmDataAfter.stableToken);
        assertEq(usmDataBefore.underlyingAsset, usmDataAfter.underlyingAsset);
        assertEq(usmDataBefore.priceStrategy, usmDataAfter.priceStrategy);
        assertEq(usmDataBefore.stableTokenTreasury, usmDataAfter.stableTokenTreasury);
        assertEq(usmDataBefore.feeStrategy, usmDataAfter.feeStrategy);
        assertEq(usmDataBefore.isFrozen, usmDataAfter.isFrozen);
        assertEq(usmDataBefore.isSeized, usmDataAfter.isSeized);
        assertEq(usmDataBefore.exposureCap, usmDataAfter.exposureCap);
        assertEq(usmDataBefore.currentExposure, usmDataAfter.currentExposure);
        assertEq(usmDataBefore.accruedFees, usmDataAfter.accruedFees);
        assertEq(usmDataBefore.admin, usmDataAfter.admin);
        assertEq(usmDataAfter.usmRevision, 2);

        // Sanity check that the USM is still working
        vm.startPrank(ALICE);
        USDC_TOKEN.mint(ALICE, 100e6);
        USDC_TOKEN.approve(address(DUSD_USM), 100e6);
        DUSD_USM.sellAsset(50e6, ALICE);
        vm.stopPrank();
    }

    function test_upgradeWhenDusdOnlyWasUpgraded() public {
        // Setup some state before upgrade
        dusdFaucet(ALICE, 1000e18);
        vm.startPrank(ALICE);
        USDC_TOKEN.mint(ALICE, 1000e6);
        USDC_TOKEN.approve(address(DUSD_USM), 1000e6);
        DUSD_USM.sellAsset(100e6, ALICE);
        vm.stopPrank();

        UsmData memory usmDataBefore = _getAllUsmData();

        // Sanity check that the USM is not empty
        assertNotEq(usmDataBefore.currentExposure, 0);
        assertNotEq(usmDataBefore.exposureCap, 0);
        assertEq(usmDataBefore.usmRevision, 1);

        vm.startPrank(address(this));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            Options memory opts;
            opts.constructorData = abi.encode(address(DUSD_TOKEN), address(USDC_TOKEN));
            Upgrades.upgradeProxy(
                address(DUSD_USM),
                "DUSDUsmUpgradedOriginalUsm.sol",
                abi.encodeCall(DUSDUsmUpgradedOriginalUsm.initializeV2, ()),
                opts
            );
        } else {
            UnsafeUpgrades.upgradeProxy(
                address(DUSD_USM),
                address(new DUSDUsmUpgradedOriginalUsm(address(DUSD_TOKEN), address(USDC_TOKEN))),
                abi.encodeCall(DUSDUsmUpgradedOriginalUsm.initializeV2, ())
            );
        }
        vm.stopPrank();

        // Verify the upgrade was successful by checking the new properties exist
        DUSDUsmUpgradedOriginalUsm upgradedUsm = DUSDUsmUpgradedOriginalUsm(address(DUSD_USM));

        // Test that the new functions are available
        upgradedUsm.setAddedProperty1(100);
        upgradedUsm.setAddedProperty2(address(0x123));
        upgradedUsm.setAddedProperty3(200);

        // Verify the values were set
        assertEq(upgradedUsm.addedProperty1(), 100);
        assertEq(upgradedUsm.addedProperty2(), address(0x123));
        assertEq(upgradedUsm.addedProperty3(), 200);

        // Verify existing functionality still works
        UsmData memory usmDataAfter = _getAllUsmData();

        // Verify that the USM data is equal to the original USM
        assertEq(usmDataBefore.stableToken, usmDataAfter.stableToken);
        assertEq(usmDataBefore.underlyingAsset, usmDataAfter.underlyingAsset);
        assertEq(usmDataBefore.priceStrategy, usmDataAfter.priceStrategy);
        assertEq(usmDataBefore.stableTokenTreasury, usmDataAfter.stableTokenTreasury);
        assertEq(usmDataBefore.feeStrategy, usmDataAfter.feeStrategy);
        assertEq(usmDataBefore.isFrozen, usmDataAfter.isFrozen);
        assertEq(usmDataBefore.isSeized, usmDataAfter.isSeized);
        assertEq(usmDataBefore.exposureCap, usmDataAfter.exposureCap);
        assertEq(usmDataBefore.currentExposure, usmDataAfter.currentExposure);
        assertEq(usmDataBefore.accruedFees, usmDataAfter.accruedFees);
        assertEq(usmDataBefore.admin, usmDataAfter.admin);
        assertEq(usmDataAfter.usmRevision, 2);

        // Sanity check that the USM is still working
        vm.startPrank(ALICE);
        USDC_TOKEN.mint(ALICE, 100e6);
        USDC_TOKEN.approve(address(DUSD_USM), 100e6);
        DUSD_USM.sellAsset(50e6, ALICE);
        vm.stopPrank();
    }

    function test_upgradeWhenNotAdmin() public {
        // Setup some state before upgrade
        dusdFaucet(ALICE, 1000e18);
        vm.startPrank(ALICE);
        USDC_TOKEN.mint(ALICE, 1000e6);
        USDC_TOKEN.approve(address(DUSD_USM), 1000e6);
        DUSD_USM.sellAsset(100e6, ALICE);
        vm.stopPrank();

        bool success = false;
        bytes memory returnData;

        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        // Use ALICE who doesn't have admin role
        address newImpl = address(new DUSDUsmUpgradedOriginalUsm(address(DUSD_TOKEN), address(USDC_TOKEN)));
        bytes memory data = abi.encodeCall(DUSDUsmUpgradedOriginalUsm.initializeV2, ());

        vm.startPrank(ALICE);
        if (shouldUseSafeProxy) {
            try this.upgradeProxyExternal(
                address(DUSD_USM),
                "DUSDUsmUpgradedOriginalUsm.sol",
                data,
                abi.encode(address(DUSD_TOKEN), address(USDC_TOKEN)),
                ALICE
            ) {
                // If we reach here, the call succeeded when it should have failed
                fail();
                success = true;
            } catch (bytes memory reason) {
                // Verify the revert reason matches what we expect
                bytes memory expectedError =
                    abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, bytes32(0));
                assertEq(reason, expectedError, "Unexpected revert reason");
                returnData = reason;
            }
        } else {
            // Call upgradeToAndCall directly on the proxy from ALICE's context
            try UUPSUpgradeable(payable(address(DUSD_USM))).upgradeToAndCall(newImpl, data) {
                // If we reach here, the call succeeded when it should have failed
                fail();
                success = true;
            } catch (bytes memory reason) {
                // Verify the revert reason matches what we expect
                bytes memory expectedError =
                    abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, bytes32(0));
                assertEq(reason, expectedError, "Unexpected revert reason");
                returnData = reason;
            }
        }
        vm.stopPrank();

        // Ensure the call failed as expected
        assertFalse(success, "Expected revert but upgrade succeeded");
    }
}

