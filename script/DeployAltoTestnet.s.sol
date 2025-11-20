// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

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
            skipLendingDeployment: false,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            wrappedNativeToken: address(1),
            uniswapV3NonFungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52
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
        {
            tokensJson = vm.serializeAddress("tokens", "alto", input.tokens.alto);
            tokensJson = vm.serializeAddress("tokens", "dusd", input.tokens.dusd);
            tokensJson = vm.serializeAddress("tokens", "usdc", input.tokens.usdc);
            tokensJson = vm.serializeAddress("tokens", "weth", input.tokens.weth);
            tokensJson = vm.serializeAddress("tokens", "wsteth", input.tokens.wsteth);
            tokensJson = vm.serializeAddress("tokens", "reth", input.tokens.reth);
            tokensJson = vm.serializeAddress("tokens", "meth", input.tokens.meth);
            tokensJson = vm.serializeAddress("tokens", "tbtc", input.tokens.tbtc);
            tokensJson = vm.serializeAddress("tokens", "wbtc", input.tokens.wbtc);
            tokensJson = vm.serializeAddress("tokens", "cbbtc", input.tokens.cbbtc);
            tokensJson = vm.serializeAddress("tokens", "susde", input.tokens.susde);
        }

        // Build weth market batch JSON
        string memory wethMarketJson = "";
        {
            wethMarketJson = vm.serializeAddress("wethMarket", "market", input.contracts.wethMarketBatch.market);
            wethMarketJson = vm.serializeAddress(
                "wethMarket", "marketImplementation", input.contracts.wethMarketBatch.marketImplementation
            );
            wethMarketJson = vm.serializeAddress("wethMarket", "marketIrm", input.contracts.wethMarketBatch.marketIrm);
            wethMarketJson =
                vm.serializeAddress("wethMarket", "marketOracle", input.contracts.wethMarketBatch.marketOracle);
        }

        // Build wsteth market batch JSON
        string memory wstethMarketJson = "";
        {

            wstethMarketJson = vm.serializeAddress("wstethMarket", "market", input.contracts.wstethMarketBatch.market);
            wstethMarketJson = vm.serializeAddress(
                "wstethMarket", "marketImplementation", input.contracts.wstethMarketBatch.marketImplementation
            );
            wstethMarketJson =
                vm.serializeAddress("wstethMarket", "marketIrm", input.contracts.wstethMarketBatch.marketIrm);
            wstethMarketJson =
                vm.serializeAddress("wstethMarket", "marketOracle", input.contracts.wstethMarketBatch.marketOracle);
        }

        // Build reth market batch JSON
        string memory rethMarketJson = "";
        {

            rethMarketJson = vm.serializeAddress("rethMarket", "market", input.contracts.rethMarketBatch.market);
            rethMarketJson = vm.serializeAddress(
                "rethMarket", "marketImplementation", input.contracts.rethMarketBatch.marketImplementation
            );
            rethMarketJson = vm.serializeAddress("rethMarket", "marketIrm", input.contracts.rethMarketBatch.marketIrm);
            rethMarketJson =
                vm.serializeAddress("rethMarket", "marketOracle", input.contracts.rethMarketBatch.marketOracle);
        }

        // Build meth market batch JSON
        string memory methMarketJson = "";
        {

            methMarketJson = vm.serializeAddress("methMarket", "market", input.contracts.methMarketBatch.market);
            methMarketJson = vm.serializeAddress(
                "methMarket", "marketImplementation", input.contracts.methMarketBatch.marketImplementation
            );
            methMarketJson = vm.serializeAddress("methMarket", "marketIrm", input.contracts.methMarketBatch.marketIrm);
            methMarketJson =
                vm.serializeAddress("methMarket", "marketOracle", input.contracts.methMarketBatch.marketOracle);
        }

        // Build tbtc market batch JSON
        string memory tbtcMarketJson = "";
        {

            tbtcMarketJson = vm.serializeAddress("tbtcMarket", "market", input.contracts.tbtcMarketBatch.market);
            tbtcMarketJson = vm.serializeAddress(
                "tbtcMarket", "marketImplementation", input.contracts.tbtcMarketBatch.marketImplementation
            );
            tbtcMarketJson = vm.serializeAddress("tbtcMarket", "marketIrm", input.contracts.tbtcMarketBatch.marketIrm);
            tbtcMarketJson =
                vm.serializeAddress("tbtcMarket", "marketOracle", input.contracts.tbtcMarketBatch.marketOracle);
        }

        // Build wbtc market batch JSON
        string memory wbtcMarketJson = "";
        {

            wbtcMarketJson = vm.serializeAddress("wbtcMarket", "market", input.contracts.wbtcMarketBatch.market);
            wbtcMarketJson = vm.serializeAddress(
                "wbtcMarket", "marketImplementation", input.contracts.wbtcMarketBatch.marketImplementation
            );
            wbtcMarketJson = vm.serializeAddress("wbtcMarket", "marketIrm", input.contracts.wbtcMarketBatch.marketIrm);
            wbtcMarketJson =
                vm.serializeAddress("wbtcMarket", "marketOracle", input.contracts.wbtcMarketBatch.marketOracle);
        }

        // Build cbbtc market batch JSON
        string memory cbbtcMarketJson = "";
        {

            cbbtcMarketJson = vm.serializeAddress("cbbtcMarket", "market", input.contracts.cbbtcMarketBatch.market);
            cbbtcMarketJson = vm.serializeAddress(
                "cbbtcMarket", "marketImplementation", input.contracts.cbbtcMarketBatch.marketImplementation
            );
            cbbtcMarketJson =
                vm.serializeAddress("cbbtcMarket", "marketIrm", input.contracts.cbbtcMarketBatch.marketIrm);
            cbbtcMarketJson =
                vm.serializeAddress("cbbtcMarket", "marketOracle", input.contracts.cbbtcMarketBatch.marketOracle);
        }
        // Build susde market batch JSON
        string memory susdeMarketJson = "";
        {

            susdeMarketJson = vm.serializeAddress("susdeMarket", "market", input.contracts.susdeMarketBatch.market);
            susdeMarketJson = vm.serializeAddress(
                "susdeMarket", "marketImplementation", input.contracts.susdeMarketBatch.marketImplementation
            );
            susdeMarketJson =
                vm.serializeAddress("susdeMarket", "marketIrm", input.contracts.susdeMarketBatch.marketIrm);
            susdeMarketJson =
                vm.serializeAddress("susdeMarket", "marketOracle", input.contracts.susdeMarketBatch.marketOracle);
        }
        // Build staking batch JSON
        string memory stakingBatchJson = "";
        {
            stakingBatchJson =
                vm.serializeAddress("stakingBatch", "stakingContract", input.contracts.stakingBatch.stakingContract);
            stakingBatchJson = vm.serializeAddress(
                "stakingBatch", "universalRewardsDistributor", input.contracts.stakingBatch.universalRewardsDistributor
            );
        }

        // Build rewards batch JSON
        string memory rewardsBatchJson = "";
        {

            rewardsBatchJson = vm.serializeAddress(
                "rewardsBatch", "rewardsDistributor", input.contracts.rewardsBatch.rewardsDistributor
            );
            rewardsBatchJson =
                vm.serializeAddress("rewardsBatch", "paymentOracles", input.contracts.rewardsBatch.paymentOracles);
            rewardsBatchJson =
                vm.serializeAddress("rewardsBatch", "rewardOracle", input.contracts.rewardsBatch.rewardOracle);
        }

        // Build contracts JSON
        string memory contractsJson = "";
        {
            contractsJson = vm.serializeAddress("contracts", "altoMulticall", input.contracts.altoMulticall);
            contractsJson = vm.serializeAddress("contracts", "multiTokenSender", input.contracts.multiTokenSender);
            contractsJson = vm.serializeAddress("contracts", "mockSwapper", input.contracts.mockSwapper);
            contractsJson = vm.serializeAddress("contracts", "altoLeverage", input.contracts.altoLeverage);
            contractsJson = vm.serializeAddress("contracts", "bundler3", input.contracts.bundler3);
            contractsJson = vm.serializeAddress("contracts", "altoAdapter", input.contracts.altoAdapter);
            contractsJson = vm.serializeString("contracts", "wethMarketBatch", wbtcMarketJson);
            contractsJson = vm.serializeString("contracts", "wstethMarketBatch", wstethMarketJson);
            contractsJson = vm.serializeString("contracts", "rethMarketBatch", rethMarketJson);
            contractsJson = vm.serializeString("contracts", "methMarketBatch", methMarketJson);
            contractsJson = vm.serializeString("contracts", "tbtcMarketBatch", tbtcMarketJson);
            contractsJson = vm.serializeString("contracts", "wbtcMarketBatch", wbtcMarketJson);
            contractsJson = vm.serializeString("contracts", "cbbtcMarketBatch", cbbtcMarketJson);
            contractsJson = vm.serializeString("contracts", "susdeMarketBatch", susdeMarketJson);
            contractsJson = vm.serializeString("contracts", "stakingBatch", stakingBatchJson);
            contractsJson = vm.serializeString("contracts", "rewardsBatch", rewardsBatchJson);
        }

        // Build final JSON
        json = vm.serializeString("", "tokens", tokensJson);
        json = vm.serializeString("", "contracts", contractsJson);
        {
            // copying the JSON to avoid stack too deep error
            string memory jsonDup = json;
            // Create deployment folder and write addresses.json
            string memory deploymentFolder =
                string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(block.timestamp));
            string memory fileName = string.concat(deploymentFolder, "/addresses.json");

            // Create the directory structure first
            vm.createDir(deploymentFolder, true);
            // Then write the file
            vm.writeJson(jsonDup, fileName);
            console.log("Deployment data saved to:", fileName);
        }
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);

        AltoTestnetInput memory loadedInput;

        // Load tokens
        loadedInput.tokens.alto = vm.parseJsonAddress(json, ".tokens.alto");
        loadedInput.tokens.dusd = vm.parseJsonAddress(json, ".tokens.dusd");
        loadedInput.tokens.usdc = vm.parseJsonAddress(json, ".tokens.usdc");
        loadedInput.tokens.weth = vm.parseJsonAddress(json, ".tokens.weth");
        loadedInput.tokens.wsteth = vm.parseJsonAddress(json, ".tokens.wsteth");
        loadedInput.tokens.reth = vm.parseJsonAddress(json, ".tokens.reth");
        loadedInput.tokens.meth = vm.parseJsonAddress(json, ".tokens.meth");
        loadedInput.tokens.tbtc = vm.parseJsonAddress(json, ".tokens.tbtc");
        loadedInput.tokens.wbtc = vm.parseJsonAddress(json, ".tokens.wbtc");
        loadedInput.tokens.cbbtc = vm.parseJsonAddress(json, ".tokens.cbbtc");
        loadedInput.tokens.susde = vm.parseJsonAddress(json, ".tokens.susde");

        // Load contracts
        loadedInput.contracts.altoMulticall = vm.parseJsonAddress(json, ".contracts.altoMulticall");
        loadedInput.contracts.multiTokenSender = vm.parseJsonAddress(json, ".contracts.multiTokenSender");
        loadedInput.contracts.mockSwapper = vm.parseJsonAddress(json, ".contracts.mockSwapper");
        loadedInput.contracts.altoLeverage = vm.parseJsonAddress(json, ".contracts.altoLeverage");
        loadedInput.contracts.bundler3 = vm.parseJsonAddress(json, ".contracts.bundler3");
        loadedInput.contracts.altoAdapter = vm.parseJsonAddress(json, ".contracts.altoAdapter");

        // Load weth market batch
        loadedInput.contracts.wethMarketBatch.market = vm.parseJsonAddress(json, ".contracts.wethMarketBatch.market");
        loadedInput.contracts.wethMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.wethMarketBatch.marketImplementation");
        loadedInput.contracts.wethMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.wethMarketBatch.marketIrm");
        loadedInput.contracts.wethMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.wethMarketBatch.marketOracle");

        // Load wsteth market batch
        loadedInput.contracts.wstethMarketBatch.market =
            vm.parseJsonAddress(json, ".contracts.wstethMarketBatch.market");
        loadedInput.contracts.wstethMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.wstethMarketBatch.marketImplementation");
        loadedInput.contracts.wstethMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.wstethMarketBatch.marketIrm");
        loadedInput.contracts.wstethMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.wstethMarketBatch.marketOracle");

        // Load reth market batch
        loadedInput.contracts.rethMarketBatch.market = vm.parseJsonAddress(json, ".contracts.rethMarketBatch.market");
        loadedInput.contracts.rethMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.rethMarketBatch.marketImplementation");
        loadedInput.contracts.rethMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.rethMarketBatch.marketIrm");
        loadedInput.contracts.rethMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.rethMarketBatch.marketOracle");

        // Load meth market batch
        loadedInput.contracts.methMarketBatch.market = vm.parseJsonAddress(json, ".contracts.methMarketBatch.market");
        loadedInput.contracts.methMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.methMarketBatch.marketImplementation");
        loadedInput.contracts.methMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.methMarketBatch.marketIrm");
        loadedInput.contracts.methMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.methMarketBatch.marketOracle");

        // Load tbtc market batch
        loadedInput.contracts.tbtcMarketBatch.market = vm.parseJsonAddress(json, ".contracts.tbtcMarketBatch.market");
        loadedInput.contracts.tbtcMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.tbtcMarketBatch.marketImplementation");
        loadedInput.contracts.tbtcMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.tbtcMarketBatch.marketIrm");
        loadedInput.contracts.tbtcMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.tbtcMarketBatch.marketOracle");

        // Load wbtc market batch
        loadedInput.contracts.wbtcMarketBatch.market = vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.market");
        loadedInput.contracts.wbtcMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.marketImplementation");
        loadedInput.contracts.wbtcMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.marketIrm");
        loadedInput.contracts.wbtcMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.marketOracle");

        // Load cbbtc market batch
        loadedInput.contracts.cbbtcMarketBatch.market = vm.parseJsonAddress(json, ".contracts.cbbtcMarketBatch.market");
        loadedInput.contracts.cbbtcMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.cbbtcMarketBatch.marketImplementation");
        loadedInput.contracts.cbbtcMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.cbbtcMarketBatch.marketIrm");
        loadedInput.contracts.cbbtcMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.cbbtcMarketBatch.marketOracle");

        // Load susde market batch
        loadedInput.contracts.susdeMarketBatch.market = vm.parseJsonAddress(json, ".contracts.susdeMarketBatch.market");
        loadedInput.contracts.susdeMarketBatch.marketImplementation =
            vm.parseJsonAddress(json, ".contracts.susdeMarketBatch.marketImplementation");
        loadedInput.contracts.susdeMarketBatch.marketIrm =
            vm.parseJsonAddress(json, ".contracts.susdeMarketBatch.marketIrm");
        loadedInput.contracts.susdeMarketBatch.marketOracle =
            vm.parseJsonAddress(json, ".contracts.susdeMarketBatch.marketOracle");

        // Load staking batch
        loadedInput.contracts.stakingBatch.stakingContract =
            vm.parseJsonAddress(json, ".contracts.stakingBatch.stakingContract");
        loadedInput.contracts.stakingBatch.universalRewardsDistributor =
            vm.parseJsonAddress(json, ".contracts.stakingBatch.universalRewardsDistributor");

        // Load rewards batch
        loadedInput.contracts.rewardsBatch.rewardsDistributor =
            vm.parseJsonAddress(json, ".contracts.rewardsBatch.rewardsDistributor");
        loadedInput.contracts.rewardsBatch.paymentOracles =
            vm.parseJsonAddressArray(json, ".contracts.rewardsBatch.paymentOracles");
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
        _extractContractABI("DUSD", abiFolder);
        _extractContractABI("ERC20Testnet", abiFolder);

        // Extract ABIs for main contracts
        _extractContractABI("AltoMulticallTestnet", abiFolder);
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
            string memory fileName = string.concat(outputDir, "/", contractName, ".json");

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
