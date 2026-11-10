// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

import {DeployAltoTestnet, AltoTestnetParams, AltoTestnetInput} from "@alto/deployments/testnet/DeployAltoTestnet.sol";
import {TestnetMarketBatchReport} from "@alto/deployments/testnet/ITestnetMarketBatch.sol";
import {console} from "forge-std/console.sol";

uint256 constant DEPLOYMENT_ID_TO_LOAD = 1766155992;

// Set to true to deploy only the vault on top of an existing deployment.
// Requires DEPLOYMENT_ID_TO_LOAD to point to the existing deployment timestamp.
bool constant DEPLOY_VAULT_ONLY = true;
string constant OUTPUT_DIR = "./contracts/deployments/testnet/output";

contract DeployAltoTestnetScript is Script {
    AltoTestnetParams params;
    AltoTestnetInput input;

    function run() public {
        if (DEPLOY_VAULT_ONLY && DEPLOYMENT_ID_TO_LOAD == 0) {
            revert("DEPLOYMENT_ID_TO_LOAD must be set to the existing deployment timestamp when deploying vault only");
        }
        _loadCurrentChainInput();

        vm.startBroadcast();

        params = AltoTestnetParams({
            skipLendingDeployment: false,
            skipRewardsDeployment: false,
            deployVaultOnly: DEPLOY_VAULT_ONLY,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            wrappedNativeToken: address(1),
            uniswapV3NonFungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            deployer: msg.sender
        });

        input = DeployAltoTestnet.deploy(params, input);

        vm.stopBroadcast();

        // Store input to JSON format
        _writeInputToJson();

        // Extract ABIs for all deployed contracts
        _extractABIs();

        console.log("Deployment completed successfully");
    }

    function _serializeMarketBatchJson(string memory objectKey, TestnetMarketBatchReport storage batch)
        internal
        returns (string memory j)
    {
        j = vm.serializeAddress(objectKey, "market", batch.market);
        j = vm.serializeAddress(objectKey, "marketImplementation", batch.marketImplementation);
        j = vm.serializeAddress(objectKey, "marketIrm", batch.marketIrm);
        j = vm.serializeAddress(objectKey, "marketOracle", batch.marketOracle);
        j = vm.serializeAddress(objectKey, "liquidationEngine", batch.liquidationEngine);
    }

    function _writeInputToJson() internal {
        string memory tokensJson = "";
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
        tokensJson = vm.serializeAddress("tokens", "paxg", input.tokens.paxg);
        tokensJson = vm.serializeAddress("tokens", "syrupUsdc", input.tokens.syrupUsdc);

        string memory contractsJson = "";
        contractsJson = vm.serializeAddress("contracts", "altoMulticall", input.contracts.altoMulticall);
        contractsJson = vm.serializeAddress("contracts", "multiTokenSender", input.contracts.multiTokenSender);
        contractsJson = vm.serializeAddress("contracts", "mockSwapper", input.contracts.mockSwapper);
        contractsJson = vm.serializeAddress("contracts", "altoLeverage", input.contracts.altoLeverage);
        contractsJson = vm.serializeAddress("contracts", "bundler3", input.contracts.bundler3);
        contractsJson = vm.serializeAddress("contracts", "altoAdapter", input.contracts.altoAdapter);
        contractsJson = vm.serializeAddress("contracts", "marketRegistry", input.contracts.marketRegistry);
        contractsJson = vm.serializeAddress("contracts", "usmRegistry", input.contracts.usmRegistry);
        contractsJson = vm.serializeAddress("contracts", "altoVault", input.contracts.altoVault);

        contractsJson = vm.serializeString(
            "contracts", "wethMarketBatch", _serializeMarketBatchJson("wethMarket", input.contracts.wethMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts",
            "wstethMarketBatch",
            _serializeMarketBatchJson("wstethMarket", input.contracts.wstethMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "rethMarketBatch", _serializeMarketBatchJson("rethMarket", input.contracts.rethMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "methMarketBatch", _serializeMarketBatchJson("methMarket", input.contracts.methMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "tbtcMarketBatch", _serializeMarketBatchJson("tbtcMarket", input.contracts.tbtcMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "wbtcMarketBatch", _serializeMarketBatchJson("wbtcMarket", input.contracts.wbtcMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "cbbtcMarketBatch", _serializeMarketBatchJson("cbbtcMarket", input.contracts.cbbtcMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts", "susdeMarketBatch", _serializeMarketBatchJson("susdeMarket", input.contracts.susdeMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts",
            "syrupUsdcBorrowMarketBatch",
            _serializeMarketBatchJson("syrupUsdcBorrowMarket", input.contracts.syrupUsdcBorrowMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts",
            "paxgBorrowMarketBatch",
            _serializeMarketBatchJson("paxgBorrowMarket", input.contracts.paxgBorrowMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts",
            "susdeMintMarketBatch",
            _serializeMarketBatchJson("susdeMintMarket", input.contracts.susdeMintMarketBatch)
        );
        contractsJson = vm.serializeString(
            "contracts",
            "syrupUsdcMintMarketBatch",
            _serializeMarketBatchJson("syrupUsdcMintMarket", input.contracts.syrupUsdcMintMarketBatch)
        );

        string memory usdcUsmBatchJson = "";
        usdcUsmBatchJson = vm.serializeAddress("usdcUsmBatch", "dusdUsm", input.contracts.usdcUsmBatch.dusdUsm);
        usdcUsmBatchJson = vm.serializeAddress(
            "usdcUsmBatch", "dusdUsmImplementation", input.contracts.usdcUsmBatch.dusdUsmImplementation
        );
        usdcUsmBatchJson =
            vm.serializeAddress("usdcUsmBatch", "fixedPriceStrategy", input.contracts.usdcUsmBatch.fixedPriceStrategy);
        usdcUsmBatchJson =
            vm.serializeAddress("usdcUsmBatch", "fixedFeeStrategy", input.contracts.usdcUsmBatch.fixedFeeStrategy);
        contractsJson = vm.serializeString("contracts", "usdcUsmBatch", usdcUsmBatchJson);

        string memory stakingBatchJson = "";
        stakingBatchJson =
            vm.serializeAddress("stakingBatch", "stakingContract", input.contracts.stakingBatch.stakingContract);
        stakingBatchJson = vm.serializeAddress(
            "stakingBatch", "universalRewardsDistributor", input.contracts.stakingBatch.universalRewardsDistributor
        );
        contractsJson = vm.serializeString("contracts", "stakingBatch", stakingBatchJson);

        string memory rewardsBatchJson = "";
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "rewardsDistributor", input.contracts.rewardsBatch.rewardsDistributor);
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "paymentOracles", input.contracts.rewardsBatch.paymentOracles);
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "rewardOracle", input.contracts.rewardsBatch.rewardOracle);
        rewardsBatchJson =
            vm.serializeAddress("rewardsBatch", "referralAdapter", input.contracts.rewardsBatch.referralAdapter);
        contractsJson = vm.serializeString("contracts", "rewardsBatch", rewardsBatchJson);

        string memory json = vm.serializeString("", "tokens", tokensJson);
        json = vm.serializeString("", "contracts", contractsJson);

        string memory deploymentFolder = _deploymentFolder();
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");
        vm.createDir(deploymentFolder, true);
        vm.writeJson(json, fileName);
        console.log("Deployment data saved to:", fileName);
    }

    /// @dev Returns the output folder for the current deployment.
    /// Uses DEPLOYMENT_ID_TO_LOAD when set so that vault-only runs write into the existing deployment folder.
    function _deploymentFolder() internal view returns (string memory) {
        uint256 id = DEPLOYMENT_ID_TO_LOAD == 0 ? block.timestamp : DEPLOYMENT_ID_TO_LOAD;
        return string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(id));
    }

    /// @dev Returns the address at `key` in `json`, or address(0) if the key is absent.
    function _parseJsonAddressSafe(string memory json, string memory key) internal view returns (address) {
        if (!vm.keyExistsJson(json, key)) return address(0);
        return vm.parseJsonAddress(json, key);
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);

        AltoTestnetInput memory loadedInput;

        // Load tokens
        loadedInput.tokens.alto = _parseJsonAddressSafe(json, ".tokens.alto");
        loadedInput.tokens.dusd = _parseJsonAddressSafe(json, ".tokens.dusd");
        loadedInput.tokens.usdc = _parseJsonAddressSafe(json, ".tokens.usdc");
        loadedInput.tokens.weth = _parseJsonAddressSafe(json, ".tokens.weth");
        loadedInput.tokens.wsteth = _parseJsonAddressSafe(json, ".tokens.wsteth");
        loadedInput.tokens.reth = _parseJsonAddressSafe(json, ".tokens.reth");
        loadedInput.tokens.meth = _parseJsonAddressSafe(json, ".tokens.meth");
        loadedInput.tokens.tbtc = _parseJsonAddressSafe(json, ".tokens.tbtc");
        loadedInput.tokens.wbtc = _parseJsonAddressSafe(json, ".tokens.wbtc");
        loadedInput.tokens.cbbtc = _parseJsonAddressSafe(json, ".tokens.cbbtc");
        loadedInput.tokens.susde = _parseJsonAddressSafe(json, ".tokens.susde");
        loadedInput.tokens.paxg = _parseJsonAddressSafe(json, ".tokens.paxg");
        loadedInput.tokens.syrupUsdc = _parseJsonAddressSafe(json, ".tokens.syrupUsdc");

        // Load contracts
        loadedInput.contracts.altoMulticall = _parseJsonAddressSafe(json, ".contracts.altoMulticall");
        loadedInput.contracts.multiTokenSender = _parseJsonAddressSafe(json, ".contracts.multiTokenSender");
        loadedInput.contracts.mockSwapper = _parseJsonAddressSafe(json, ".contracts.mockSwapper");
        loadedInput.contracts.altoLeverage = _parseJsonAddressSafe(json, ".contracts.altoLeverage");
        loadedInput.contracts.bundler3 = _parseJsonAddressSafe(json, ".contracts.bundler3");
        loadedInput.contracts.altoAdapter = _parseJsonAddressSafe(json, ".contracts.altoAdapter");
        loadedInput.contracts.marketRegistry = _parseJsonAddressSafe(json, ".contracts.marketRegistry");
        loadedInput.contracts.usmRegistry = _parseJsonAddressSafe(json, ".contracts.usmRegistry");
        loadedInput.contracts.altoVault = _parseJsonAddressSafe(json, ".contracts.altoVault");

        // Load market batches
        loadedInput.contracts.wethMarketBatch.market = _parseJsonAddressSafe(json, ".contracts.wethMarketBatch.market");
        loadedInput.contracts.wethMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.wethMarketBatch.marketImplementation");
        loadedInput.contracts.wethMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.wethMarketBatch.marketIrm");
        loadedInput.contracts.wethMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.wethMarketBatch.marketOracle");
        loadedInput.contracts.wethMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.wethMarketBatch.liquidationEngine");

        loadedInput.contracts.wstethMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.wstethMarketBatch.market");
        loadedInput.contracts.wstethMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.wstethMarketBatch.marketImplementation");
        loadedInput.contracts.wstethMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.wstethMarketBatch.marketIrm");
        loadedInput.contracts.wstethMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.wstethMarketBatch.marketOracle");
        loadedInput.contracts.wstethMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.wstethMarketBatch.liquidationEngine");

        loadedInput.contracts.rethMarketBatch.market = _parseJsonAddressSafe(json, ".contracts.rethMarketBatch.market");
        loadedInput.contracts.rethMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.rethMarketBatch.marketImplementation");
        loadedInput.contracts.rethMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.rethMarketBatch.marketIrm");
        loadedInput.contracts.rethMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.rethMarketBatch.marketOracle");
        loadedInput.contracts.rethMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.rethMarketBatch.liquidationEngine");

        loadedInput.contracts.methMarketBatch.market = _parseJsonAddressSafe(json, ".contracts.methMarketBatch.market");
        loadedInput.contracts.methMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.methMarketBatch.marketImplementation");
        loadedInput.contracts.methMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.methMarketBatch.marketIrm");
        loadedInput.contracts.methMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.methMarketBatch.marketOracle");
        loadedInput.contracts.methMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.methMarketBatch.liquidationEngine");

        loadedInput.contracts.tbtcMarketBatch.market = _parseJsonAddressSafe(json, ".contracts.tbtcMarketBatch.market");
        loadedInput.contracts.tbtcMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.tbtcMarketBatch.marketImplementation");
        loadedInput.contracts.tbtcMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.tbtcMarketBatch.marketIrm");
        loadedInput.contracts.tbtcMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.tbtcMarketBatch.marketOracle");
        loadedInput.contracts.tbtcMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.tbtcMarketBatch.liquidationEngine");

        loadedInput.contracts.wbtcMarketBatch.market = _parseJsonAddressSafe(json, ".contracts.wbtcMarketBatch.market");
        loadedInput.contracts.wbtcMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.wbtcMarketBatch.marketImplementation");
        loadedInput.contracts.wbtcMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.wbtcMarketBatch.marketIrm");
        loadedInput.contracts.wbtcMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.wbtcMarketBatch.marketOracle");
        loadedInput.contracts.wbtcMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.wbtcMarketBatch.liquidationEngine");

        loadedInput.contracts.cbbtcMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.cbbtcMarketBatch.market");
        loadedInput.contracts.cbbtcMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.cbbtcMarketBatch.marketImplementation");
        loadedInput.contracts.cbbtcMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.cbbtcMarketBatch.marketIrm");
        loadedInput.contracts.cbbtcMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.cbbtcMarketBatch.marketOracle");
        loadedInput.contracts.cbbtcMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.cbbtcMarketBatch.liquidationEngine");

        loadedInput.contracts.susdeMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.susdeMarketBatch.market");
        loadedInput.contracts.susdeMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.susdeMarketBatch.marketImplementation");
        loadedInput.contracts.susdeMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.susdeMarketBatch.marketIrm");
        loadedInput.contracts.susdeMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.susdeMarketBatch.marketOracle");
        loadedInput.contracts.susdeMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.susdeMarketBatch.liquidationEngine");

        loadedInput.contracts.syrupUsdcBorrowMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcBorrowMarketBatch.market");
        loadedInput.contracts.syrupUsdcBorrowMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcBorrowMarketBatch.marketImplementation");
        loadedInput.contracts.syrupUsdcBorrowMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcBorrowMarketBatch.marketIrm");
        loadedInput.contracts.syrupUsdcBorrowMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcBorrowMarketBatch.marketOracle");
        loadedInput.contracts.syrupUsdcBorrowMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcBorrowMarketBatch.liquidationEngine");

        loadedInput.contracts.paxgBorrowMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.paxgBorrowMarketBatch.market");
        loadedInput.contracts.paxgBorrowMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.paxgBorrowMarketBatch.marketImplementation");
        loadedInput.contracts.paxgBorrowMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.paxgBorrowMarketBatch.marketIrm");
        loadedInput.contracts.paxgBorrowMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.paxgBorrowMarketBatch.marketOracle");
        loadedInput.contracts.paxgBorrowMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.paxgBorrowMarketBatch.liquidationEngine");

        loadedInput.contracts.susdeMintMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.susdeMintMarketBatch.market");
        loadedInput.contracts.susdeMintMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.susdeMintMarketBatch.marketImplementation");
        loadedInput.contracts.susdeMintMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.susdeMintMarketBatch.marketIrm");
        loadedInput.contracts.susdeMintMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.susdeMintMarketBatch.marketOracle");
        loadedInput.contracts.susdeMintMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.susdeMintMarketBatch.liquidationEngine");

        loadedInput.contracts.syrupUsdcMintMarketBatch.market =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcMintMarketBatch.market");
        loadedInput.contracts.syrupUsdcMintMarketBatch.marketImplementation =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcMintMarketBatch.marketImplementation");
        loadedInput.contracts.syrupUsdcMintMarketBatch.marketIrm =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcMintMarketBatch.marketIrm");
        loadedInput.contracts.syrupUsdcMintMarketBatch.marketOracle =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcMintMarketBatch.marketOracle");
        loadedInput.contracts.syrupUsdcMintMarketBatch.liquidationEngine =
            _parseJsonAddressSafe(json, ".contracts.syrupUsdcMintMarketBatch.liquidationEngine");

        // Load usdc usm batch
        loadedInput.contracts.usdcUsmBatch.dusdUsm = _parseJsonAddressSafe(json, ".contracts.usdcUsmBatch.dusdUsm");
        loadedInput.contracts.usdcUsmBatch.dusdUsmImplementation =
            _parseJsonAddressSafe(json, ".contracts.usdcUsmBatch.dusdUsmImplementation");
        loadedInput.contracts.usdcUsmBatch.fixedPriceStrategy =
            _parseJsonAddressSafe(json, ".contracts.usdcUsmBatch.fixedPriceStrategy");
        loadedInput.contracts.usdcUsmBatch.fixedFeeStrategy =
            _parseJsonAddressSafe(json, ".contracts.usdcUsmBatch.fixedFeeStrategy");

        // Load staking batch
        loadedInput.contracts.stakingBatch.stakingContract =
            _parseJsonAddressSafe(json, ".contracts.stakingBatch.stakingContract");
        loadedInput.contracts.stakingBatch.universalRewardsDistributor =
            _parseJsonAddressSafe(json, ".contracts.stakingBatch.universalRewardsDistributor");

        // Load rewards batch
        loadedInput.contracts.rewardsBatch.rewardsDistributor =
            _parseJsonAddressSafe(json, ".contracts.rewardsBatch.rewardsDistributor");
        if (vm.keyExistsJson(json, ".contracts.rewardsBatch.paymentOracles")) {
            loadedInput.contracts.rewardsBatch.paymentOracles =
                vm.parseJsonAddressArray(json, ".contracts.rewardsBatch.paymentOracles");
        }
        loadedInput.contracts.rewardsBatch.rewardOracle =
            _parseJsonAddressSafe(json, ".contracts.rewardsBatch.rewardOracle");
        loadedInput.contracts.rewardsBatch.referralAdapter =
            _parseJsonAddressSafe(json, ".contracts.rewardsBatch.referralAdapter");

        input = loadedInput;
    }

    function _loadCurrentChainInput() internal {
        if (DEPLOYMENT_ID_TO_LOAD == 0) {
            return;
        }
        string memory deploymentFolder = _deploymentFolder();
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");
        _loadInputFromJson(fileName);
    }

    function _extractABIs() internal {
        string memory deploymentFolder = _deploymentFolder();
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
        _extractContractABI("MarketRegistry", abiFolder);
        _extractContractABI("UsmRegistry", abiFolder);
        _extractContractABI("AltoVault", abiFolder);

        // Extract ABIs for market contracts
        _extractContractABI("DlbDcfPriorityLiquidationEngine", abiFolder);
        _extractContractABI("AltoBorrowMarket", abiFolder);
        _extractContractABI("AltoMintMarket", abiFolder);
        _extractContractABI("AdaptiveCurveIrm", abiFolder);
        _extractContractABI("FixedRateIrm", abiFolder);
        _extractContractABI("OracleTestnet", abiFolder);
        _extractContractABI("IAltoLiquidationEngine", abiFolder);

        // Extract ABIs for DUSDUsm contract
        _extractContractABI("DUSDUsm", abiFolder);
        _extractContractABI("FixedPriceStrategy", abiFolder);
        _extractContractABI("FixedFeeStrategy", abiFolder);

        // Extract ABIs for staking contracts
        _extractContractABI("AltoStaking", abiFolder);
        _extractContractABI("UniversalRewardsDistributor", abiFolder);

        // Extract ABIs for rewards contracts
        _extractContractABI("AltoRewardsDistributor", abiFolder);
        _extractContractABI("AltoReferralWhitelistAdapter", abiFolder);

        console.log("ABIs extracted to:", abiFolder);
    }

    function _extractContractABI(string memory contractName, string memory outputDir) internal {
        string memory fileName = string.concat(outputDir, "/", contractName, ".json");
        if (vm.isFile(fileName)) return;

        try vm.getCode(contractName) returns (bytes memory) {
            string memory artifactPath = string.concat("./out/", contractName, ".sol/", contractName, ".json");

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
