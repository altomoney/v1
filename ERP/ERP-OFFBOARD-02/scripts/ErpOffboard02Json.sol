// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

struct SafeTransaction {
    address to;
    uint256 value;
    bytes data;
}

/// @notice Shared JSON writer for ERP-OFFBOARD-02 batch scripts.
/// @dev Every generated file is directly importable by Safe Transaction Builder.
abstract contract ErpOffboard02Json is Script {
    string internal constant OUTPUT_DIRECTORY = "ERP/ERP-OFFBOARD-02/output/";

    /// @dev Production Timelock proposer/executor Safe from `script/DeployAltoEthereumMainnet.s.sol`.
    /// The deployment output JSON contains contract addresses only, so this control address cannot be read from it.
    address internal constant MAINNET_TIMELOCK_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;

    function _transaction(address to, bytes memory data) internal pure returns (SafeTransaction memory) {
        return SafeTransaction({to: to, value: 0, data: data});
    }

    function _writeSafeBatch(
        string memory fileName,
        string memory name,
        address safe,
        SafeTransaction[] memory transactions
    ) internal {
        require(safe != address(0), "ERP: zero Safe");
        require(transactions.length != 0, "ERP: empty Safe batch");
        vm.writeFile(string.concat(OUTPUT_DIRECTORY, fileName), _safeBatchJson(name, safe, transactions));
    }

    function _writeTimelockPair(
        string memory fileStem,
        string memory name,
        address safe,
        address timelock,
        uint256 delay,
        SafeTransaction[] memory calls
    ) internal {
        require(timelock != address(0) && timelock.code.length != 0, "ERP: invalid Timelock");
        require(calls.length != 0, "ERP: empty Timelock batch");

        TimelockController controller = TimelockController(payable(timelock));
        require(controller.hasRole(controller.PROPOSER_ROLE(), safe), "ERP: Safe is not Timelock proposer");
        require(
            controller.hasRole(controller.EXECUTOR_ROLE(), safe)
                || controller.hasRole(controller.EXECUTOR_ROLE(), address(0)),
            "ERP: Safe is not Timelock executor"
        );
        require(delay >= controller.getMinDelay(), "ERP: delay below Timelock minimum");

        address[] memory targets = new address[](calls.length);
        uint256[] memory values = new uint256[](calls.length);
        bytes[] memory payloads = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            targets[i] = calls[i].to;
            values[i] = calls[i].value;
            payloads[i] = calls[i].data;
        }

        bytes32 predecessor;
        bytes32 salt;
        SafeTransaction[] memory schedule = new SafeTransaction[](1);
        schedule[0] = _transaction(
            timelock,
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay))
        );

        SafeTransaction[] memory execute = new SafeTransaction[](1);
        execute[0] = _transaction(
            timelock, abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt))
        );

        _writeSafeBatch(string.concat(fileStem, "-schedule.json"), string.concat(name, " - Schedule"), safe, schedule);
        _writeSafeBatch(string.concat(fileStem, "-execute.json"), string.concat(name, " - Execute"), safe, execute);
    }

    function _safeBatchJson(string memory name, address safe, SafeTransaction[] memory transactions)
        private
        view
        returns (string memory json)
    {
        json = string.concat(
            '{"version":"1.0","chainId":"',
            vm.toString(block.chainid),
            '","meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5","createdFromSafeAddress":"',
            vm.toString(safe),
            '"},"transactions":['
        );

        for (uint256 i; i < transactions.length; ++i) {
            SafeTransaction memory transaction = transactions[i];
            if (i != 0) json = string.concat(json, ",");
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(transaction.to),
                '","value":"',
                vm.toString(transaction.value),
                '","data":"',
                vm.toString(transaction.data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        return string.concat(json, "]}");
    }
}
