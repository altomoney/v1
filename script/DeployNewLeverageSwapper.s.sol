// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {AltoLeverageSwapper} from "@alto/lending/leverage/AltoLeverageSwapper.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ODOS_ROUTER_V3_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Set this to the deployment timestamp to load addresses from
uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765364975;
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

contract DeployNewLeverageSwapper is Script {
    address constant SYRUP_USDC_BORROW_LEVERAGE = 0xA30Fbc6847e27F795C33C8e298AaD9136A08DA87;

    function run() public {
        address timelock = _loadTimelock();
        require(timelock != address(0), "Timelock not found in deployment JSON");

        console.log("=== Deployment Parameters ===");
        console.log("Timelock:", timelock);
        console.log("Leverage contract:", SYRUP_USDC_BORROW_LEVERAGE);
        console.log("ODOS Router:", ODOS_ROUTER_V3_MAINNET);
        console.log("");

        vm.startBroadcast();

        // Deploy new swapper with ODOS router, deployer as temporary owner
        AltoLeverageSwapper newSwapper = new AltoLeverageSwapper(msg.sender, ODOS_ROUTER_V3_MAINNET);
        console.log("=== Step 1: Deployed new AltoLeverageSwapper ===");
        console.log("New swapper address:", address(newSwapper));
        console.log("Swap target (ODOS):", newSwapper.SWAP_TARGET());
        console.log("Temporary owner:", newSwapper.owner());
        console.log("");

        // Whitelist the leverage contract on the new swapper
        newSwapper.setWhitelisted(SYRUP_USDC_BORROW_LEVERAGE, true);
        console.log("=== Step 2: Whitelisted leverage contract ===");
        console.log("Leverage contract whitelisted:", newSwapper.isWhitelisted(SYRUP_USDC_BORROW_LEVERAGE));
        console.log("");

        // Transfer ownership of swapper from deployer to timelock
        newSwapper.transferOwnership(timelock);
        console.log("=== Step 3: Transferred swapper ownership to timelock ===");
        console.log("New swapper owner:", newSwapper.owner());
        console.log("");

        vm.stopBroadcast();

        // Generate timelock batch transaction data for setSwapper call
        _logTimelockSetSwapperTransaction(timelock, address(newSwapper));
    }

    /// @dev Loads timelock address from deployment JSON
    function _loadTimelock() internal view returns (address) {
        string memory fileName =
            string.concat(OUTPUT_DIR, "/ethereum-mainnet-1-", vm.toString(DEPLOYMENT_ID_TO_LOAD), "/addresses.json");
        string memory json = vm.readFile(fileName);
        return vm.parseJsonAddress(json, ".contracts.timelock");
    }

    /// @dev Logs timelock transaction data for calling setSwapper on the leverage contract
    /// @param timelock The timelock controller address
    /// @param newSwapper The new swapper address to set
    function _logTimelockSetSwapperTransaction(address timelock, address newSwapper) internal view {
        uint256 minDelay = TimelockController(payable(timelock)).getMinDelay();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);

        // Transaction: Call setSwapper on leverage contract
        targets[0] = SYRUP_USDC_BORROW_LEVERAGE;
        values[0] = 0;
        payloads[0] = abi.encodeCall(AltoLeverage.setSwapper, (IAltoLeverageSwapper(newSwapper)));

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, minDelay));

        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        console.log("=== Step 4: Timelock Batch Transaction for setSwapper ===");
        console.log("Timelock:", timelock);
        console.log("Delay (seconds):", minDelay);
        console.log("Number of operations:", targets.length);
        console.log("");

        console.log("--- Batch Contents ---");
        console.log("Operation 0: setSwapper on AltoLeverage");
        console.log("  target:", targets[0]);
        console.log("  value:", values[0]);
        console.log("  payload (setSwapper):");
        console.logBytes(payloads[0]);
        console.log("");

        console.log("--- Step 4a: ScheduleBatch (submit to multisig now) ---");
        console.log("Call timelock at:", timelock);
        console.log("Calldata:");
        console.logBytes(scheduleBatchData);
        console.log("");

        console.log("--- Step 4b: ExecuteBatch (submit to multisig after delay) ---");
        console.log("Call timelock at:", timelock);
        console.log("Calldata:");
        console.logBytes(executeBatchData);
        console.log("==========================================");
    }
}
