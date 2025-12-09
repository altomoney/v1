// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

import {
    DeployAltoEthereumMainnet,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnetForTesting.sol";
import {console} from "forge-std/console.sol";

uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765210967;
DeploymentPhase constant PHASE_TO_DEPLOY = DeploymentPhase.CORE; // CORE, DUSD, MINT_MARKET_WETH, MINT_MARKET_WSTETH, MINT_MARKET_RETH, MINT_MARKET_METH, MINT_MARKET_TBTC, BORROW_MARKET_WBTC, BORROW_MARKET_CBBTC, BORROW_MARKET_SUSDE, USDC_USM, or POST
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

contract DeployAltoEthereumMainnetScript is Script {
    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    function run() public {
        _loadCurrentChainInput();

        vm.startBroadcast();

        params = AltoEthereumMainnetParams({
            timelockAdmin: msg.sender,
            timelockDelay: 0,
            freezer: msg.sender,
            deployer: msg.sender,
            phase: PHASE_TO_DEPLOY,
            useUnsafeUpgrades: true,
            treasuryMultisig: msg.sender,
            uniswapV3NonFungiblePositionManager: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        });

        // Set feeRecipient for testing (needed when loading from previous deployment and skipping CORE)
        input.contracts.feeRecipient = msg.sender;

        // input = DeployAltoEthereumMainnet.deploy(params, input);

        // params.phase = DeploymentPhase.DUSD;
        // input = DeployAltoEthereumMainnet.deploy(params, input);

        params.phase = DeploymentPhase.MINT_MARKET_WETH;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        // params.phase = DeploymentPhase.BORROW_MARKET_WBTC;
        // input = DeployAltoEthereumMainnet.deploy(params, input);

        // params.phase = DeploymentPhase.POST;
        // input = DeployAltoEthereumMainnet.deploy(params, input);

        vm.stopBroadcast();

        // Store input to JSON format
        _writeInputToJson();

        // Extract ABIs for all deployed contracts
        _extractABIs();

        console.log("Deployment completed successfully");
    }

    function _writeInputToJson() internal {
        string memory contractsJson = "";

        // Serialize core contracts
        contractsJson = vm.serializeAddress("contracts", "altoAdapter", input.contracts.altoAdapter);
        contractsJson = vm.serializeAddress("contracts", "dusd", input.contracts.dusd);
        contractsJson = vm.serializeAddress("contracts", "dusdFlashMinter", input.contracts.dusdFlashMinter);
        contractsJson = vm.serializeAddress("contracts", "uniswapPool", input.contracts.uniswapPool);

        // Serialize market contracts using helper
        contractsJson = _serializeMarketContracts(contractsJson, "weth", input.contracts.wethMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "wbtcBorrow", input.contracts.wbtcBorrowMarket);

        // Build final JSON and write to file
        string memory json = vm.serializeString("", "contracts", contractsJson);
        string memory deploymentFolder = string.concat(
            OUTPUT_DIR, "/ethereum-mainnet-", vm.toString(block.chainid), "-", vm.toString(block.timestamp)
        );
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");

        vm.createDir(deploymentFolder, true);
        vm.writeJson(json, fileName);
        console.log("Deployment data saved to:", fileName);
    }

    function _serializeMarketContracts(string memory contractsJson, string memory prefix, MarketContracts memory market)
        internal
        returns (string memory)
    {
        if (market.market == address(0)) {
            return contractsJson;
        }

        contractsJson = vm.serializeAddress("contracts", string.concat(prefix, "Market"), market.market);
        contractsJson = vm.serializeAddress(
            "contracts", string.concat(prefix, "MarketImplementation"), market.marketImplementation
        );
        contractsJson = vm.serializeAddress("contracts", string.concat(prefix, "MarketIrm"), market.marketIrm);
        contractsJson = vm.serializeAddress("contracts", string.concat(prefix, "MarketOracle"), market.marketOracle);
        contractsJson =
            vm.serializeAddress("contracts", string.concat(prefix, "LiquidationEngine"), market.liquidationEngine);
        contractsJson =
            vm.serializeAddress("contracts", string.concat(prefix, "LeverageSwapper"), market.leverageSwapper);
        contractsJson = vm.serializeAddress("contracts", string.concat(prefix, "Leverage"), market.leverage);

        return contractsJson;
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);
        AltoEthereumMainnetInput memory loadedInput;

        // Load core contracts
        loadedInput.contracts.altoAdapter = _tryParseAddress(json, ".contracts.altoAdapter");
        loadedInput.contracts.dusd = _tryParseAddress(json, ".contracts.dusd");
        loadedInput.contracts.dusdFlashMinter = _tryParseAddress(json, ".contracts.dusdFlashMinter");
        loadedInput.contracts.uniswapPool = _tryParseAddress(json, ".contracts.uniswapPool");

        // Load market contracts using helper
        loadedInput.contracts.wethMarket = _loadMarketContracts(json, "weth");
        loadedInput.contracts.wbtcBorrowMarket = _loadMarketContracts(json, "wbtcBorrow");

        input = loadedInput;
    }

    function _tryParseAddress(string memory json, string memory path) internal returns (address) {
        try vm.parseJsonAddress(json, path) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    function _loadMarketContracts(string memory json, string memory prefix) internal returns (MarketContracts memory) {
        MarketContracts memory market;
        market.market = _tryParseAddress(json, string.concat(".contracts.", prefix, "Market"));
        market.marketImplementation =
            _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketImplementation"));
        market.marketIrm = _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketIrm"));
        market.marketOracle = _tryParseAddress(json, string.concat(".contracts.", prefix, "MarketOracle"));
        market.liquidationEngine = _tryParseAddress(json, string.concat(".contracts.", prefix, "LiquidationEngine"));
        market.leverageSwapper = _tryParseAddress(json, string.concat(".contracts.", prefix, "LeverageSwapper"));
        market.leverage = _tryParseAddress(json, string.concat(".contracts.", prefix, "Leverage"));
        return market;
    }

    function _loadCurrentChainInput() internal {
        if (DEPLOYMENT_ID_TO_LOAD == 0) {
            return;
        }
        string memory deploymentFolder = string.concat(
            OUTPUT_DIR, "/ethereum-mainnet-", vm.toString(block.chainid), "-", vm.toString(DEPLOYMENT_ID_TO_LOAD)
        );
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");
        _loadInputFromJson(fileName);
    }

    function _extractABIs() internal {
        string memory deploymentFolder = string.concat(
            OUTPUT_DIR, "/ethereum-mainnet-", vm.toString(block.chainid), "-", vm.toString(block.timestamp)
        );
        string memory abiFolder = string.concat(deploymentFolder, "/abi");

        vm.createDir(abiFolder, true);

        // Extract ABIs based on phase
        if (PHASE_TO_DEPLOY == DeploymentPhase.CORE) {
            _extractContractABI("AltoAdapter", abiFolder);
            _extractContractABI("MockFeeCollector", abiFolder);
            _extractContractABI("AltoTimelockController", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.DUSD) {
            _extractContractABI("DUSD", abiFolder);
            _extractContractABI("DUSDFlashMinter", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_WETH) {
            _extractMintMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_WBTC) {
            _extractBorrowMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.POST) {
            _extractContractABI("AltoTimelockController", abiFolder);
        }

        console.log("ABIs extracted to:", abiFolder);
    }

    function _extractMintMarketABIs(string memory abiFolder, string memory oracleName) internal {
        _extractContractABI("AltoMintMarket", abiFolder);
        _extractContractABI("FixedRateIrm", abiFolder);
        _extractContractABI(oracleName, abiFolder);
        _extractContractABI("DlbDcfPriorityLiquidationEngine", abiFolder);
        _extractContractABI("AltoLeverageSwapper", abiFolder);
        _extractContractABI("AltoLeverage", abiFolder);
    }

    function _extractBorrowMarketABIs(string memory abiFolder, string memory oracleName) internal {
        _extractContractABI("AltoBorrowMarket", abiFolder);
        _extractContractABI("AdaptiveCurveIrm", abiFolder);
        _extractContractABI(oracleName, abiFolder);
        _extractContractABI("DlbDcfPriorityLiquidationEngine", abiFolder);
        _extractContractABI("AltoLeverageSwapper", abiFolder);
        _extractContractABI("AltoLeverage", abiFolder);
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

