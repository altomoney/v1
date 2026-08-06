// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Generates the transactions that remove every privilege found by
///         AltoDeployerPrivilegesEthereumMainnet.t.sol at block 25,688,751.
/// @dev Run with:
///      forge script script/GenerateRevokeDeploymentPrivilegesTransactions.s.sol:GenerateRevokeDeploymentPrivilegesTransactions --rpc-url ethereum -vvv
/// @dev Run against the requested fork block. The two `safe-tx-*` files are Safe Transaction
///      Builder files for the timelock admin. AddressChange is the sole exception: because its
///      current owner is the Alto deployer EOA, its ownership transfer must be sent by that EOA.
contract GenerateRevokeDeploymentPrivilegesTransactions is Script {
    address internal constant ALTO_DEPLOYER = 0xBA5eD2B1234274a0fFE44E717119C0ECa04703ed;
    address internal constant DUSD_BATCH = 0xe318D8f0dC3C10F507ab7a199e4511fb09737Bdf;

    bytes32 internal constant PREDECESSOR = bytes32(0);
    bytes32 internal constant SALT = bytes32(0);

    string internal constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string internal constant SCHEDULE_FILE =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-revoke-deployment-privileges-schedule.json";
    string internal constant EXECUTE_FILE =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-revoke-deployment-privileges-execute.json";
    string internal constant ADDRESS_CHANGE_FILE =
        "contracts/deployments/ethereum-mainnet/output/alto-deployer-tx-address-change-transfer-ownership.json";

    function run() external {
        string memory addressesJson = vm.readFile(ADDRESSES_FILE);
        address timelock = _readAddress(addressesJson, "timelock");
        address addressChange = _readAddress(addressesJson, "addressChange");
        address dusd = _readAddress(addressesJson, "dusd");
        address[12] memory markets = _readMarkets(addressesJson);

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildTimelockCalls(dusd, markets);

        uint256 delay = TimelockController(payable(timelock)).getMinDelay();
        bytes memory scheduleData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, PREDECESSOR, SALT, delay));
        bytes memory executeData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, PREDECESSOR, SALT));

        vm.writeFile(SCHEDULE_FILE, _buildSafeJson("Revoke deployment privileges - Schedule", timelock, scheduleData));
        vm.writeFile(EXECUTE_FILE, _buildSafeJson("Revoke deployment privileges - Execute", timelock, executeData));

        bytes memory transferOwnershipData = abi.encodeCall(Ownable.transferOwnership, (timelock));
        vm.writeFile(
            ADDRESS_CHANGE_FILE,
            _buildDeployerJson(
                "Transfer AddressChange ownership to timelock", ALTO_DEPLOYER, addressChange, transferOwnershipData
            )
        );

        console2.log("Generated 25 timelock calls (24 market pauser revocations + 1 DUSD batch revocation).");
        console2.log("Schedule Safe file:", SCHEDULE_FILE);
        console2.log("Execute Safe file:", EXECUTE_FILE);
        console2.log("scheduleBatch calldata:");
        console2.logBytes(scheduleData);
        console2.log("executeBatch calldata:");
        console2.logBytes(executeData);
        console2.log("AddressChange requires a separate transaction signed by the current Alto deployer EOA.");
        console2.log("Deployer transaction file:", ADDRESS_CHANGE_FILE);
        console2.log("AddressChange transferOwnership calldata:");
        console2.logBytes(transferOwnershipData);
    }

    function _buildTimelockCalls(address dusd, address[12] memory markets)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](25);
        values = new uint256[](25);
        payloads = new bytes[](25);

        targets[0] = dusd;
        payloads[0] = abi.encodeCall(IPausable.setPauser, (DUSD_BATCH, PAUSE_TYPE, false));

        for (uint256 i; i < markets.length; ++i) {
            uint256 pauseIndex = 1 + i * 2;
            uint256 frozenIndex = pauseIndex + 1;

            targets[pauseIndex] = markets[i];
            payloads[pauseIndex] = abi.encodeCall(IPausable.setPauser, (ALTO_DEPLOYER, PAUSE_TYPE, false));

            targets[frozenIndex] = markets[i];
            payloads[frozenIndex] = abi.encodeCall(IPausable.setPauser, (ALTO_DEPLOYER, FROZEN_TYPE, false));
        }
    }

    function _readMarkets(string memory json) internal pure returns (address[12] memory markets) {
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
            markets[i] = _readAddress(json, keys[i]);
        }
    }

    function _readAddress(string memory json, string memory key) internal pure returns (address) {
        return vm.parseJsonAddress(json, string.concat(".contracts.", key));
    }

    function _buildSafeJson(string memory name, address to, bytes memory data) internal pure returns (string memory) {
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

    function _buildDeployerJson(string memory name, address from, address to, bytes memory data)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '","description":"This transaction must be sent directly by the current Alto deployer EOA; it cannot be executed by the timelock or Safe."},"from":"',
            vm.toString(from),
            '","transactions":[{"to":"',
            vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '"}]}'
        );
    }
}
