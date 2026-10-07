// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {SDUSDBatch, SDUSDBatchParams, SDUSDBatchReport} from "@alto/deployments/ethereum-mainnet/SDUSDBatch.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";

/// @notice Deploy and seed a fresh sDUSD, then write its Owner Safe timelock transactions.
/// @dev Run with --rpc-url $MAINNET_RPC_URL --account $ACCOUNT --broadcast --slow. The deployer needs 1 DUSD.
///      Regenerate after deployment with --sig 'generate(address)' $NEW_SDUSD and no --broadcast.
///      Execute the schedule and execute JSONs from the Owner Safe, observing the timelock delay.
///      After execution, update sdusd and sdusdImplementation in addresses.json and export the new SDUSD ABI.
contract ReplaceSDUSDScript is Script {
    function run() public returns (SDUSDBatchReport memory report) {
        string memory json = _addresses();
        SDUSD oldVault = SDUSD(vm.parseJsonAddress(json, ".contracts.sdusd"));
        address controller = vm.parseJsonAddress(json, ".contracts.emergencyController");
        SDUSDBatchParams memory params = SDUSDBatchParams({
            rewarder: vm.parseJsonAddress(json, ".contracts.protocolFeeCollector"),
            timelock: vm.parseJsonAddress(json, ".contracts.timelock"),
            freezer: address(EmergencyController(controller).pauserSafe()),
            emergencyController: controller,
            dusd: oldVault.asset(),
            seedShares: 1 ether,
            depositCap: 0,
            rewardDuration: oldVault.rewardDuration()
        });
        Options memory opts;
        Upgrades.validateImplementation("SDUSD.sol:SDUSD", opts);

        vm.startBroadcast();
        report = new SDUSDBatch(params).getReport();
        require(IERC20(params.dusd).approve(report.sdusd, params.seedShares), "Seed approval failed");
        SDUSD(report.sdusd).deposit(params.seedShares, address(1));
        vm.stopBroadcast();
        generate(report.sdusd);
    }

    function generate(address replacement) public {
        string memory json = _addresses();
        address oldVault = vm.parseJsonAddress(json, ".contracts.sdusd");
        address collector = vm.parseJsonAddress(json, ".contracts.protocolFeeCollector");
        address timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        address adapter = vm.parseJsonAddress(json, ".contracts.altoAdapter");
        address controller = vm.parseJsonAddress(json, ".contracts.emergencyController");
        require(
            replacement != oldVault && ProtocolFeeCollector(collector).sdusdVault() == oldVault,
            "Unexpected active vault"
        );
        {
            SDUSD vault = SDUSD(replacement);
            require(
                vault.owner() == timelock && vault.asset() == SDUSD(oldVault).asset() && vault.rewarder() == collector,
                "Unexpected replacement"
            );
            require(
                vault.depositCap() == 0 && vault.balanceOf(address(1)) == 1 ether,
                "Replacement must be seeded and closed"
            );
        }

        uint256 oldCap = SDUSD(oldVault).depositCap();
        uint256 cap = vm.envOr("SDUSD_REPLACEMENT_DEPOSIT_CAP", oldCap == 0 ? 250_000 ether : oldCap);
        require(cap != 0, "Invalid deposit cap");
        address[] memory targets = new address[](oldCap == 0 ? 6 : 7);
        uint256[] memory values = new uint256[](targets.length);
        bytes[] memory payloads = new bytes[](targets.length);
        uint256 i;
        if (oldCap != 0) {
            targets[i] = oldVault;
            payloads[i++] = abi.encodeCall(SDUSD.setDepositCap, (0));
        }
        targets[i] = collector;
        payloads[i++] = abi.encodeCall(ProtocolFeeCollector.setSdusdVault, (replacement));
        targets[i] = adapter;
        payloads[i++] = abi.encodeCall(AdapterContractApproval.approveContract, (replacement));
        targets[i] = adapter;
        payloads[i++] = abi.encodeCall(AdapterContractApproval.revokeContract, (oldVault));
        targets[i] = controller;
        payloads[i++] = abi.encodeCall(EmergencyController.setContractWhitelist, (replacement, true));
        targets[i] = controller;
        payloads[i++] = abi.encodeCall(EmergencyController.setContractWhitelist, (oldVault, false));
        targets[i] = replacement;
        payloads[i] = abi.encodeCall(SDUSD.setDepositCap, (cap));
        SafeTransactionBuilder.writeTimelockBatch(
            "sdusd-replacement",
            timelock,
            targets,
            values,
            payloads,
            TimelockController(payable(timelock)).getMinDelay()
        );
    }

    function _addresses() internal view returns (string memory) {
        require(block.chainid == 1, "Not Ethereum mainnet");
        return vm.readFile("contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json");
    }
}
