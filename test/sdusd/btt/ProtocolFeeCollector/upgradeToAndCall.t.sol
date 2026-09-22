// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollectorV2 is ProtocolFeeCollector {
    uint256 public v2Value;

    function initializeV2(uint256 newValue) external reinitializer(2) {
        v2Value = newValue;
    }
}

contract NonUUPSProtocolFeeCollectorImplementation {}

contract ProtocolFeeCollector_UpgradeToAndCall_Test is ProtocolFeeCollectorCommon {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_RevertWhen_CalledDirectlyOnImplementation() public {
        ProtocolFeeCollectorV2 newImplementation = new ProtocolFeeCollectorV2();

        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        UUPSUpgradeable(payable(address(implementation))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_ProxyCallerIsNotOwner() public {
        ProtocolFeeCollectorV2 newImplementation = new ProtocolFeeCollectorV2();

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        UUPSUpgradeable(payable(address(collector))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_NewImplementationIsNotUupsCompatible() public {
        NonUUPSProtocolFeeCollectorImplementation newImplementation = new NonUUPSProtocolFeeCollectorImplementation();

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(newImplementation))
        );
        UUPSUpgradeable(payable(address(collector))).upgradeToAndCall(address(newImplementation), "");
    }

    function test_OwnerUpdatesImplementationAndPreservesStorage() public {
        ProtocolFeeCollectorV2 newImplementation = new ProtocolFeeCollectorV2();
        _setSdusdVault();
        _pause();
        vm.prank(ADMIN);
        collector.transferOwnership(USER);

        vm.prank(ADMIN);
        UUPSUpgradeable(payable(address(collector))).upgradeToAndCall(address(newImplementation), "");

        address storedImplementation = address(uint160(uint256(vm.load(address(collector), IMPLEMENTATION_SLOT))));
        assertEq(storedImplementation, address(newImplementation));
        assertEq(collector.owner(), ADMIN);
        assertEq(collector.pendingOwner(), USER);
        assertTrue(collector.isCollateralOperator(COLLATERAL_OPERATOR));
        assertTrue(collector.pausers(PAUSER, PAUSE_TYPE));
        assertTrue(collector.pausers(ADMIN, PAUSE_TYPE));
        assertTrue(collector.paused(PAUSE_TYPE));
        assertEq(collector.dusd(), address(dusd));
        assertEq(collector.sdusdVault(), address(sdusdVault));
        assertEq(collector.treasury(), TREASURY);
        assertEq(collector.manualSwapReceiver(), MANUAL_SWAP_RECEIVER);
        assertEq(collector.flashMinter(), address(flashMinter));
        assertEq(address(collector.marketRegistry()), address(marketRegistry));
        assertEq(address(collector.usmRegistry()), address(usmRegistry));
        assertEq(address(collector.vaultRegistry()), address(vaultRegistry));
        assertEq(collector.rewardsBps(), INITIAL_REWARDS_BPS);
        assertEq(collector.minimumRewardAmount(), INITIAL_MINIMUM_REWARD_AMOUNT);
    }

    function test_OwnerDelegatecallsNewImplementationWithProvidedCalldata() public {
        ProtocolFeeCollectorV2 newImplementation = new ProtocolFeeCollectorV2();
        uint256 expectedValue = 42;
        bytes memory data = abi.encodeCall(ProtocolFeeCollectorV2.initializeV2, (expectedValue));

        vm.prank(ADMIN);
        UUPSUpgradeable(payable(address(collector))).upgradeToAndCall(address(newImplementation), data);

        assertEq(ProtocolFeeCollectorV2(address(collector)).v2Value(), expectedValue);
    }
}
