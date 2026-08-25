// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {BatchAScript} from "../../scripts/BatchA.s.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";

contract BatchALiveTest is Test {
    string internal constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string internal constant OUTPUT_DIRECTORY = "ERP/ERP-OFFBOARD-02/output/";

    BatchAScript internal batchA;
    IAltoVault internal vault;
    address internal freezerSafe;
    address[] internal borrowMarkets;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        freezerSafe = vm.parseJsonAddress(addresses, ".freezerSafe");
        vault = IAltoVault(vm.parseJsonAddress(addresses, ".contracts.dusdVault"));

        batchA = new BatchAScript();
        borrowMarkets = batchA.borrowMarketsToDeprecate();
    }

    function testLiveBatchAExecutesGeneratedSafeTransactions() public {
        bool[] memory hadPendingCap = new bool[](borrowMarkets.length);
        address[] memory supplyQueueBefore = _supplyQueue();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            MarketConfig memory config = vault.config(borrowMarkets[i]);
            PendingUint192 memory pendingCap = vault.pendingCap(borrowMarkets[i]);
            assertGt(config.cap, 0, "market cap is already zero");
            assertFalse(IPausable(borrowMarkets[i]).paused(FROZEN_TYPE), "market is already frozen");
            hadPendingCap[i] = pendingCap.validAt != 0;
        }

        batchA.run();

        _executeFreezerJson();
        _executeVaultCuratorJson(hadPendingCap);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertTrue(IPausable(borrowMarkets[i]).paused(FROZEN_TYPE), "market was not frozen");
            assertEq(vault.config(borrowMarkets[i]).cap, 0, "market cap was not set to zero");
            assertEq(vault.pendingCap(borrowMarkets[i]).validAt, 0, "pending cap was not cleared");
        }

        _assertSupplyQueueUnchanged(supplyQueueBefore);
    }

    function _executeFreezerJson() private {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, batchA.FREEZER_OUTPUT_FILE()));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), freezerSafe, "wrong Freezer Safe");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            string memory prefix = string.concat(".transactions[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
            bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));

            assertEq(target, borrowMarkets[i], "wrong freeze target or order");
            assertEq(data, abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true)), "wrong freeze calldata");
            assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "non-zero Safe value");
            _callFrom(freezerSafe, target, data);
        }

        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(borrowMarkets.length), "]")),
            "unexpected extra freeze transaction"
        );
    }

    function _executeVaultCuratorJson(bool[] memory hadPendingCap) private {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, batchA.VAULT_CURATOR_OUTPUT_FILE()));
        address curator = vault.curator();
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), curator, "wrong curator Safe");

        uint256 transactionIndex;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (hadPendingCap[i]) {
                _assertAndExecuteVaultTransaction(
                    json, transactionIndex, abi.encodeCall(IAltoVaultBase.revokePendingCap, (borrowMarkets[i])), curator
                );
                ++transactionIndex;
            }

            _assertAndExecuteVaultTransaction(
                json, transactionIndex, abi.encodeCall(IAltoVaultBase.submitCap, (borrowMarkets[i], 0)), curator
            );
            ++transactionIndex;
        }

        assertFalse(
            vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(transactionIndex), "]")),
            "unexpected extra curator transaction"
        );
    }

    function _assertAndExecuteVaultTransaction(
        string memory json,
        uint256 transactionIndex,
        bytes memory expectedData,
        address curator
    ) private {
        string memory prefix = string.concat(".transactions[", vm.toString(transactionIndex), "]");
        address target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
        bytes memory data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));

        assertEq(target, address(vault), "wrong vault target");
        assertEq(data, expectedData, "wrong curator calldata or order");
        assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "non-zero Safe value");
        _callFrom(curator, target, data);
    }

    function _supplyQueue() private view returns (address[] memory queue) {
        queue = new address[](vault.supplyQueueLength());
        for (uint256 i; i < queue.length; ++i) {
            queue[i] = vault.supplyQueue(i);
        }
    }

    function _assertSupplyQueueUnchanged(address[] memory supplyQueueBefore) private view {
        assertEq(vault.supplyQueueLength(), supplyQueueBefore.length, "supply queue length changed");
        for (uint256 i; i < supplyQueueBefore.length; ++i) {
            assertEq(vault.supplyQueue(i), supplyQueueBefore[i], "supply queue changed");
        }
    }

    function _callFrom(address caller, address target, bytes memory data) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        assertTrue(success, string(returnData));
    }
}
