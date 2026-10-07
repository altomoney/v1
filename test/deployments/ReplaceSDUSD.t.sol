// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ReplaceSDUSDScript} from "../../script/ReplaceSDUSD.s.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {SDUSDBatch, SDUSDBatchParams, SDUSDBatchReport} from "@alto/deployments/ethereum-mainnet/SDUSDBatch.sol";

contract ReplaceSDUSDMainnetForkTest is Test {
    function testFork_GeneratedJsonSwitchesVaultAndPreservesLegacyWithdrawals() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 26141093);
        string memory json =
            vm.readFile("contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json");
        SDUSD oldVault = SDUSD(vm.parseJsonAddress(json, ".contracts.sdusd"));
        ProtocolFeeCollector collector =
            ProtocolFeeCollector(vm.parseJsonAddress(json, ".contracts.protocolFeeCollector"));
        EmergencyController controller =
            EmergencyController(vm.parseJsonAddress(json, ".contracts.emergencyController"));
        AdapterContractApproval adapter = AdapterContractApproval(vm.parseJsonAddress(json, ".contracts.altoAdapter"));
        TimelockController timelock = TimelockController(payable(vm.parseJsonAddress(json, ".contracts.timelock")));
        SDUSDBatchReport memory report = new SDUSDBatch(
                SDUSDBatchParams({
                rewarder: address(collector),
                timelock: address(timelock),
                freezer: address(controller.pauserSafe()),
                emergencyController: address(controller),
                dusd: oldVault.asset(),
                seedShares: 1 ether,
                depositCap: 0,
                rewardDuration: oldVault.rewardDuration()
            })
            ).getReport();
        SDUSD vault = SDUSD(report.sdusd);
        IERC20 dusd = IERC20(oldVault.asset());
        deal(address(dusd), address(this), 6 ether);
        dusd.approve(address(vault), 1 ether);
        vault.deposit(1 ether, address(1));
        assertEq(vault.maxDeposit(address(this)), 0);

        new ReplaceSDUSDScript().generate(address(vault));
        string memory prefix = "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-replacement";
        string memory schedulePath = string.concat(prefix, "-schedule.json");
        string memory executePath = string.concat(prefix, "-execute.json");
        _callSafeJson(schedulePath, address(timelock));
        vm.warp(block.timestamp + timelock.getMinDelay());

        // Deposits arriving during the timelock delay must remain redeemable after the switch.
        dusd.approve(address(oldVault), 5 ether);
        uint256 shares = oldVault.deposit(5 ether, address(this));
        uint256 cap = oldVault.depositCap();
        _callSafeJson(executePath, address(timelock));
        assertEq(collector.sdusdVault(), address(vault));
        assertEq(oldVault.depositCap(), 0);
        assertEq(vault.depositCap(), cap);
        assertTrue(adapter.isApprovedContract(address(vault)));
        assertFalse(adapter.isApprovedContract(address(oldVault)));
        assertTrue(controller.contractWhitelist(address(vault)));
        assertFalse(controller.contractWhitelist(address(oldVault)));
        assertEq(oldVault.redeem(shares, address(this), address(this)), 5 ether);
        dusd.approve(address(vault), 5 ether);
        assertEq(vault.deposit(5 ether, address(this)), 5 ether);
        vm.removeFile(schedulePath);
        vm.removeFile(executePath);
    }

    function _callSafeJson(string memory path, address timelock) private {
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonString(json, ".chainId"), "1");
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), timelock);
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        vm.prank(0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0);
        (bool success,) = timelock.call(data);
        assertTrue(success, "Safe timelock transaction failed");
    }
}
