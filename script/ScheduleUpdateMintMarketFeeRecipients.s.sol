// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

string constant ADDRESSES_FILE =
    "./contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

contract ScheduleUpdateMintMarketFeeRecipients is Script {
    address constant TIMELOCK_CONTROLLER = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant NEW_FEE_RECIPIENT = 0x5F80c18b6B73B1C4F06fa5233De32778eC90FA96;

    function run() public {
        // Read addresses from JSON file
        string memory addressesJson = vm.readFile(ADDRESSES_FILE);

        // Extract mint market addresses
        address wethMarket = vm.parseJsonAddress(addressesJson, ".contracts.wethMarket");
        address wstethMarket = vm.parseJsonAddress(addressesJson, ".contracts.wstethMarket");
        address rethMarket = vm.parseJsonAddress(addressesJson, ".contracts.rethMarket");
        address methMarket = vm.parseJsonAddress(addressesJson, ".contracts.methMarket");
        address tbtcMarket = vm.parseJsonAddress(addressesJson, ".contracts.tbtcMarket");

        console.log("=== Scheduling Batch Update Fee Recipients ===");
        console.log("Timelock Controller:", TIMELOCK_CONTROLLER);
        console.log("New Fee Recipient:", NEW_FEE_RECIPIENT);
        console.log("");
        console.log("Mint Markets:");
        console.log("  WETH Market:", wethMarket);
        console.log("  wstETH Market:", wstethMarket);
        console.log("  rETH Market:", rethMarket);
        console.log("  mETH Market:", methMarket);
        console.log("  tBTC Market:", tbtcMarket);
        console.log("");

        // Prepare arrays for scheduleBatch
        address[] memory targets = new address[](5);
        uint256[] memory values = new uint256[](5);
        bytes[] memory payloads = new bytes[](5);

        // Encode setFeeRecipient calls for each market
        bytes4 setFeeRecipientSelector = bytes4(keccak256("setFeeRecipient(address)"));

        targets[0] = wethMarket;
        values[0] = 0;
        payloads[0] = abi.encodeWithSelector(setFeeRecipientSelector, NEW_FEE_RECIPIENT);

        targets[1] = wstethMarket;
        values[1] = 0;
        payloads[1] = abi.encodeWithSelector(setFeeRecipientSelector, NEW_FEE_RECIPIENT);

        targets[2] = rethMarket;
        values[2] = 0;
        payloads[2] = abi.encodeWithSelector(setFeeRecipientSelector, NEW_FEE_RECIPIENT);

        targets[3] = methMarket;
        values[3] = 0;
        payloads[3] = abi.encodeWithSelector(setFeeRecipientSelector, NEW_FEE_RECIPIENT);

        targets[4] = tbtcMarket;
        values[4] = 0;
        payloads[4] = abi.encodeWithSelector(setFeeRecipientSelector, NEW_FEE_RECIPIENT);

        // Get timelock delay
        TimelockController timelock = TimelockController(payable(TIMELOCK_CONTROLLER));

        // Schedule the batch operation
        vm.startBroadcast();

        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 0);

        console.log("Batch operation scheduled successfully!");
        console.log("");

        console.log("Executing batch operation immediately (delay is 0)...");
        timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));
        console.log("Batch operation executed successfully!");
        console.log("");

        // Verify fee recipients were updated
        console.log("=== Verifying Fee Recipients ===");
        console.log("Expected Fee Recipient:", NEW_FEE_RECIPIENT);
        console.log("");

        IMarket wethMarketContract = IMarket(wethMarket);
        IMarket wstethMarketContract = IMarket(wstethMarket);
        IMarket rethMarketContract = IMarket(rethMarket);
        IMarket methMarketContract = IMarket(methMarket);
        IMarket tbtcMarketContract = IMarket(tbtcMarket);

        address wethFeeRecipient = wethMarketContract.feeRecipient();
        address wstethFeeRecipient = wstethMarketContract.feeRecipient();
        address rethFeeRecipient = rethMarketContract.feeRecipient();
        address methFeeRecipient = methMarketContract.feeRecipient();
        address tbtcFeeRecipient = tbtcMarketContract.feeRecipient();

        console.log("WETH Market Fee Recipient:", wethFeeRecipient);
        console.log("wstETH Market Fee Recipient:", wstethFeeRecipient);
        console.log("rETH Market Fee Recipient:", rethFeeRecipient);
        console.log("mETH Market Fee Recipient:", methFeeRecipient);
        console.log("tBTC Market Fee Recipient:", tbtcFeeRecipient);
        console.log("");

        // Verify all match expected value
        require(wethFeeRecipient == NEW_FEE_RECIPIENT, "WETH market fee recipient mismatch");
        require(wstethFeeRecipient == NEW_FEE_RECIPIENT, "wstETH market fee recipient mismatch");
        require(rethFeeRecipient == NEW_FEE_RECIPIENT, "rETH market fee recipient mismatch");
        require(methFeeRecipient == NEW_FEE_RECIPIENT, "mETH market fee recipient mismatch");
        require(tbtcFeeRecipient == NEW_FEE_RECIPIENT, "tBTC market fee recipient mismatch");

        console.log("All fee recipients verified successfully!");

        vm.stopBroadcast();
    }
}

