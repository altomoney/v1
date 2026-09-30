// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";

interface ILegacyEmergencyControllerUpgradeTargets {
    function dusd() external view returns (address);
    function universalRewardsDistributor() external view returns (address);
}

/// @notice Deploys the new implementation and prepares the existing proxy's governance upgrade.
contract UpgradeEmergencyControllerScript is Script {
    address public constant CONTROLLER = 0x3c822f14a90955bf35278b42BA509FeEcAD3a305;
    address public constant LEGACY_IMPLEMENTATION = 0xFE329F88663b9B8833b180A139315C131A033167;
    address public constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address public constant OWNER_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    bytes32 public constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Deploys only the implementation. The Owner Safe executes the upgrade through the timelock.
    function run() public returns (address implementation) {
        preflight();

        vm.startBroadcast();
        implementation = address(new EmergencyController());
        vm.stopBroadcast();

        console.log("New EmergencyController implementation:", implementation);
    }

    /// @notice Checks the deployed legacy proxy and reads the current timelock delay.
    function preflight() public view returns (uint256 minDelay) {
        require(block.chainid == 1, "Ethereum mainnet required");
        require(CONTROLLER.code.length != 0, "Controller not deployed");
        require(
            address(uint160(uint256(vm.load(CONTROLLER, IMPLEMENTATION_SLOT)))) == LEGACY_IMPLEMENTATION,
            "Unexpected controller implementation"
        );
        require(EmergencyController(CONTROLLER).owner() == TIMELOCK, "Unexpected controller owner");

        ILegacyEmergencyControllerUpgradeTargets legacy = ILegacyEmergencyControllerUpgradeTargets(CONTROLLER);
        require(legacy.dusd().code.length != 0, "DUSD not deployed");
        require(legacy.universalRewardsDistributor().code.length != 0, "Rewards distributor not deployed");

        TimelockController timelock = TimelockController(payable(TIMELOCK));
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), OWNER_SAFE), "Owner Safe cannot schedule");
        require(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), OWNER_SAFE)
                || timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)),
            "Owner Safe cannot execute"
        );
        minDelay = timelock.getMinDelay();

        console.log("Existing EmergencyController proxy:", CONTROLLER);
        console.log("Owner Safe:", OWNER_SAFE);
        console.log("Timelock delay in seconds:", minDelay);
    }

    /// @notice Writes Safe Transaction Builder JSON for an implementation that is already deployed.
    function generateTransactions(address implementation) public {
        uint256 minDelay = preflight();
        require(implementation.code.length != 0, "Implementation not deployed");
        require(implementation != LEGACY_IMPLEMENTATION, "Implementation must change");
        require(UUPSUpgradeable(implementation).proxiableUUID() == IMPLEMENTATION_SLOT, "Invalid UUPS implementation");

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = CONTROLLER;
        payloads[0] = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall, (implementation, abi.encodeCall(EmergencyController.initializeV2, ()))
        );

        SafeTransactionBuilder.writeTimelockBatch(
            "emergency-controller-upgrade", TIMELOCK, targets, values, payloads, minDelay
        );

        bytes32 operationId =
            TimelockController(payable(TIMELOCK)).hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));
        console.log("Upgrade implementation:", implementation);
        console.log("Timelock operation ID:");
        console.logBytes32(operationId);
        console.log("Import schedule JSON into the Owner Safe, then execute JSON after the timelock delay.");
    }
}
