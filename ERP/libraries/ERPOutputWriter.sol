// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Ordered calls to be submitted by a Safe directly or wrapped in one atomic Timelock batch.
struct ERPTransactionBatch {
    address safe;
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

/// @notice One caller-target transaction described in a generic, non-Safe ERP artifact.
struct ERPTransactionPlan {
    address caller;
    address target;
    bytes data;
    string functionName;
    string argumentsJson;
    string postconditionsJson;
}

/// @notice One transaction within an ordered generic ERP plan.
struct ERPTransactionPlanCall {
    address target;
    bytes data;
    string functionName;
    string argumentsJson;
}

/// @notice Ordered transactions submitted by one non-Safe ERP caller.
struct ERPTransactionPlanBatch {
    address caller;
    address target;
    ERPTransactionPlanCall[] calls;
    string postconditionsJson;
}

/// @notice Shared Safe Transaction Builder and Timelock artifact helpers for ERPs.
library ERPOutputWriter {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function newBatch(address safe, uint256 callCount) internal pure returns (ERPTransactionBatch memory batch) {
        batch.safe = safe;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);
    }

    function addBatchCall(ERPTransactionBatch memory batch, uint256 index, address target, bytes memory payload)
        internal
        pure
        returns (uint256)
    {
        batch.targets[index] = target;
        batch.payloads[index] = payload;
        return index + 1;
    }

    function timelockCalldata(address timelock, ERPTransactionBatch memory calls, uint256 delay, bytes32 predecessor)
        internal
        pure
        returns (bytes memory scheduleData, bytes memory executeData, bytes32 operationId)
    {
        _validateBatch(calls);
        bytes32 salt;
        scheduleData = abi.encodeCall(
            TimelockController.scheduleBatch, (calls.targets, calls.values, calls.payloads, predecessor, salt, delay)
        );
        executeData = abi.encodeCall(
            TimelockController.executeBatch, (calls.targets, calls.values, calls.payloads, predecessor, salt)
        );
        operationId = keccak256(abi.encode(calls.targets, calls.values, calls.payloads, predecessor, salt));
        require(timelock != address(0), "ERP: zero Timelock");
    }

    function writeOptionalTimelockPair(
        string memory outputDirectory,
        string memory fileStem,
        string memory name,
        address timelock,
        ERPTransactionBatch memory batch,
        uint256 delay,
        bytes32 predecessor
    ) internal {
        if (batch.targets.length == 0) {
            removeIfExists(string.concat(outputDirectory, "/", fileStem, "-schedule.json"));
            removeIfExists(string.concat(outputDirectory, "/", fileStem, "-execute.json"));
            console2.log("No Timelock transactions required; removed stale output if present:", fileStem);
            return;
        }

        writeTimelockPair(outputDirectory, fileStem, name, timelock, batch, delay, predecessor);
    }

    function writeTimelockPair(
        string memory outputDirectory,
        string memory fileStem,
        string memory name,
        address timelock,
        ERPTransactionBatch memory batch,
        uint256 delay,
        bytes32 predecessor
    ) internal {
        (bytes memory scheduleData, bytes memory executeData,) = timelockCalldata(timelock, batch, delay, predecessor);

        writeSingleTransactionSafeBatch(
            outputDirectory,
            string.concat(fileStem, "-schedule.json"),
            string.concat(name, " - Schedule"),
            batch.safe,
            timelock,
            scheduleData
        );
        writeSingleTransactionSafeBatch(
            outputDirectory,
            string.concat(fileStem, "-execute.json"),
            string.concat(name, " - Execute"),
            batch.safe,
            timelock,
            executeData
        );
    }

    function writeSingleTransactionSafeBatch(
        string memory outputDirectory,
        string memory fileName,
        string memory name,
        address safe,
        address target,
        bytes memory payload
    ) internal {
        ERPTransactionBatch memory batch = newBatch(safe, 1);
        addBatchCall(batch, 0, target, payload);
        writeSafeBatch(outputDirectory, fileName, name, batch);
    }

    function writeOptionalSafeBatch(
        string memory outputDirectory,
        string memory fileName,
        string memory name,
        ERPTransactionBatch memory batch
    ) internal {
        if (batch.targets.length == 0) {
            removeIfExists(string.concat(outputDirectory, "/", fileName));
            console2.log("No Safe transactions required; removed stale output if present:", fileName);
            return;
        }

        writeSafeBatch(outputDirectory, fileName, name, batch);
    }

