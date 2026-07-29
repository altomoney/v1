// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {ODOS_ROUTER_V3_MAINNET} from "deployments/ethereum-mainnet/Constants.sol";

/// @title Generate Swap Target Timelock Transaction Data
/// @dev Run with: forge script script/GenerateKyberSwapTimelockTransactions.s.sol --rpc-url $ETH_RPC_URL
/// @notice Writes Safe Transaction Builder JSON files to allow-list KyberSwap and remove ODOS from all mainnet
/// leverage swappers.
contract GenerateKyberSwapTimelockTransactionsScript is Script {
    address internal constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address internal constant KYBERSWAP_META_AGGREGATION_ROUTER_V2 = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

    string internal constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";
    string internal constant BATCH_NAME = "kyberswap-add-odos-remove-leverage-swappers";

    function run() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildBatch();
        uint256 timelockDelay = TimelockController(payable(TIMELOCK)).getMinDelay();

        _writeSafeTimelockBatchJson(BATCH_NAME, TIMELOCK, targets, values, payloads, timelockDelay);

        console.log("KyberSwap target:", KYBERSWAP_META_AGGREGATION_ROUTER_V2);
        console.log("ODOS target removed:", ODOS_ROUTER_V3_MAINNET);
        console.log("Swappers updated:", targets.length / 2);
        console.log("Timelock:", TIMELOCK);
        console.log("Timelock delay:", timelockDelay);
    }

    function _buildBatch()
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        address[] memory swappers = _swappers();
        uint256 operationCount = swappers.length * 2;
        targets = new address[](operationCount);
        values = new uint256[](operationCount);
        payloads = new bytes[](operationCount);

        for (uint256 i = 0; i < swappers.length; i++) {
            uint256 kyberOperation = i * 2;
            uint256 odosOperation = kyberOperation + 1;

            targets[kyberOperation] = swappers[i];
            payloads[kyberOperation] = abi.encodeCall(
                IAltoLeverageSwapperMultiTarget.setValidSwapTarget, (KYBERSWAP_META_AGGREGATION_ROUTER_V2, true)
            );

            targets[odosOperation] = swappers[i];
            payloads[odosOperation] =
                abi.encodeCall(IAltoLeverageSwapperMultiTarget.setValidSwapTarget, (ODOS_ROUTER_V3_MAINNET, false));
        }
    }

    function _swappers() internal pure returns (address[] memory swappers) {
        swappers = new address[](12);
        swappers[0] = 0xe55282760E475B14773818Cea77b408ceE8933f2; // wBTC Borrow (active)
        swappers[1] = 0x3F53a997BDA0aBb348068869b514D0F1D5056216; // cbBTC Borrow (active)
        swappers[2] = 0xA3F15A334A1399a5e2aCc1d9Ca2a046062fdE559; // sUSDe Borrow (active)
        swappers[3] = 0x7cF8D583a453fCe304973db8f800538a91aEfCFa; // syrupUSDC Borrow (active)
        swappers[4] = 0xe4fE4bD13Da7EA32d4E9e2D89F007588cD8003CD; // PAXG Borrow (active)
        swappers[5] = 0xe2C2A2E165A2d07deE34F5996ff90df053d93882; // sUSDe Mint (active)
        swappers[6] = 0xDd8158f87947D8dCcF54aD697a7d931B6888BD96; // syrupUSDC Mint (active)
        swappers[7] = 0x8814f9A1f996Ee5EdE2Dc2E1229bc87b8D939c85; // WETH Mint (active)
        swappers[8] = 0x2264b8E45393404A989C43E38bce5BafdBEb4B62; // wstETH Mint (active)
        swappers[9] = 0x65C7b84204392597161daDB5749b68299Ad4eb6F; // rETH Mint (active)
        swappers[10] = 0xef82C87c65bA9096011cFd1682d1f98ff02187Fb; // mETH Mint (deprecated)
        swappers[11] = 0x1a81eC134b96a8ecC77F0e97eb709dA11151eda8; // tBTC Mint (deprecated)
    }

    function _writeSafeTimelockBatchJson(
        string memory name,
        address timelock,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 delay
    ) internal {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes memory scheduleBatchData =
            abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, predecessor, salt, delay));
        bytes memory executeBatchData =
            abi.encodeCall(TimelockController.executeBatch, (targets, values, payloads, predecessor, salt));

        vm.createDir(OUTPUT_DIR, true);
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-schedule.json"),
            _buildSafeJson(string.concat(name, " - Schedule"), timelock, scheduleBatchData)
        );
        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", name, "-execute.json"),
            _buildSafeJson(string.concat(name, " - Execute"), timelock, executeBatchData)
        );

        console.log("Safe TX Builder JSONs written:");
        console.log("  1. safe-tx-%s-schedule.json  (propose)", name);
        console.log("  2. safe-tx-%s-execute.json   (execute after delay)", name);
    }

    function _buildSafeJson(string memory name, address to, bytes memory data) internal view returns (string memory) {
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
