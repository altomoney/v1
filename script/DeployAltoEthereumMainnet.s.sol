// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";

import {
    DeployAltoEthereumMainnet,
    AltoEthereumMainnetParams,
    AltoEthereumMainnetInput,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {console} from "forge-std/console.sol";

uint256 constant DEPLOYMENT_ID_TO_LOAD = 1765364975;
DeploymentPhase constant PHASE_TO_DEPLOY = DeploymentPhase.ALTO_LEVERAGE_SWAPPER_MULTI_TARGET; // CORE, DUSD, MINT_MARKET_WETH, MINT_MARKET_WSTETH, MINT_MARKET_RETH, MINT_MARKET_METH, MINT_MARKET_TBTC, BORROW_MARKET_WBTC, BORROW_MARKET_CBBTC, BORROW_MARKET_SUSDE, USDC_USM, POST, REFERRAL_ADAPTER, BORROW_MARKET_SYRUP_USDC, BORROW_MARKET_PAXG, MINT_MARKET_SUSDE, MINT_MARKET_SYRUPUSDC, PERMISSIONED_FRXUSD_USM, ADAPTER, DUSD_VAULT, VAULT_REGISTRY, PERMISSIONLESS_FRXUSD_USM, ALTO_LEVERAGE_SWAPPER_MULTI_TARGET
string constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";

contract DeployAltoEthereumMainnetScript is Script {
    AltoEthereumMainnetParams params;
    AltoEthereumMainnetInput input;

    function run() public {
        _loadCurrentChainInput();

        vm.startBroadcast();

        params = AltoEthereumMainnetParams({
            timelockAdmin: 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0,
            timelockDelay: 1 hours,
            freezer: 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4,
            deployer: msg.sender,
            phase: PHASE_TO_DEPLOY,
            useUnsafeUpgrades: false,
            treasuryMultisig: 0xA1148A1b94262540994Cf9Aa431A13ad39764228,
            updater: 0x7db7C14533a4186EcC07950F78835859320835Be,
            deployerHasOwnership: false // Deployer doesn't have ownership, log txs for multisig
        });

        input = DeployAltoEthereumMainnet.deploy(params, input);

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
        contractsJson = vm.serializeAddress("contracts", "timelock", input.contracts.timelock);
        contractsJson = vm.serializeAddress("contracts", "altoAdapter", input.contracts.altoAdapter);
        contractsJson = vm.serializeAddress("contracts", "feeRecipient", input.contracts.feeRecipient);
        contractsJson =
            vm.serializeAddress("contracts", "feeRecipientMintMarkets", input.contracts.feeRecipientMintMarkets);
        contractsJson = vm.serializeAddress("contracts", "dusd", input.contracts.dusd);
        contractsJson = vm.serializeAddress("contracts", "dusdFlashMinter", input.contracts.dusdFlashMinter);
        contractsJson = vm.serializeAddress("contracts", "marketRegistry", input.contracts.marketRegistry);
        contractsJson = vm.serializeAddress("contracts", "usmRegistry", input.contracts.usmRegistry);
        contractsJson = vm.serializeAddress("contracts", "vaultRegistry", input.contracts.vaultRegistry);
        contractsJson = vm.serializeAddress("contracts", "referralAdapter", input.contracts.referralAdapter);

        // Serialize market contracts using helper
        contractsJson = _serializeMarketContracts(contractsJson, "weth", input.contracts.wethMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "wsteth", input.contracts.wstethMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "reth", input.contracts.rethMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "meth", input.contracts.methMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "tbtc", input.contracts.tbtcMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "wbtcBorrow", input.contracts.wbtcBorrowMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "cbbtcBorrow", input.contracts.cbbtcBorrowMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "susdeBorrow", input.contracts.susdeBorrowMarket);
        contractsJson =
            _serializeMarketContracts(contractsJson, "syrupUsdcBorrow", input.contracts.syrupUsdcBorrowMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "paxgBorrow", input.contracts.paxgBorrowMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "susdeMint", input.contracts.susdeMintMarket);
        contractsJson = _serializeMarketContracts(contractsJson, "syrupUsdcMint", input.contracts.syrupUsdcMintMarket);

        // Serialize USDC USM contracts
        if (input.contracts.permissionedUsm.dusdUsm != address(0)) {
            contractsJson = vm.serializeAddress("contracts", "permissionedUsm", input.contracts.permissionedUsm.dusdUsm);
            contractsJson = vm.serializeAddress(
                "contracts", "permissionedUsmImplementation", input.contracts.permissionedUsm.dusdUsmImplementation
            );
            contractsJson = vm.serializeAddress(
                "contracts", "permissionedUsmFixedPriceStrategy", input.contracts.permissionedUsm.fixedPriceStrategy
            );
            contractsJson = vm.serializeAddress(
                "contracts", "permissionedUsmFixedFeeStrategy", input.contracts.permissionedUsm.fixedFeeStrategy
            );
        }
        if (input.contracts.permissionlessUsm.dusdUsm != address(0)) {
            contractsJson =
                vm.serializeAddress("contracts", "permissionlessUsm", input.contracts.permissionlessUsm.dusdUsm);
            contractsJson = vm.serializeAddress(
                "contracts", "permissionlessUsmImplementation", input.contracts.permissionlessUsm.dusdUsmImplementation
            );
            contractsJson = vm.serializeAddress(
                "contracts", "permissionlessUsmFixedPriceStrategy", input.contracts.permissionlessUsm.fixedPriceStrategy
            );
            contractsJson = vm.serializeAddress(
                "contracts", "permissionlessUsmFixedFeeStrategy", input.contracts.permissionlessUsm.fixedFeeStrategy
            );
        }
        if (input.contracts.permissionedFrxusdUsm.dusdUsm != address(0)) {
            contractsJson = vm.serializeAddress(
                "contracts", "permissionedFrxUsdUsm", input.contracts.permissionedFrxusdUsm.dusdUsm
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionedFrxUsdUsmImplementation",
                input.contracts.permissionedFrxusdUsm.dusdUsmImplementation
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionedFrxUsdUsmFixedPriceStrategy",
                input.contracts.permissionedFrxusdUsm.fixedPriceStrategy
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionedFrxUsdUsmFixedFeeStrategy",
                input.contracts.permissionedFrxusdUsm.fixedFeeStrategy
            );
        }
        if (input.contracts.permissionlessFrxusdUsm.dusdUsm != address(0)) {
            contractsJson = vm.serializeAddress(
                "contracts", "permissionlessFrxUsdUsm", input.contracts.permissionlessFrxusdUsm.dusdUsm
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionlessFrxUsdUsmImplementation",
                input.contracts.permissionlessFrxusdUsm.dusdUsmImplementation
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionlessFrxUsdUsmFixedPriceStrategy",
                input.contracts.permissionlessFrxusdUsm.fixedPriceStrategy
            );
            contractsJson = vm.serializeAddress(
                "contracts",
                "permissionlessFrxUsdUsmFixedFeeStrategy",
                input.contracts.permissionlessFrxusdUsm.fixedFeeStrategy
            );
        }
        if (input.contracts.dusdVault != address(0)) {
            contractsJson = vm.serializeAddress("contracts", "dusdVault", input.contracts.dusdVault);
        }

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
        loadedInput.contracts.timelock = _tryParseAddress(json, ".contracts.timelock");
        loadedInput.contracts.altoAdapter = _tryParseAddress(json, ".contracts.altoAdapter");
        loadedInput.contracts.feeRecipient = _tryParseAddress(json, ".contracts.feeRecipient");
        loadedInput.contracts.feeRecipientMintMarkets = _tryParseAddress(json, ".contracts.feeRecipientMintMarkets");
        loadedInput.contracts.dusd = _tryParseAddress(json, ".contracts.dusd");
        loadedInput.contracts.dusdFlashMinter = _tryParseAddress(json, ".contracts.dusdFlashMinter");
        loadedInput.contracts.marketRegistry = _tryParseAddress(json, ".contracts.marketRegistry");
        loadedInput.contracts.usmRegistry = _tryParseAddress(json, ".contracts.usmRegistry");
        loadedInput.contracts.vaultRegistry = _tryParseAddress(json, ".contracts.vaultRegistry");
        loadedInput.contracts.referralAdapter = _tryParseAddress(json, ".contracts.referralAdapter");

        // Load market contracts using helper
        loadedInput.contracts.wethMarket = _loadMarketContracts(json, "weth");
        loadedInput.contracts.wstethMarket = _loadMarketContracts(json, "wsteth");
        loadedInput.contracts.rethMarket = _loadMarketContracts(json, "reth");
        loadedInput.contracts.methMarket = _loadMarketContracts(json, "meth");
        loadedInput.contracts.tbtcMarket = _loadMarketContracts(json, "tbtc");
        loadedInput.contracts.wbtcBorrowMarket = _loadMarketContracts(json, "wbtcBorrow");
        loadedInput.contracts.cbbtcBorrowMarket = _loadMarketContracts(json, "cbbtcBorrow");
        loadedInput.contracts.susdeBorrowMarket = _loadMarketContracts(json, "susdeBorrow");
        loadedInput.contracts.syrupUsdcBorrowMarket = _loadMarketContracts(json, "syrupUsdcBorrow");
        loadedInput.contracts.paxgBorrowMarket = _loadMarketContracts(json, "paxgBorrow");
        loadedInput.contracts.susdeMintMarket = _loadMarketContracts(json, "susdeMint");
        loadedInput.contracts.syrupUsdcMintMarket = _loadMarketContracts(json, "syrupUsdcMint");

        // Load USDC USM contracts
        loadedInput.contracts.permissionedUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionedUsm");
        loadedInput.contracts.permissionedUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionedUsmImplementation");
        loadedInput.contracts.permissionedUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionedUsmFixedPriceStrategy");
        loadedInput.contracts.permissionedUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionedUsmFixedFeeStrategy");
        loadedInput.contracts.permissionlessUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionlessUsm");
        loadedInput.contracts.permissionlessUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionlessUsmImplementation");
        loadedInput.contracts.permissionlessUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionlessUsmFixedPriceStrategy");
        loadedInput.contracts.permissionlessUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionlessUsmFixedFeeStrategy");

        // Load frxUSD USM contracts
        loadedInput.contracts.permissionedFrxusdUsm.dusdUsm = _tryParseAddress(json, ".contracts.permissionedFrxUsdUsm");
        loadedInput.contracts.permissionedFrxusdUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmImplementation");
        loadedInput.contracts.permissionedFrxusdUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmFixedPriceStrategy");
        loadedInput.contracts.permissionedFrxusdUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionedFrxUsdUsmFixedFeeStrategy");
        loadedInput.contracts.permissionlessFrxusdUsm.dusdUsm =
            _tryParseAddress(json, ".contracts.permissionlessFrxUsdUsm");
        loadedInput.contracts.permissionlessFrxusdUsm.dusdUsmImplementation =
            _tryParseAddress(json, ".contracts.permissionlessFrxUsdUsmImplementation");
        loadedInput.contracts.permissionlessFrxusdUsm.fixedPriceStrategy =
            _tryParseAddress(json, ".contracts.permissionlessFrxUsdUsmFixedPriceStrategy");
        loadedInput.contracts.permissionlessFrxusdUsm.fixedFeeStrategy =
            _tryParseAddress(json, ".contracts.permissionlessFrxUsdUsmFixedFeeStrategy");
        loadedInput.contracts.dusdVault = _tryParseAddress(json, ".contracts.dusdVault");

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
            _extractContractABI("AltoTimelockControllerMintMarketFee", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.REGISTRY) {
            _extractContractABI("MarketRegistry", abiFolder);
            _extractContractABI("UsmRegistry", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.DUSD) {
            _extractContractABI("DUSD", abiFolder);
            _extractContractABI("DUSDFlashMinter", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_WETH) {
            _extractMintMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_WSTETH) {
            _extractMintMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleWSTETH");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_RETH) {
            _extractMintMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleRETH");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_METH) {
            _extractMintMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleMETH");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_TBTC) {
            _extractMintMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_WBTC) {
            _extractBorrowMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_CBBTC) {
            _extractBorrowMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_SUSDE) {
            _extractBorrowMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleSUSDE");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.PERMISSIONED_USM) {
            _extractContractABI("DUSDUsm", abiFolder);
            _extractContractABI("FixedPriceStrategy", abiFolder);
            _extractContractABI("FixedFeeStrategy", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.PERMISSIONED_FRXUSD_USM) {
            _extractContractABI("DUSDUsm", abiFolder);
            _extractContractABI("FixedPriceStrategy", abiFolder);
            _extractContractABI("FixedFeeStrategy", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.PERMISSIONLESS_FRXUSD_USM) {
            _extractContractABI("DUSDUsm", abiFolder);
            _extractContractABI("FixedPriceStrategy", abiFolder);
            _extractContractABI("FixedFeeStrategy", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.DUSD_VAULT) {
            _extractContractABI("AltoVault", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.VAULT_REGISTRY) {
            _extractContractABI("VaultRegistry", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.PERMISSIONLESS_USM) {
            _extractContractABI("DUSDUsm", abiFolder);
            _extractContractABI("FixedPriceStrategy", abiFolder);
            _extractContractABI("FixedFeeStrategy", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.POST) {
            _extractContractABI("AltoTimelockController", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.REFERRAL_ADAPTER) {
            _extractContractABI("AltoReferralWhitelistAdapter", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_SYRUP_USDC) {
            _extractBorrowMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleSYRUPUSDC");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.BORROW_MARKET_PAXG) {
            _extractBorrowMarketABIs(abiFolder, "AltoMultiChainlinkLendingOracle");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_SUSDE) {
            _extractMintMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleSUSDE");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.MINT_MARKET_SYRUPUSDC) {
            _extractMintMarketABIs(abiFolder, "ERC4626RatioChainlinkOracleSYRUPUSDC");
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.ADAPTER) {
            _extractContractABI("AltoAdapter", abiFolder);
        } else if (PHASE_TO_DEPLOY == DeploymentPhase.ALTO_LEVERAGE_SWAPPER_MULTI_TARGET) {
            _extractContractABI("AltoLeverageSwapperMultiTarget", abiFolder);
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

