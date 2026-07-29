// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {GenerateKyberSwapTimelockTransactionsScript} from "../../script/GenerateKyberSwapTimelockTransactions.s.sol";

contract GenerateKyberSwapTimelockTransactionsTest is Test {
    address internal constant MAINNET_TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address internal constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address internal constant KYBERSWAP_META_AGGREGATION_ROUTER_V2 = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-kyberswap-allowlist-leverage-swappers-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-kyberswap-allowlist-leverage-swappers-execute.json";

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
    }

    function test_run_writesSafeJsonsThatAllowlistKyberSwapOnAllMainnetSwappers() public {
        address[] memory swappers = _swappers();
        for (uint256 i; i < swappers.length; ++i) {
            assertFalse(
                IAltoLeverageSwapperMultiTarget(swappers[i]).isValidSwapTarget(KYBERSWAP_META_AGGREGATION_ROUTER_V2),
                "kyber should not already be allow-listed"
            );
        }

        new GenerateKyberSwapTimelockTransactionsScript().run();

        assertEq(vm.parseJsonAddress(vm.readFile(SCHEDULE_JSON), ".transactions[0].to"), TIMELOCK, "schedule to");
        assertEq(vm.parseJsonAddress(vm.readFile(EXECUTE_JSON), ".transactions[0].to"), TIMELOCK, "execute to");

        _assertScheduleBatchCalldata(_readSafeTxData(SCHEDULE_JSON), swappers);
        _assertExecuteBatchCalldata(_readSafeTxData(EXECUTE_JSON), swappers);
        _executeSafeTimelockBatch();

        for (uint256 i; i < swappers.length; ++i) {
            assertTrue(
                IAltoLeverageSwapperMultiTarget(swappers[i]).isValidSwapTarget(KYBERSWAP_META_AGGREGATION_ROUTER_V2),
                "kyber should be allow-listed"
            );
        }
    }

    function _executeSafeTimelockBatch() internal {
        TimelockController timelock = TimelockController(payable(TIMELOCK));
        uint256 minDelay = timelock.getMinDelay();

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool scheduled,) = address(timelock).call(_readSafeTxData(SCHEDULE_JSON));
        assertTrue(scheduled, "timelock schedule failed");

        vm.warp(block.timestamp + minDelay + 1);

        vm.prank(MAINNET_TIMELOCK_ADMIN);
        (bool executed,) = address(timelock).call(_readSafeTxData(EXECUTE_JSON));
        assertTrue(executed, "timelock execute failed");
    }

    function _assertScheduleBatchCalldata(bytes memory data, address[] memory expectedTargets) internal view {
        assertEq(bytes4(data), TimelockController.scheduleBatch.selector, "schedule selector");
        bytes memory args = _stripSelector(data);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads,
            bytes32 predecessor,
            bytes32 salt,
            uint256 delay
        ) = abi.decode(args, (address[], uint256[], bytes[], bytes32, bytes32, uint256));

        assertEq(delay, TimelockController(payable(TIMELOCK)).getMinDelay(), "delay");
        _assertBatchArgs(targets, values, payloads, predecessor, salt, expectedTargets);
    }

    function _assertExecuteBatchCalldata(bytes memory data, address[] memory expectedTargets) internal pure {
        assertEq(bytes4(data), TimelockController.executeBatch.selector, "execute selector");
        bytes memory args = _stripSelector(data);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads, bytes32 predecessor, bytes32 salt)
        = abi.decode(args, (address[], uint256[], bytes[], bytes32, bytes32));

        _assertBatchArgs(targets, values, payloads, predecessor, salt, expectedTargets);
    }

    function _assertBatchArgs(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt,
        address[] memory expectedTargets
    ) internal pure {
        assertEq(targets.length, 12, "target length");
        assertEq(values.length, 12, "value length");
        assertEq(payloads.length, 12, "payload length");
        assertEq(predecessor, bytes32(0), "predecessor");
        assertEq(salt, bytes32(0), "salt");

        bytes memory expectedPayload = abi.encodeCall(
            IAltoLeverageSwapperMultiTarget.setValidSwapTarget, (KYBERSWAP_META_AGGREGATION_ROUTER_V2, true)
        );

        for (uint256 i; i < expectedTargets.length; ++i) {
            assertEq(targets[i], expectedTargets[i], "target");
            assertEq(values[i], 0, "value");
            assertEq(payloads[i], expectedPayload, "payload");
        }
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory args) {
        args = new bytes(data.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = data[i + 4];
        }
    }

    function _readSafeTxData(string memory path) internal view returns (bytes memory) {
        string memory json = vm.readFile(path);
        return vm.parseJsonBytes(json, ".transactions[0].data");
    }

    function _swappers() internal pure returns (address[] memory swappers) {
        swappers = new address[](12);
        swappers[0] = 0xe55282760E475B14773818Cea77b408ceE8933f2;
        swappers[1] = 0x3F53a997BDA0aBb348068869b514D0F1D5056216;
        swappers[2] = 0xA3F15A334A1399a5e2aCc1d9Ca2a046062fdE559;
        swappers[3] = 0x7cF8D583a453fCe304973db8f800538a91aEfCFa;
        swappers[4] = 0xe4fE4bD13Da7EA32d4E9e2D89F007588cD8003CD;
        swappers[5] = 0xe2C2A2E165A2d07deE34F5996ff90df053d93882;
        swappers[6] = 0xDd8158f87947D8dCcF54aD697a7d931B6888BD96;
        swappers[7] = 0x8814f9A1f996Ee5EdE2Dc2E1229bc87b8D939c85;
        swappers[8] = 0x2264b8E45393404A989C43E38bce5BafdBEb4B62;
        swappers[9] = 0x65C7b84204392597161daDB5749b68299Ad4eb6F;
        swappers[10] = 0xef82C87c65bA9096011cFd1682d1f98ff02187Fb;
        swappers[11] = 0x1a81eC134b96a8ecC77F0e97eb709dA11151eda8;
    }
}
