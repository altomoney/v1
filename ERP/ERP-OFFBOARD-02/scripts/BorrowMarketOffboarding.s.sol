// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingParams,
    BorrowMarketOffboardingPhase
} from "../IBorrowMarketOffboarding.sol";

uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765364975;
BorrowMarketOffboardingPhase constant PHASE_TO_RUN = BorrowMarketOffboardingPhase.BATCH_C_RECOVER;

string constant MAINNET_DEPLOYMENT_OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

address constant FREEZER_SAFE = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;
address constant TIMELOCK_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;

/// @notice Loads the minimal mainnet input and prepares one ERP-OFFBOARD-02 phase.
/// @dev Run the factory deployment phase first, then change `PHASE_TO_RUN` for the approved activation.
contract BorrowMarketOffboardingScript is Script {
    function run() external {
        _runPhase(PHASE_TO_RUN);
    }

    function _runPhase(BorrowMarketOffboardingPhase phase) internal {
        BorrowMarketOffboardingInput memory input = _loadCurrentChainInput();
        _runPhase(phase, input);
    }

    function _runPhase(BorrowMarketOffboardingPhase phase, BorrowMarketOffboardingInput memory input)
        internal
        returns (BorrowMarketOffboardingInput memory)
    {
        BorrowMarketOffboardingParams memory params =
            BorrowMarketOffboardingParams({phase: phase, freezerSafe: FREEZER_SAFE, timelockSafe: TIMELOCK_SAFE});

        vm.startBroadcast();
        input = BorrowMarketOffboarding.runPhase(params, input);
        vm.stopBroadcast();

        return input;
    }

    function _loadCurrentChainInput() internal view returns (BorrowMarketOffboardingInput memory input) {
        string memory json = vm.readFile(string.concat(_deploymentFolder(), "/addresses.json"));

        input.contracts.timelock = vm.parseJsonAddress(json, ".contracts.timelock");
        input.contracts.ownerFixedRateIrmFactory = _tryParseAddress(json, ".contracts.ownerFixedRateIrmFactory");
        input.contracts.marketRegistry = vm.parseJsonAddress(json, ".contracts.marketRegistry");
        input.contracts.altoAdapter = vm.parseJsonAddress(json, ".contracts.altoAdapter");
        input.contracts.liquidationPeriphery = vm.parseJsonAddress(json, ".contracts.liquidationPeriphery");
        input.contracts.dusdVault = vm.parseJsonAddress(json, ".contracts.dusdVault");
        input.contracts.wbtcBorrowMarket = vm.parseJsonAddress(json, ".contracts.wbtcBorrowMarket");
        input.contracts.cbbtcBorrowMarket = vm.parseJsonAddress(json, ".contracts.cbbtcBorrowMarket");
        input.contracts.susdeBorrowMarket = vm.parseJsonAddress(json, ".contracts.susdeBorrowMarket");
        input.contracts.syrupUsdcBorrowMarket = vm.parseJsonAddress(json, ".contracts.syrupUsdcBorrowMarket");
        input.contracts.paxgBorrowMarket = vm.parseJsonAddress(json, ".contracts.paxgBorrowMarket");
        input.contracts.wbtcBorrowLeverage = vm.parseJsonAddress(json, ".contracts.wbtcBorrowLeverage");
        input.contracts.cbbtcBorrowLeverage = vm.parseJsonAddress(json, ".contracts.cbbtcBorrowLeverage");
        input.contracts.susdeBorrowLeverage = vm.parseJsonAddress(json, ".contracts.susdeBorrowLeverage");
        input.contracts.syrupUsdcBorrowLeverage = vm.parseJsonAddress(json, ".contracts.syrupUsdcBorrowLeverage");
        input.contracts.paxgBorrowLeverage = vm.parseJsonAddress(json, ".contracts.paxgBorrowLeverage");
    }

    function _tryParseAddress(string memory json, string memory path) internal pure returns (address) {
        try vm.parseJsonAddress(json, path) returns (address parsed) {
            return parsed;
        } catch {
            return address(0);
        }
    }

    function _deploymentFolder() internal view returns (string memory) {
        return string.concat(
            MAINNET_DEPLOYMENT_OUTPUT_DIR,
            "/ethereum-mainnet-",
            vm.toString(block.chainid),
            "-",
            vm.toString(DEPLOYMENT_ID_TO_LOAD)
        );
    }
}
