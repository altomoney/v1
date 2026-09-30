// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {
    UpgradeEmergencyControllerScript,
    ILegacyEmergencyControllerUpgradeTargets
} from "../../../script/UpgradeEmergencyController.s.sol";

contract InvalidEmergencyUpgradeImplementation {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(0);
    }
}

contract UpgradeEmergencyControllerScriptForkTest is Test {
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-emergency-controller-upgrade-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-emergency-controller-upgrade-execute.json";

    UpgradeEmergencyControllerScript internal upgradeScript;
    EmergencyController internal controller;
    TimelockController internal timelock;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 26089493);
        upgradeScript = new UpgradeEmergencyControllerScript();
        controller = EmergencyController(upgradeScript.CONTROLLER());
        timelock = TimelockController(payable(upgradeScript.TIMELOCK()));
    }

    function test_GeneratedSafeJsonExecutesAtomicMainnetUpgrade() public {
        address dusd = ILegacyEmergencyControllerUpgradeTargets(address(controller)).dusd();
        address rewardsDistributor =
            ILegacyEmergencyControllerUpgradeTargets(address(controller)).universalRewardsDistributor();
        address pendingOwner = controller.pendingOwner();
        bytes32[5] memory legacySlots;
        for (uint256 i; i < legacySlots.length; ++i) {
            legacySlots[i] = vm.load(address(controller), bytes32(i));
        }

        uint256 minDelay = upgradeScript.preflight();
        assertEq(minDelay, timelock.getMinDelay());
        address implementation = upgradeScript.run();
        assertGt(implementation.code.length, 0);
        assertEq(_implementation(), upgradeScript.LEGACY_IMPLEMENTATION(), "deployment does not upgrade proxy");
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        EmergencyController(implementation).initialize(address(this), address(this), address(this), address(this));

        (bytes memory scheduleData, bytes memory executeData) = _generateAndReadJson(implementation);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = address(controller);
        payloads[0] = abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall, (implementation, abi.encodeCall(EmergencyController.initializeV2, ()))
        );
        assertEq(
            scheduleData,
            abi.encodeCall(
                TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), minDelay)
            )
        );
        assertEq(
            executeData,
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), bytes32(0)))
        );
        bytes32 operationId = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));

        _executeAsOwnerSafe(scheduleData);
        assertTrue(timelock.isOperationPending(operationId));
        assertEq(timelock.getTimestamp(operationId), block.timestamp + minDelay);

        vm.prank(upgradeScript.OWNER_SAFE());
        (bool earlyExecutionSucceeded,) = address(timelock).call(executeData);
        assertFalse(earlyExecutionSucceeded, "timelock delay enforced");
        assertEq(_implementation(), upgradeScript.LEGACY_IMPLEMENTATION(), "no early upgrade");

        vm.warp(block.timestamp + minDelay + 1);
        _executeAsOwnerSafe(executeData);
        assertTrue(timelock.isOperationDone(operationId));
        assertEq(_implementation(), implementation);
        assertEq(controller.owner(), address(timelock));
        assertEq(controller.pendingOwner(), pendingOwner);
        for (uint256 i; i < legacySlots.length; ++i) {
            assertEq(vm.load(address(controller), bytes32(i)), legacySlots[i], "legacy storage preserved");
        }
        assertTrue(controller.contractWhitelist(dusd));
        assertTrue(controller.contractWhitelist(rewardsDistributor));

        vm.prank(address(timelock));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        controller.initializeV2();
        vm.expectRevert("Unexpected controller implementation");
        upgradeScript.generateTransactions(implementation);
    }

    function test_PreflightRejectsWrongChain() public {
        vm.chainId(10);
        vm.expectRevert("Ethereum mainnet required");
        upgradeScript.preflight();
    }

    function test_PreflightRejectsUnexpectedImplementation() public {
        vm.store(address(controller), upgradeScript.IMPLEMENTATION_SLOT(), bytes32(uint256(uint160(address(this)))));
        vm.expectRevert("Unexpected controller implementation");
        upgradeScript.preflight();
    }

    function test_GenerationRejectsUndeployedAndLegacyImplementations() public {
        address legacyImplementation = upgradeScript.LEGACY_IMPLEMENTATION();
        vm.expectRevert("Implementation not deployed");
        upgradeScript.generateTransactions(address(0x1234));
        vm.expectRevert("Implementation must change");
        upgradeScript.generateTransactions(legacyImplementation);
    }

    function test_GenerationRejectsInvalidUupsImplementation() public {
        address implementation = address(new InvalidEmergencyUpgradeImplementation());
        vm.expectRevert("Invalid UUPS implementation");
        upgradeScript.generateTransactions(implementation);
    }

    function _implementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(controller), upgradeScript.IMPLEMENTATION_SLOT()))));
    }

    function _generateAndReadJson(address implementation)
        internal
        returns (bytes memory scheduleData, bytes memory executeData)
    {
        bool scheduleExisted = vm.exists(SCHEDULE_JSON);
        bool executeExisted = vm.exists(EXECUTE_JSON);
        string memory oldSchedule = scheduleExisted ? vm.readFile(SCHEDULE_JSON) : "";
        string memory oldExecute = executeExisted ? vm.readFile(EXECUTE_JSON) : "";

        upgradeScript.generateTransactions(implementation);
        string memory scheduleJson = vm.readFile(SCHEDULE_JSON);
        string memory executeJson = vm.readFile(EXECUTE_JSON);

        // Restore real artifacts before checking or executing the fork-only transactions.
        if (scheduleExisted) vm.writeFile(SCHEDULE_JSON, oldSchedule);
        else vm.removeFile(SCHEDULE_JSON);
        if (executeExisted) vm.writeFile(EXECUTE_JSON, oldExecute);
        else vm.removeFile(EXECUTE_JSON);

        scheduleData = _readSafeData(scheduleJson);
        executeData = _readSafeData(executeJson);
    }

    function _readSafeData(string memory json) internal view returns (bytes memory) {
        assertEq(vm.parseJsonString(json, ".chainId"), "1");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(timelock));
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0");
        assertFalse(vm.keyExistsJson(json, ".transactions[1]"), "one Safe transaction");
        return vm.parseJsonBytes(json, ".transactions[0].data");
    }

    function _executeAsOwnerSafe(bytes memory data) internal {
        vm.prank(upgradeScript.OWNER_SAFE());
        (bool success, bytes memory reason) = address(timelock).call(data);
        if (!success) {
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}
