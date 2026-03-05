// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract UpgradeMarketsScript is Script {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;

    // mint market proxies
    address constant WETH_MARKET = 0x8DED9e2B8Bc5128B862dD534b97c8a32991959ff;
    address constant WSTETH_MARKET = 0xfd8c25047f4397dC5461B919999585a2a3EaC2eF;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant TBTC_MARKET = 0xE17F10f8535336143d4F2FE304f3Dcf7B23671e1;

    // borrow market proxies
    address constant WBTC_BORROW = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant CBBTC_BORROW = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;
    address constant SUSDE_BORROW = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant SYRUPUSDC_BORROW = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant PAXG_BORROW = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;

    // bad debt amounts per mint market
    // ! FILL WITH REAL VALUES
    uint128 constant WETH_BAD_DEBT = 2792786924391007704;
    uint128 constant WSTETH_BAD_DEBT = 11547222592138533;
    uint128 constant RETH_BAD_DEBT = 0;
    uint128 constant METH_BAD_DEBT = 0;
    uint128 constant TBTC_BAD_DEBT = 0;

    string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

    uint256 constant NUM_MARKETS = 10;

    function run() public {
        uint256 timelockDelay = TimelockController(payable(TIMELOCK)).getMinDelay();
        console.log("Timelock min delay:", timelockDelay);

        vm.startBroadcast();

        // do not forget to pass these addresses to the current deployment output
        address newMintImpl = address(new AltoMintMarket());
        address newBorrowImpl = address(new AltoBorrowMarket());

        console.log("New AltoMintMarket implementation:", newMintImpl);
        console.log("New AltoBorrowMarket implementation:", newBorrowImpl);

        vm.stopBroadcast();

        // build the arrays for scheduleBatch / executeBatch
        address[] memory targets = new address[](NUM_MARKETS);
        uint256[] memory values = new uint256[](NUM_MARKETS);
        bytes[] memory payloads = new bytes[](NUM_MARKETS);

        // mint
        targets[0] = WETH_MARKET;
        targets[1] = WSTETH_MARKET;
        targets[2] = RETH_MARKET;
        targets[3] = METH_MARKET;
        targets[4] = TBTC_MARKET;

        payloads[0] = _mintUpgradeData(newMintImpl, WETH_BAD_DEBT);
        payloads[1] = _mintUpgradeData(newMintImpl, WSTETH_BAD_DEBT);
        payloads[2] = _mintUpgradeData(newMintImpl, RETH_BAD_DEBT);
        payloads[3] = _mintUpgradeData(newMintImpl, METH_BAD_DEBT);
        payloads[4] = _mintUpgradeData(newMintImpl, TBTC_BAD_DEBT);

        // borrow
        targets[5] = WBTC_BORROW;
        targets[6] = CBBTC_BORROW;
        targets[7] = SUSDE_BORROW;
        targets[8] = SYRUPUSDC_BORROW;
        targets[9] = PAXG_BORROW;

        bytes memory borrowData = _borrowUpgradeData(newBorrowImpl);
        for (uint256 i = 5; i < NUM_MARKETS; i++) {
            payloads[i] = borrowData;
        }

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(abi.encode(block.timestamp, block.chainid, newMintImpl, newBorrowImpl));

        bytes memory scheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, timelockDelay)
        );
        bytes memory executeCalldata =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        string memory folder = string.concat(OUTPUT_DIR, "/upgrade-markets-", vm.toString(block.timestamp));
        vm.createDir(folder, true);

        _writeSafeJson(
            string.concat(folder, "/safe-schedule-batch.json"),
            "Schedule: Upgrade All Markets",
            TIMELOCK,
            scheduleCalldata
        );
        _writeSafeJson(
            string.concat(folder, "/safe-execute-batch.json"), "Execute: Upgrade All Markets", TIMELOCK, executeCalldata
        );

        console.log("Safe TX Builder JSONs written to:", folder);
    }

    function _mintUpgradeData(address impl, uint128 badDebt) internal pure returns (bytes memory) {
        return abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall, (impl, abi.encodeCall(AltoMintMarket.initializeV2, (badDebt)))
        );
    }

    function _borrowUpgradeData(address impl) internal pure returns (bytes memory) {
        return abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (impl, ""));
    }

    function _writeSafeJson(string memory filePath, string memory name, address to, bytes memory data) internal {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","createdAt":',
            vm.toString(block.timestamp),
            ',"meta":{"name":"',
            name,
            '","description":"","txBuilderVersion":"1.17.1","createdFromSafeAddress":"',
            Strings.toHexString(SAFE),
            '","createdFromOwnerAddress":"","checksum":""},"transactions":[{"to":"',
            Strings.toHexString(to),
            '","value":"0","data":"',
            vm.toString(data),
            '","contractMethod":null,"contractInputsValues":null}]}'
        );

        vm.writeFile(filePath, json);
        console.log("  Written:", filePath);
    }
}
