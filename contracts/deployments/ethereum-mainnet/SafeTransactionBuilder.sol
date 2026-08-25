// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

library SafeTransactionBuilder {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string private constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function writeTimelockBatch(
        string memory name,
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        bytes memory scheduleData = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), bytes32(0), delay)
        );
        bytes memory executeData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, bytes32(0), bytes32(0)));

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json"),
            _singleTransactionJson(string.concat(name, " - Schedule"), timelock, scheduleData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json"),
            _singleTransactionJson(string.concat(name, " - Execute"), timelock, executeData)
        );

        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json  (propose)", name);
        console.log("  2. safe-tx-%s-execute.json   (execute after delay)", name);
    }

    function writeDirectBatch(
        string memory name,
        address safe,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads
    ) internal {
        uint256 callCount = targets.length;
        require(safe != address(0), "Invalid Safe");
        require(callCount != 0 && values.length == callCount && payloads.length == callCount, "Invalid Safe batch");

        string memory transactions;
        for (uint256 i; i < callCount; ++i) {
            transactions = string.concat(
                transactions,
                i == 0 ? "" : ",",
                '{"to":"',
                vm.toString(targets[i]),
                '","value":"',
                vm.toString(values[i]),
                '","data":"',
                vm.toString(payloads[i]),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, ".json"),
            string.concat(
                '{"version":"1.0","chainId":"1","meta":{"name":"',
                name,
                '","txBuilderVersion":"1.16.5","createdFromSafeAddress":"',
                vm.toString(safe),
                '"},"transactions":[',
                transactions,
                "]}"
            )
        );

        console.log("Safe TX Builder JSON written: safe-tx-%s.json", name);
        console.log("  Submit from Safe:", safe);
    }

    function _singleTransactionJson(string memory name, address to, bytes memory data)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '"},"transactions":[{"to":"',
            vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '"}]}'
        );
    }
}
