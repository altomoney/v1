// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

/// @title Deprecate Permissionless USDC USM
/// @notice Generates timelock Safe TX payloads for deprecating the permissionless USDC PSM.
///         PSM must already be frozen and drained before running this script.
/// @dev Run with: forge script script/DeprecatePermissionlessUsdcUsm.s.sol --fork-url ethereum -vvv
contract DeprecatePermissionlessUsdcUsmScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant USDC_PSM = 0x4026db9152cEb2e6D376de72Efb70eb8F407A0e4;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant USM_REGISTRY = 0xAD5620e10C33918E2C6A2E8E53325bf98c548E5e;
    address constant ALTO_ADAPTER = 0x4F46bb6948190eDd091c3A4f47DC2946Ae627369;
    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        uint256 usdcDust = IERC20(USDC).balanceOf(USDC_PSM);

        address[] memory targets = new address[](7);
        uint256[] memory values = new uint256[](7);
        bytes[] memory payloads = new bytes[](7);

        targets[0] = USDC_PSM;
        payloads[0] = abi.encodeCall(IAccessControl.grantRole, (IUsm(USDC_PSM).TOKEN_RESCUER_ROLE(), TIMELOCK));

        targets[1] = USDC_PSM;
        payloads[1] = abi.encodeCall(IUsm.rescueTokens, (USDC, TREASURY, usdcDust));

        targets[2] = DUSD;
        payloads[2] = abi.encodeCall(IDUSD.setMinterStatus, (USDC_PSM, false));

        targets[3] = DUSD;
        payloads[3] = abi.encodeCall(IDUSD.setMinterCeiling, (USDC_PSM, 0));

        targets[4] = DUSD;
        payloads[4] = abi.encodeCall(IDUSD.setBurnerStatus, (USDC_PSM, false));

        targets[5] = USM_REGISTRY;
        payloads[5] = abi.encodeCall(IUsmRegistry.removeUsm, (USDC_PSM));

        targets[6] = ALTO_ADAPTER;
        payloads[6] = abi.encodeWithSignature("revokeContract(address)", USDC_PSM);

        uint256 minDelay = TimelockController(payable(TIMELOCK)).getMinDelay();
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        string memory name = "deprecate-permissionless-usdc-usm-cleanup";

        bytes memory scheduleData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, minDelay));
        bytes memory executeData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json"),
            _buildSafeJson(string.concat(name, " - Schedule"), TIMELOCK, scheduleData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json"),
            _buildSafeJson(string.concat(name, " - Execute"), TIMELOCK, executeData)
        );
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
}
