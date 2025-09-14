// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    TestnetRewardsBatch,
    TestnetRewardsBatchReport,
    TestnetRewardsBatchParams
} from "@alto/deployments/testnet/TestnetRewardsBatch.sol";
import {
    TestnetStakingBatch,
    TestnetStakingBatchParams,
    TestnetStakingBatchReport
} from "@alto/deployments/testnet/TestnetStakingBatch.sol";
import {DeployAltoTestnet, AltoTestnetParams, AltoTestnetInput} from "@alto/deployments/testnet/DeployAltoTestnet.sol";
import {console} from "forge-std/console.sol";

uint256 constant DEPLOYMENT_ID_TO_LOAD = 0;
string constant OUTPUT_DIR = "./contracts/deployments/testnet/output";

contract DeployAltoTestnetScript is Script {
    AltoTestnetParams params;
    AltoTestnetInput input;

    function run() public {
        _loadCurrentChainInput();

        vm.startBroadcast();

        params = AltoTestnetParams({
            owner: msg.sender,
            altoMulticall: 0xb471301c353B759226A835653aCec5cD968Fd62B,
            skipLendingDeployment: false,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            wrappedNativeToken: address(1),
            universalRewardsDistributor: 0x018784fE6D9dbf14ba224797f934fcfb71c3bADd
        });

        input = DeployAltoTestnet.deploy(params, input);

        vm.stopBroadcast();

        // Store input to JSON format
        _writeInputToJson();

        // Extract ABIs for all deployed contracts
        _extractABIs();

        console.log("Deployment completed successfully");
    }

    function _writeInputToJson() internal {
        string memory json = "";

        // Build tokens JSON
        string memory tokensJson = "";
        tokensJson = vm.serializeAddress("tokens", "alto", input.tokens.alto);
        tokensJson = vm.serializeAddress("tokens", "usdo", input.tokens.usdo);
        tokensJson = vm.serializeAddress("tokens", "usdc", input.tokens.usdc);
        tokensJson = vm.serializeAddress("tokens", "weth", input.tokens.weth);

        // Build borrow market batch JSON
        string memory borrowMarketJson = "";
        borrowMarketJson = vm.serializeAddress("borrowMarket", "market", input.contracts.borrowMarketBatch.market);
        borrowMarketJson = vm.serializeAddress(
            "borrowMarket", "marketImplementation", input.contracts.borrowMarketBatch.marketImplementation
        );
        borrowMarketJson = vm.serializeAddress("borrowMarket", "marketIrm", input.contracts.borrowMarketBatch.marketIrm);
        borrowMarketJson =
            vm.serializeAddress("borrowMarket", "marketOracle", input.contracts.borrowMarketBatch.marketOracle);

        // Build mint market batch JSON
        string memory mintMarketJson = "";
        mintMarketJson = vm.serializeAddress("mintMarket", "market", input.contracts.mintMarketBatch.market);
        mintMarketJson = vm.serializeAddress(
            "mintMarket", "marketImplementation", input.contracts.mintMarketBatch.marketImplementation
        );
        mintMarketJson = vm.serializeAddress("mintMarket", "marketIrm", input.contracts.mintMarketBatch.marketIrm);
        mintMarketJson = vm.serializeAddress("mintMarket", "marketOracle", input.contracts.mintMarketBatch.marketOracle);

        // Build staking batch JSON
        string memory stakingBatchJson = "";
        stakingBatchJson =
            vm.serializeAddress("stakingBatch", "stakingContract", input.contracts.stakingBatch.stakingContract);
        stakingBatchJson = vm.serializeAddress(
            "stakingBatch", "universalRewardsDistributor", input.contracts.stakingBatch.universalRewardsDistributor
        );

        // Build rewards batch JSON
        string memory rewardsBatchJson = "";
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "rewardsDistributor", input.contracts.rewardsBatch.rewardsDistributor);
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "paymentOracle", input.contracts.rewardsBatch.paymentOracle);
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "rewardOracle", input.contracts.rewardsBatch.rewardOracle);

        // Build contracts JSON
        string memory contractsJson = "";
        contractsJson = vm.serializeAddress("contracts", "multiTokenSender", input.contracts.multiTokenSender);
        contractsJson = vm.serializeAddress("contracts", "mockSwapper", input.contracts.mockSwapper);
        contractsJson = vm.serializeAddress("contracts", "altoLeverage", input.contracts.altoLeverage);
        contractsJson = vm.serializeAddress("contracts", "bundler3", input.contracts.bundler3);
        contractsJson = vm.serializeAddress("contracts", "altoAdapter", input.contracts.altoAdapter);
        contractsJson = vm.serializeString("contracts", "borrowMarketBatch", borrowMarketJson);
        contractsJson = vm.serializeString("contracts", "mintMarketBatch", mintMarketJson);
        contractsJson = vm.serializeString("contracts", "stakingBatch", stakingBatchJson);
        contractsJson = vm.serializeString("contracts", "rewardsBatch", rewardsBatchJson);

        // Build final JSON
        json = vm.serializeString("", "tokens", tokensJson);
        json = vm.serializeString("", "contracts", contractsJson);

        // Create deployment folder and write addresses.json
        string memory deploymentFolder =
            string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");

        // Create the directory structure first
        vm.createDir(deploymentFolder, true);
        // Then write the file
        vm.writeJson(json, fileName);

        console.log("Deployment data saved to:", fileName);
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);

        AltoTestnetInput memory loadedInput;

        // Load tokens
        loadedInput.tokens.alto = vm.parseJsonAddress(json, ".tokens.alto");
        loadedInput.tokens.usdo = vm.parseJsonAddress(json, ".tokens.usdo");
        loadedInput.tokens.usdc = vm.parseJsonAddress(json, ".tokens.usdc");
        loadedInput.tokens.weth = vm.parseJsonAddress(json, ".tokens.weth");

        // Load contracts
        loadedInput.contracts.multiTokenSender = vm.parseJsonAddress(json, ".contracts.multiTokenSender");
        loadedInput.contracts.mockSwapper = vm.parseJsonAddress(json, ".contracts.mockSwapper");
        loadedInput.contracts.altoLeverage = vm.parseJsonAddress(json, ".contracts.altoLeverage");
        loadedInput.contracts.bundler3 = vm.parseJsonAddress(json, ".contracts.bundler3");
        loadedInput.contracts.altoAdapter = vm.parseJsonAddress(json, ".contracts.altoAdapter");

        // Load borrow market batch
        loadedInput.contracts.borrowMarketBatch.market =
            vm.parseJsonAddress(json, ".contracts.borrowMarketBatch.market");
        loadedInput.contracts.borrowMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.borrowMarketBatch.marketImplementation");
        loadedInput.contracts.borrowMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.borrowMarketBatch.marketIrm");
        loadedInput.contracts.borrowMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.borrowMarketBatch.marketOracle");

        // Load mint market batch
        loadedInput.contracts.mintMarketBatch.market = vm.parseJsonAddress(json, ".contracts.mintMarketBatch.market");
        loadedInput.contracts.mintMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.mintMarketBatch.marketImplementation");
        loadedInput.contracts.mintMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.mintMarketBatch.marketIrm");
        loadedInput.contracts.mintMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.mintMarketBatch.marketOracle");

        // Load staking batch
        loadedInput.contracts.stakingBatch.stakingContract =
            vm.parseJsonAddress(json, ".contracts.stakingBatch.stakingContract");
        loadedInput.contracts.stakingBatch.universalRewardsDistributor =
            vm.parseJsonAddress(json, ".contracts.stakingBatch.universalRewardsDistributor");

        // Load rewards batch
        loadedInput.contracts.rewardsBatch.rewardsDistributor =
            vm.parseJsonAddress(json, ".contracts.rewardsBatch.rewardsDistributor");
        loadedInput.contracts.rewardsBatch.paymentOracle =
            vm.parseJsonAddress(json, ".contracts.rewardsBatch.paymentOracle");
        loadedInput.contracts.rewardsBatch.rewardOracle =
            vm.parseJsonAddress(json, ".contracts.rewardsBatch.rewardOracle");

        input = loadedInput;
    }

    function _loadCurrentChainInput() internal {
        if (DEPLOYMENT_ID_TO_LOAD == 0) {
            return;
        }
        string memory deploymentFolder =
            string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(DEPLOYMENT_ID_TO_LOAD));
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");
        _loadInputFromJson(fileName);
    }

    function _extractABIs() internal {
        string memory deploymentFolder =
            string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));
        string memory abiFolder = string.concat(deploymentFolder, "/abi");

        // Create the abi directory
        vm.createDir(abiFolder, true);

        // Extract ABIs for tokens
        _extractContractABI("AltoToken", abiFolder);
        _extractContractABI("USDO", abiFolder);
        _extractContractABI("ERC20Testnet", abiFolder);

        // Extract ABIs for main contracts
        _extractContractABI("MultiTokenSender", abiFolder);
        _extractContractABI("SwapperSimpleMock", abiFolder);
        _extractContractABI("AltoLeverage", abiFolder);
        _extractContractABI("Bundler3", abiFolder);
        _extractContractABI("AltoAdapter", abiFolder);

        // Extract ABIs for market contracts
        _extractContractABI("AltoBorrowMarket", abiFolder);
        _extractContractABI("AltoMintMarket", abiFolder);
        _extractContractABI("AdaptiveCurveIrm", abiFolder);
        _extractContractABI("FixedRateIrm", abiFolder);
        _extractContractABI("OracleTestnet", abiFolder);

        // Extract ABIs for staking contracts
        _extractContractABI("AltoStaking", abiFolder);
        _extractContractABI("UniversalRewardsDistributor", abiFolder);

        // Extract ABIs for rewards contracts
        _extractContractABI("AltoRewardsDistributor", abiFolder);

        console.log("ABIs extracted to:", abiFolder);
    }

    function _extractContractABI(string memory contractName, string memory outputDir) internal {
        try vm.getCode(contractName) returns (bytes memory) {
            string memory artifactPath = string.concat("./out/", contractName, ".sol/", contractName, ".json");
            string memory fileName = string.concat(outputDir, "/", contractName, ".abi.json");

            // Use jq command to extract just the ABI field from the artifact JSON
            string[] memory inputs = new string[](3);
            inputs[0] = "jq";
            inputs[1] = ".abi";
            inputs[2] = artifactPath;

            // Execute jq command to extract ABI and get the result
            bytes memory result = vm.ffi(inputs);
            string memory abiString = string(result);

            // Write the ABI to file
            vm.writeFile(fileName, abiString);
        } catch {
            console.log("Warning: Could not extract ABI for", contractName);
        }
    }
}
