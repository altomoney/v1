// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSDV2 is SDUSD {
    uint256 public v2Value;

    function initializeV2(uint256 newValue) external reinitializer(2) {
        v2Value = newValue;
    }
}

contract NonUUPSSDUSDImplementation {}

contract SDUSD_UpgradeToAndCall_Test is SDUSDCommon {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_RevertWhen_CalledDirectlyOnImplementation() public {
        SDUSDV2 implementation = new SDUSDV2();
        SDUSDV2 newImplementation = new SDUSDV2();

        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        UUPSUpgradeable(payable(address(implementation))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_ProxyCallerIsNotOwner() public {
        SDUSDV2 newImplementation = new SDUSDV2();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        UUPSUpgradeable(payable(address(vault))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_NonOwnerProvidesInvalidImplementationBeforeCompatibilityCheck() public {
        NonUUPSSDUSDImplementation newImplementation = new NonUUPSSDUSDImplementation();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        UUPSUpgradeable(payable(address(vault))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_NewImplementationIsNotUupsCompatible() public {
        NonUUPSSDUSDImplementation newImplementation = new NonUUPSSDUSDImplementation();

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(newImplementation))
        );
        UUPSUpgradeable(payable(address(vault))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_OwnerUpdatesImplementationAndPreservesStorage() public {
        SDUSDV2 newImplementation = new SDUSDV2();

        _notifyRewards(REWARD_AMOUNT);
        uint256 periodStartBefore = vault.periodStart();
        uint256 periodFinishBefore = vault.rewardPeriodFinish();
        vm.warp(periodStartBefore + REWARD_DURATION / 2);

        uint256 nextRewardDuration = 8 days;
        vm.prank(ADMIN);
        vault.setRewardDuration(nextRewardDuration);
        _pauseVault();
        vm.prank(ADMIN);
        vault.transferOwnership(USER);

        address assetBefore = vault.asset();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 accountedAssetsBefore = vault.accountedAssets();
        uint256 lockedRewardsBefore = vault.lockedRewardsRemaining();
        uint256 exchangeRateBefore = vault.convertToAssets(1 ether);
        uint256 seedBalanceBefore = vault.balanceOf(SEED_LOCK);
        uint256 userBalanceBefore = vault.balanceOf(USER);

        vm.expectEmit(true, false, false, true, address(vault));
        emit IERC1967.Upgraded(address(newImplementation));
        vm.prank(ADMIN);
        UUPSUpgradeable(payable(address(vault))).upgradeToAndCall(address(newImplementation), "");

        address storedImplementation = address(uint160(uint256(vm.load(address(vault), IMPLEMENTATION_SLOT))));
        assertEq(storedImplementation, address(newImplementation));
        assertEq(vault.owner(), ADMIN);
        assertEq(vault.pendingOwner(), USER);
        assertTrue(vault.pausers(PAUSER, PAUSE_TYPE));
        assertTrue(vault.pausers(ADMIN, PAUSE_TYPE));
        assertTrue(vault.paused(PAUSE_TYPE));
        assertEq(vault.asset(), assetBefore);
        assertEq(vault.seedShares(), SEED_SHARES);
        assertEq(vault.rewarder(), address(collector));
        assertEq(vault.rewardDuration(), nextRewardDuration);
        assertEq(vault.depositCap(), INITIAL_DEPOSIT_CAP);
        assertEq(vault.depositCapUsage(), SEED_SHARES);
        assertEq(vault.principalOf(USER), SEED_SHARES);
        assertEq(vault.principalOf(SEED_LOCK), 0);
        assertEq(vault.maxDeposit(USER), 0);
        assertEq(vault.rewardsForPeriod(), REWARD_AMOUNT);
        assertEq(vault.periodStart(), periodStartBefore);
        assertEq(vault.rewardPeriodFinish(), periodFinishBefore);
        assertEq(vault.totalSupply(), totalSupplyBefore);
        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.accountedAssets(), accountedAssetsBefore);
        assertEq(vault.lockedRewardsRemaining(), lockedRewardsBefore);
        assertEq(vault.convertToAssets(1 ether), exchangeRateBefore);
        assertEq(vault.balanceOf(SEED_LOCK), seedBalanceBefore);
        assertEq(vault.balanceOf(USER), userBalanceBefore);

        vm.prank(ADMIN);
        vault.pause(PAUSE_TYPE, false);
        assertEq(vault.maxDeposit(USER), INITIAL_DEPOSIT_CAP - SEED_SHARES);

        // The active period continues using its original seven-day span even though the next period is configured
        // to use eight days.
        vm.warp(periodStartBefore + REWARD_DURATION * 3 / 4);
        assertEq(vault.lockedRewardsRemaining(), REWARD_AMOUNT / 4);
        assertEq(vault.totalAssets(), accountedAssetsBefore - REWARD_AMOUNT / 4);
        assertGt(vault.convertToAssets(1 ether), exchangeRateBefore);
    }

    function test_OwnerDelegatecallsNewImplementationWithProvidedCalldata() public {
        SDUSDV2 newImplementation = new SDUSDV2();
        uint256 expectedValue = 42;
        bytes memory data = abi.encodeCall(SDUSDV2.initializeV2, (expectedValue));

        vm.prank(ADMIN);
        UUPSUpgradeable(payable(address(vault))).upgradeToAndCall(address(newImplementation), data);

        assertEq(SDUSDV2(address(vault)).v2Value(), expectedValue);
    }
}
