// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DeployAltoEthereumMainnetTestBase} from "@alto-test/deployments/DeployAltoEthereumMainnet.t.sol";
import {
    DeployAltoEthereumMainnet,
    DeploymentPhase
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {UsmType} from "@alto/usm/interfaces/IUsmCommon.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {IUsmRegistry, UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

abstract contract DeployUsmUpgradesDeprecatedTestBase is DeployAltoEthereumMainnetTestBase {
    // ─────────────────────────────────────────────────────────────────────────
    // USM_REGISTRY_UPDATE
    // ─────────────────────────────────────────────────────────────────────────
    function _assertDeployUsmRegistryUpdate() internal {
        require(input.contracts.usmRegistry != address(0), "usmRegistry required");
        require(input.contracts.timelock != address(0), "timelock required");

        address oldRegistry = input.contracts.usmRegistry;
        address timelock = input.contracts.timelock;
        address[] memory oldUsms = IUsmRegistry(oldRegistry).getUsmList();
        require(oldUsms.length > 0, "old registry should have USMs");

        params.phase = DeploymentPhase.USM_REGISTRY_UPDATE;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address newRegistry = input.contracts.usmRegistry;

        _verifyDeployed(newRegistry, "usmRegistry");
        _verifyOwner(newRegistry, "usmRegistry");

        assertTrue(newRegistry != oldRegistry, "new registry should be deployed");
        assertEq(UsmRegistry(newRegistry).getUsmListLength(), oldUsms.length, "USM count mismatch");

        for (uint256 i; i < oldUsms.length; ++i) {
            assertTrue(IUsmRegistry(newRegistry).isUsm(oldUsms[i]), "USM not migrated");
        }

        assertEq(Ownable(oldRegistry).owner(), timelock, "old registry owner should be unchanged");
        assertEq(IUsmRegistry(oldRegistry).getUsmListLength(), oldUsms.length, "old registry should be unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UPGRADE_STANDARD_USM
    // ─────────────────────────────────────────────────────────────────────────

    struct UsmUpgradeState {
        AccessMode accessMode;
        uint256 accruedFees;
        uint256 availableLiquidity;
        uint256 availableUnderlyingExposure;
        uint128 exposureCap;
        address feeRecipient;
        address feeStrategy;
        address priceStrategy;
    }

    function _snapshotUsmUpgradeState(address usm) internal view returns (UsmUpgradeState memory state) {
        state.accessMode = IUsm(usm).getAccessMode();
        state.accruedFees = IUsm(usm).getAccruedFees();
        state.availableLiquidity = IUsm(usm).getAvailableLiquidity();
        state.availableUnderlyingExposure = IUsm(usm).getAvailableUnderlyingExposure();
        state.exposureCap = IUsm(usm).getExposureCap();
        state.feeRecipient = IUsm(usm).getFeeRecipient();
        state.feeStrategy = IUsm(usm).getFeeStrategy();
        state.priceStrategy = IUsm(usm).priceStrategy();
    }

    function _assertUsmUpgradeStateUnchanged(UsmUpgradeState memory before, UsmUpgradeState memory stateAfter)
        internal
        pure
    {
        assertEq(uint8(stateAfter.accessMode), uint8(before.accessMode), "access mode mismatch");
        assertEq(stateAfter.accruedFees, before.accruedFees, "accrued fees mismatch");
        assertEq(stateAfter.availableLiquidity, before.availableLiquidity, "available liquidity mismatch");
        assertEq(
            stateAfter.availableUnderlyingExposure,
            before.availableUnderlyingExposure,
            "available underlying exposure mismatch"
        );
        assertEq(stateAfter.exposureCap, before.exposureCap, "exposure cap mismatch");
        assertEq(stateAfter.feeRecipient, before.feeRecipient, "fee recipient mismatch");
        assertEq(stateAfter.feeStrategy, before.feeStrategy, "fee strategy mismatch");
        assertEq(stateAfter.priceStrategy, before.priceStrategy, "price strategy mismatch");
    }

    function _assertUpgradeStandardUsm() internal {
        require(input.contracts.timelock != address(0), "timelock required");

        address[] memory usmsToUpgrade = _standardUsmsToUpgrade();
        require(usmsToUpgrade.length == 3, "expected 3 USMs to upgrade");

        address permissionlessUsm = input.contracts.permissionlessUsm.dusdUsm;
        address permissionlessUsmImplementationBefore;
        if (permissionlessUsm != address(0)) {
            permissionlessUsmImplementationBefore = UnsafeUpgrades.getImplementationAddress(permissionlessUsm);
        }

        address[] memory oldImplementations = new address[](usmsToUpgrade.length);
        for (uint256 i; i < usmsToUpgrade.length; ++i) {
            oldImplementations[i] = UnsafeUpgrades.getImplementationAddress(usmsToUpgrade[i]);
        }

        params.phase = DeploymentPhase.UPGRADE_STANDARD_USM;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        assertTrue(
            vm.exists("contracts/deployments/ethereum-mainnet/output/safe-tx-standard-usm-upgrade-schedule.json"),
            "schedule json should be written"
        );
        assertTrue(
            vm.exists("contracts/deployments/ethereum-mainnet/output/safe-tx-standard-usm-upgrade-execute.json"),
            "execute json should be written"
        );

        for (uint256 i; i < usmsToUpgrade.length; ++i) {
            address usmProxy = usmsToUpgrade[i];
            address newImplementation = _getUsmImplementationFromInput(usmProxy);
            address stableToken = IUsm(usmProxy).STABLE_TOKEN();
            address underlyingAsset = IUsm(usmProxy).UNDERLYING_ASSET();

            _verifyDeployed(newImplementation, "DUSDUsm implementation");
            assertTrue(newImplementation != oldImplementations[i], "implementation should be redeployed");
            assertEq(DUSDUsm(newImplementation).STABLE_TOKEN(), stableToken, "stable token mismatch");
            assertEq(DUSDUsm(newImplementation).UNDERLYING_ASSET(), underlyingAsset, "underlying asset mismatch");
            assertEq(
                UnsafeUpgrades.getImplementationAddress(usmProxy),
                oldImplementations[i],
                "proxy implementation unchanged until timelock executes upgrade"
            );

            UsmUpgradeState memory stateBefore = _snapshotUsmUpgradeState(usmProxy);

            vm.prank(input.contracts.timelock);
            UUPSUpgradeable(usmProxy).upgradeToAndCall(newImplementation, bytes(""));

            assertEq(UnsafeUpgrades.getImplementationAddress(usmProxy), newImplementation, "proxy not upgraded");
            assertEq(uint8(IUsm(usmProxy).USM_TYPE()), uint8(UsmType.STANDARD), "USM_TYPE mismatch");
            _assertUsmUpgradeStateUnchanged(stateBefore, _snapshotUsmUpgradeState(usmProxy));
        }

        if (permissionlessUsm != address(0)) {
            assertEq(
                UnsafeUpgrades.getImplementationAddress(permissionlessUsm),
                permissionlessUsmImplementationBefore,
                "permissionlessUsm implementation should be unchanged"
            );
        }
    }

    function _standardUsmsToUpgrade() internal view returns (address[] memory usms) {
        usms = new address[](3);
        usms[0] = input.contracts.permissionedUsm.dusdUsm;
        usms[1] = input.contracts.permissionlessFrxusdUsm.dusdUsm;
        usms[2] = input.contracts.permissionedFrxusdUsm.dusdUsm;
    }

    function _getUsmImplementationFromInput(address usmProxy) internal view returns (address) {
        if (usmProxy == input.contracts.permissionedUsm.dusdUsm) {
            return input.contracts.permissionedUsm.dusdUsmImplementation;
        }
        if (usmProxy == input.contracts.permissionedFrxusdUsm.dusdUsm) {
            return input.contracts.permissionedFrxusdUsm.dusdUsmImplementation;
        }
        if (usmProxy == input.contracts.permissionlessFrxusdUsm.dusdUsm) {
            return input.contracts.permissionlessFrxusdUsm.dusdUsmImplementation;
        }
        revert("unknown USM proxy");
    }
}

contract DeployUsmRegistryUpdatePhaseTest is DeployUsmUpgradesDeprecatedTestBase {
    function test_deployUsmRegistryUpdate() public {
        _assertDeployUsmRegistryUpdate();
    }
}

contract DeployUpgradeStandardUsmPhaseTest is DeployUsmUpgradesDeprecatedTestBase {
    function test_upgradeStandardUsm() public {
        _assertUpgradeStandardUsm();
    }
}
