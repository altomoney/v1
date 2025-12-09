// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {console} from "forge-std/console.sol";

string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

contract DeployAltoBundler3Script is Script {
    address public bundler3;

    function run() public {
        vm.startBroadcast();

        // Deploy Bundler3 (no constructor parameters)
        bundler3 = address(new Bundler3());

        vm.stopBroadcast();

        // Store deployment data to JSON format
        _writeDeploymentToJson();

        // Extract ABI
        _extractABI();

        console.log("Bundler3 deployed at:", bundler3);
        console.log("Deployment completed successfully");
    }

    function _writeDeploymentToJson() internal {
        string memory contractsJson = "";
        contractsJson = vm.serializeAddress("contracts", "bundler3", bundler3);

        // Build final JSON and write to file
        string memory json = vm.serializeString("", "contracts", contractsJson);
        string memory deploymentFolder =
            string.concat(OUTPUT_DIR, "/bundler3-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");

        vm.createDir(deploymentFolder, true);
        vm.writeJson(json, fileName);
        console.log("Deployment data saved to:", fileName);
    }

    function _extractABI() internal {
        string memory deploymentFolder =
            string.concat(OUTPUT_DIR, "/bundler3-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));
        string memory abiFolder = string.concat(deploymentFolder, "/abi");

        vm.createDir(abiFolder, true);

        _extractContractABI("Bundler3", abiFolder);

        console.log("ABIs extracted to:", abiFolder);
    }

    function _extractContractABI(string memory contractName, string memory outputDir) internal {
        try vm.getCode(contractName) returns (bytes memory) {
            string memory artifactPath = string.concat("./out/", contractName, ".sol/", contractName, ".json");
            string memory fileName = string.concat(outputDir, "/", contractName, ".json");

            // Use jq command to extract just the ABI field from the artifact JSON
            string[] memory inputs = new string[](3);
            inputs[0] = "jq";
            inputs[1] = ".abi";
            inputs[2] = artifactPath;

            // Execute jq command to extract ABI and get the result
            bytes memory result = vm.ffi(inputs);
            string memory abiString = string(result);

            // Write the ABI to file
            vm.writeFile(fileName, abiString);
        } catch {
            console.log("Warning: Could not extract ABI for", contractName);
        }
    }
}

