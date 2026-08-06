// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {GenerateRevokeDeploymentPrivilegesTransactions} from
    "../../script/GenerateRevokeDeploymentPrivilegesTransactions.s.sol";

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IPauserPermissions is IPausable {
    function pausers(address account, bytes32 pauseType) external view returns (bool);
}

/// @notice Executes the exact generated transaction files on the requested mainnet fork and
///         proves that every privilege found by the deployment-privilege audit is removed.
contract RevokeDeploymentPrivilegesEthereumMainnetTest is Test {
    address internal constant ALTO_DEPLOYER = 0xBA5eD2B1234274a0fFE44E717119C0ECa04703ed;
    address internal constant DUSD_BATCH = 0xe318D8f0dC3C10F507ab7a199e4511fb09737Bdf;
    address internal constant MAINNET_TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    uint256 internal constant FORK_BLOCK = 25_688_751;

    string internal constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string internal constant SCHEDULE_FILE =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-revoke-deployment-privileges-schedule.json";
    string internal constant EXECUTE_FILE =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-revoke-deployment-privileges-execute.json";
    string internal constant ADDRESS_CHANGE_FILE =
        "contracts/deployments/ethereum-mainnet/output/alto-deployer-tx-address-change-transfer-ownership.json";

    string internal addressesJson;
    address internal timelock;
    address internal addressChange;
    address internal dusd;
    address[12] internal markets;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        addressesJson = vm.readFile(ADDRESSES_FILE);
        timelock = _readAddress("timelock");
        addressChange = _readAddress("addressChange");
        dusd = _readAddress("dusd");
        markets = _readMarkets();

        assertEq(block.number, FORK_BLOCK, "test must use the audited fork block");
    }

    function test_generatedTransactionsRemoveEveryAuditedPrivilege() public {
        _assertAuditedPrivilegesArePresent();
        new GenerateRevokeDeploymentPrivilegesTransactions().run();

        _executeAddressChangeOwnershipFile();
        _scheduleAndExecuteTimelockFiles();

        assertEq(Ownable(addressChange).owner(), timelock, "AddressChange owner was not transferred");
        assertFalse(IPauserPermissions(dusd).pausers(DUSD_BATCH, PAUSE_TYPE), "DUSDBatch retained DUSD PAUSE_TYPE");

        for (uint256 i; i < markets.length; ++i) {
            address market = markets[i];
            assertEq(Ownable(market).owner(), timelock, "market owner changed unexpectedly");
            assertFalse(
                IPauserPermissions(market).pausers(ALTO_DEPLOYER, PAUSE_TYPE),
                "Alto deployer retained market PAUSE_TYPE"
            );
            assertFalse(
                IPauserPermissions(market).pausers(ALTO_DEPLOYER, FROZEN_TYPE),
                "Alto deployer retained market FROZEN_TYPE"
            );
        }
    }

    function _assertAuditedPrivilegesArePresent() internal view {
        assertEq(Ownable(addressChange).owner(), ALTO_DEPLOYER, "unexpected AddressChange owner at fork block");
        assertEq(Ownable(dusd).owner(), timelock, "unexpected DUSD owner at fork block");
        assertTrue(
            IPauserPermissions(dusd).pausers(DUSD_BATCH, PAUSE_TYPE), "expected DUSDBatch DUSD PAUSE_TYPE finding"
        );

        TimelockController controller = TimelockController(payable(timelock));
        assertTrue(
            controller.hasRole(controller.PROPOSER_ROLE(), MAINNET_TIMELOCK_ADMIN), "Safe is not a timelock proposer"
        );
        assertTrue(
            controller.hasRole(controller.EXECUTOR_ROLE(), MAINNET_TIMELOCK_ADMIN), "Safe is not a timelock executor"
        );

        for (uint256 i; i < markets.length; ++i) {
            address market = markets[i];
            assertEq(Ownable(market).owner(), timelock, "unexpected market owner at fork block");
            assertTrue(
                IPauserPermissions(market).pausers(ALTO_DEPLOYER, PAUSE_TYPE),
                "expected Alto deployer market PAUSE_TYPE finding"
            );
            assertTrue(
                IPauserPermissions(market).pausers(ALTO_DEPLOYER, FROZEN_TYPE),
                "expected Alto deployer market FROZEN_TYPE finding"
            );
        }
    }

    function _executeAddressChangeOwnershipFile() internal {
        string memory json = vm.readFile(ADDRESS_CHANGE_FILE);
        address from = vm.parseJsonAddress(json, ".from");
        address target = vm.parseJsonAddress(json, ".transactions[0].to");
        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");

        assertEq(from, ALTO_DEPLOYER, "wrong signer in AddressChange transaction file");
        assertEq(target, addressChange, "wrong target in AddressChange transaction file");

        vm.prank(from);
        (bool success,) = target.call(data);
        assertTrue(success, "AddressChange ownership transaction failed");
    }

    function _scheduleAndExecuteTimelockFiles() internal {
        TimelockController controller = TimelockController(payable(timelock));
        (address scheduleTarget, bytes memory scheduleData) = _readSafeTransaction(SCHEDULE_FILE);
        (address executeTarget, bytes memory executeData) = _readSafeTransaction(EXECUTE_FILE);

        assertEq(scheduleTarget, timelock, "schedule file targets wrong timelock");
        assertEq(executeTarget, timelock, "execute file targets wrong timelock");

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool scheduled,) = scheduleTarget.call(scheduleData);
        assertTrue(scheduled, "timelock scheduleBatch transaction failed");

        vm.warp(block.timestamp + controller.getMinDelay() + 1);

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool executed,) = executeTarget.call(executeData);
        assertTrue(executed, "timelock executeBatch transaction failed");
    }

    function _readSafeTransaction(string memory path) internal view returns (address target, bytes memory data) {
        string memory json = vm.readFile(path);
        target = vm.parseJsonAddress(json, ".transactions[0].to");
        data = vm.parseJsonBytes(json, ".transactions[0].data");
    }

    function _readMarkets() internal view returns (address[12] memory result) {
        string[12] memory keys = [
            "wethMarket",
            "wstethMarket",
            "rethMarket",
            "methMarket",
            "tbtcMarket",
            "wbtcBorrowMarket",
            "cbbtcBorrowMarket",
            "susdeBorrowMarket",
            "syrupUsdcBorrowMarket",
            "paxgBorrowMarket",
            "susdeMintMarket",
            "syrupUsdcMintMarket"
        ];

        for (uint256 i; i < keys.length; ++i) {
            result[i] = _readAddress(keys[i]);
        }
    }

    function _readAddress(string memory key) internal view returns (address) {
        return vm.parseJsonAddress(addressesJson, string.concat(".contracts.", key));
    }
}