    function writeSafeBatch(
        string memory outputDirectory,
        string memory fileName,
        string memory name,
        ERPTransactionBatch memory batch
    ) internal {
        _validateBatch(batch);
        require(batch.safe != address(0), "ERP: zero Safe");

        string memory transactions;
        for (uint256 i; i < batch.targets.length; ++i) {
            transactions = string.concat(
                transactions,
                i == 0 ? "" : ",",
                '{"to":"',
                vm.toString(batch.targets[i]),
                '","value":"',
                vm.toString(batch.values[i]),
                '","data":"',
                vm.toString(batch.payloads[i]),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        vm.writeFile(
            string.concat(outputDirectory, "/", fileName),
            string.concat(
                '{"version":"1.0","chainId":"',
                vm.toString(block.chainid),
                '","meta":{"name":"',
                name,
                '","txBuilderVersion":"1.16.5","createdFromSafeAddress":"',
                vm.toString(batch.safe),
                '"},"transactions":[',
                transactions,
                "]}"
            )
        );

        console2.log("Safe Transaction Builder JSON written:", fileName);
        console2.log("Submit from Safe:", batch.safe);
    }

    function writeOptionalTransactionPlan(
        string memory outputDirectory,
        string memory fileName,
        uint256 sourceBlock,
        ERPTransactionPlan memory plan
    ) internal {
        string memory path = string.concat(outputDirectory, "/", fileName);
        if (plan.data.length == 0) {
            removeIfExists(path);
            console2.log("No transaction required; removed stale output if present:", fileName);
            return;
        }

        require(plan.caller != address(0), "ERP: zero caller");
        require(plan.target != address(0), "ERP: zero target");
        vm.writeFile(
            path,
            string.concat(
                "{\"version\":\"1.0\",\"chainId\":\"",
                vm.toString(block.chainid),
                "\",\"sourceBlock\":\"",
                vm.toString(sourceBlock),
                "\",\"caller\":\"",
                vm.toString(plan.caller),
                "\",\"vault\":\"",
                vm.toString(plan.target),
                "\",\"transaction\":{\"to\":\"",
                vm.toString(plan.target),
                "\",\"value\":\"0\",\"data\":\"",
                vm.toString(plan.data),
                "\",\"function\":\"",
                plan.functionName,
                "\",\"arguments\":",
                plan.argumentsJson,
                "},\"postconditions\":",
                plan.postconditionsJson,
                "}"
            )
        );
        console2.log("Transaction plan written:", fileName);
        console2.log("Execute from caller:", plan.caller);
    }

    function writeOptionalTransactionPlanBatch(
        string memory outputDirectory,
        string memory fileName,
        uint256 sourceBlock,
        ERPTransactionPlanBatch memory plan
    ) internal {
        string memory path = string.concat(outputDirectory, "/", fileName);
        if (plan.calls.length == 0) {
            removeIfExists(path);
            console2.log("No transactions required; removed stale output if present:", fileName);
            return;
        }

        require(plan.caller != address(0), "ERP: zero caller");
        require(plan.target != address(0), "ERP: zero target");

        string memory transactions;
        for (uint256 i; i < plan.calls.length; ++i) {
            ERPTransactionPlanCall memory call = plan.calls[i];
            require(call.target != address(0), "ERP: zero transaction target");
            require(call.data.length != 0, "ERP: empty transaction data");
            transactions = string.concat(
                transactions,
                i == 0 ? "" : ",",
                "{\"to\":\"",
                vm.toString(call.target),
                "\",\"value\":\"0\",\"data\":\"",
                vm.toString(call.data),
                "\",\"function\":\"",
                call.functionName,
                "\",\"arguments\":",
                call.argumentsJson,
                "}"
            );
        }

        vm.writeFile(
            path,
            string.concat(
                "{\"version\":\"1.0\",\"chainId\":\"",
                vm.toString(block.chainid),
                "\",\"sourceBlock\":\"",
                vm.toString(sourceBlock),
                "\",\"caller\":\"",
                vm.toString(plan.caller),
                "\",\"vault\":\"",
                vm.toString(plan.target),
                "\",\"transactions\":[",
                transactions,
                "],\"postconditions\":",
                plan.postconditionsJson,
                "}"
            )
        );
        console2.log("Transaction plan written:", fileName);
        console2.log("Execute transactions in order from caller:", plan.caller);
    }

    function addressArrayJson(address[] memory values) internal pure returns (string memory json) {
        json = "[";
        for (uint256 i; i < values.length; ++i) {
            json = string.concat(json, i == 0 ? "" : ",", "\"", vm.toString(values[i]), "\"");
        }
        return string.concat(json, "]");
    }

    function uintArrayJson(uint256[] memory values) internal pure returns (string memory json) {
        json = "[";
        for (uint256 i; i < values.length; ++i) {
            json = string.concat(json, i == 0 ? "" : ",", vm.toString(values[i]));
        }
        return string.concat(json, "]");
    }

    function uintString(uint256 value) internal pure returns (string memory) {
        return vm.toString(value);
    }

    function addressString(address value) internal pure returns (string memory) {
        return vm.toString(value);
    }

    function removeIfExists(string memory path) internal {
        if (vm.exists(path)) vm.removeFile(path);
    }

    function _validateBatch(ERPTransactionBatch memory batch) private pure {
        uint256 callCount = batch.targets.length;
        require(callCount != 0, "ERP: empty batch");
        require(batch.values.length == callCount, "ERP: target/value length mismatch");
        require(batch.payloads.length == callCount, "ERP: target/payload length mismatch");
    }
}
