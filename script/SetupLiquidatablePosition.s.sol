// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IMarket, Position, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {MultiTokenSender} from "@alto/deployments/testnet/contracts/MultiTokenSender.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";

string constant OUTPUT_DIR = "./contracts/deployments/testnet/output";

/// @title SetupLiquidatablePosition
/// @notice Script to set up a liquidatable position on testnet for testing
/// @dev Assumes testnet was deployed with current deployment scripts
/// @dev Run with: forge script script/SetupLiquidatablePosition.s.sol --rpc-url <RPC> --private-key <DEPLOYER_PK> --broadcast -vvv
/// @dev Environment variables:
///      - MARKET: "weth" or "wbtc" (default: "weth")
///      - DEPLOYMENT_ID: timestamp of the deployment folder (required)
contract SetupLiquidatablePositionScript is Script {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    // Deployment addresses loaded from JSON
    address altoMulticall;
    address multiTokenSender;

    // Market-specific addresses
    address market;
    address marketOracle;
    address liquidationEngine;
    address collateralToken;
    address borrowToken;

    // Market parameters
    uint256 defaultOraclePrice;
    uint256 collateralDecimals;
    uint256 collateralAmountFor10k;

    // Test user - derived from deterministic private key
    uint256 constant USER_PRIVATE_KEY_SEED = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 userPrivateKey;
    address user;

    function run() public {
        // Get market type from environment variable: "weth" or "wbtc"
        string memory marketType = "weth";
        uint256 deploymentId = 1765539372;

        console.log("Setting up liquidatable position for market:", marketType);
        console.log("Deployment ID:", deploymentId);

        // Load deployment addresses
        _loadDeployment(deploymentId, marketType);

        // Generate deterministic test user from seed + block data for uniqueness
        userPrivateKey = uint256(keccak256(abi.encodePacked(USER_PRIVATE_KEY_SEED, block.timestamp, block.chainid)));
        user = vm.addr(userPrivateKey);

        console.log("Test user address:", user);
        console.log("Test user private key:", vm.toString(bytes32(userPrivateKey)));

        vm.startBroadcast(userPrivateKey);

        // approving msg.sender to authorize on behalf of user
        IMarket(market).setAuthorization(msg.sender, true);

        vm.stopBroadcast();

        vm.startBroadcast();

        // Step 1: Disable priority liquidation if enabled
        _disablePriorityLiquidationIfEnabled();

        // Step 2: Set oracle price to default if not already
        _setOraclePriceToDefault();

        // Step 3: Fund user with collateral and native token for gas
        _fundUser();

        // Steps 4-5: User actions (deposit and borrow) - broadcast as user

        // Step 4: Deposit collateral
        _depositCollateral();

        // Step 5: Borrow at max LTV
        _borrowAtMaxLtv();

        vm.stopBroadcast();

        // Step 6: Lower oracle price (requires multicall owner)
        vm.startBroadcast();

        _makePositionLiquidatable();

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("Liquidatable position created!");
        console.log("User address:", user);
        console.log("User private key:", vm.toString(bytes32(userPrivateKey)));
        console.log("Market:", market);
        console.log("=====================================");
    }

    function _loadDeployment(uint256 deploymentId, string memory marketType) internal {
        string memory deploymentFolder;

        if (deploymentId == 0) {
            // Find the latest deployment by listing directory
            revert("DEPLOYMENT_ID environment variable required");
        }

        deploymentFolder =
            string.concat(OUTPUT_DIR, "/testnet-", vm.toString(block.chainid), "-", vm.toString(deploymentId));
        string memory fileName = string.concat(deploymentFolder, "/addresses.json");

        console.log("Loading deployment from:", fileName);

        string memory json = vm.readFile(fileName);

        altoMulticall = vm.parseJsonAddress(json, ".contracts.altoMulticall");
        multiTokenSender = vm.parseJsonAddress(json, ".contracts.multiTokenSender");
        borrowToken = vm.parseJsonAddress(json, ".tokens.dusd");

        if (keccak256(bytes(marketType)) == keccak256(bytes("weth"))) {
            market = vm.parseJsonAddress(json, ".contracts.wethMarketBatch.market");
            marketOracle = vm.parseJsonAddress(json, ".contracts.wethMarketBatch.marketOracle");
            liquidationEngine = vm.parseJsonAddress(json, ".contracts.wethMarketBatch.liquidationEngine");
            collateralToken = vm.parseJsonAddress(json, ".tokens.weth");

            // WETH: 18 decimals, ~$4100 per ETH, so ~2.44 ETH for $10k
            defaultOraclePrice = 4100 * LENDING_ORACLE_PRICE_PRECISION;
            collateralDecimals = 18;
            collateralAmountFor10k = 2.5 ether; // ~$10,250 at $4100/ETH
        } else if (keccak256(bytes(marketType)) == keccak256(bytes("wbtc"))) {
            market = vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.market");
            marketOracle = vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.marketOracle");
            liquidationEngine = vm.parseJsonAddress(json, ".contracts.wbtcMarketBatch.liquidationEngine");
            collateralToken = vm.parseJsonAddress(json, ".tokens.wbtc");

            // WBTC: 8 decimals, ~$100,000 per BTC, so ~0.1 BTC for $10k
            // Note: Oracle price includes decimal adjustment (1e10 multiplier for 8 decimal tokens)
            defaultOraclePrice = 100_000 * LENDING_ORACLE_PRICE_PRECISION * 1e10;
            collateralDecimals = 8;
            collateralAmountFor10k = 0.1e8; // 0.1 BTC = $10,000 at $100k/BTC
        } else {
            revert("Invalid market type. Use 'weth' or 'wbtc'");
        }

        console.log("Market loaded:", market);
        console.log("Oracle:", marketOracle);
        console.log("Liquidation Engine:", liquidationEngine);
        console.log("Collateral Token:", collateralToken);
    }

    function _disablePriorityLiquidationIfEnabled() internal {
        DlbDcfPriorityLiquidationEngine engine = DlbDcfPriorityLiquidationEngine(liquidationEngine);

        (
            uint256 maxLiquidationLtv,
            uint256 dynamicBonusFeeStart,
            uint256 ltvForCompleteLiquidation,
            uint256 dynamicBonusFeeDecaySteepness,
            uint256 liquidationBaseFee,
            uint256 minPenaltyPercentage,
            uint256 protocolFeePercentage,
            bool isEnabledPriorityLiquidation,
            uint256 disablePriorityLiquidationAbovePositionLtv,
            uint32 priorityLiquidationGracePeriod,
            uint32 taggerLiquidationGracePeriod,
            uint32 liquidationWindowTag
        ) = engine.liquidationConfiguration();

        if (isEnabledPriorityLiquidation) {
            console.log("Disabling priority liquidation...");

            LiquidationConfiguration memory newConfig = LiquidationConfiguration({
                maxLiquidationLtv: maxLiquidationLtv,
                dynamicBonusFeeStart: dynamicBonusFeeStart,
                ltvForCompleteLiquidation: ltvForCompleteLiquidation,
                dynamicBonusFeeDecaySteepness: dynamicBonusFeeDecaySteepness,
                liquidationBaseFee: liquidationBaseFee,
                minPenaltyPercentage: minPenaltyPercentage,
                protocolFeePercentage: protocolFeePercentage,
                isEnabledPriorityLiquidation: false,
                disablePriorityLiquidationAbovePositionLtv: disablePriorityLiquidationAbovePositionLtv,
                priorityLiquidationGracePeriod: priorityLiquidationGracePeriod,
                taggerLiquidationGracePeriod: taggerLiquidationGracePeriod,
                liquidationWindowTag: liquidationWindowTag
            });

            // Call via multicall since it owns the liquidation engine
            AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
            calls[0] = AltoMulticallTestnet.Call({
                target: liquidationEngine,
                allowFailure: false,
                callData: abi.encodeCall(DlbDcfPriorityLiquidationEngine.setLiquidationConfiguration, (newConfig))
            });

            AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
            console.log("Priority liquidation disabled");
        } else {
            console.log("Priority liquidation already disabled");
        }
    }

    function _setOraclePriceToDefault() internal {
        OracleTestnet oracle = OracleTestnet(marketOracle);
        uint256 currentPrice = oracle.getPrice();

        if (currentPrice != defaultOraclePrice) {
            console.log("Setting oracle price to default...");
            console.log("Current price:", currentPrice);
            console.log("Default price:", defaultOraclePrice);

            // Call via multicall since it owns the oracle
            AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
            calls[0] = AltoMulticallTestnet.Call({
                target: marketOracle,
                allowFailure: false,
                callData: abi.encodeCall(OracleTestnet.setPrice, (defaultOraclePrice))
            });

            AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
            console.log("Oracle price set to default");
        } else {
            console.log("Oracle price already at default");
        }
    }

    function _fundUser() internal {
        console.log("Funding sender with collateral...");
        console.log("Collateral amount:", collateralAmountFor10k);

        AltoMulticallTestnet multicall = AltoMulticallTestnet(payable(altoMulticall));

        // Step 1: Whitelist msg.sender on multiTokenSender via multicall
        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
        calls[0] = AltoMulticallTestnet.Call({
            target: multiTokenSender,
            allowFailure: false,
            callData: abi.encodeCall(MultiTokenSender.updateWhitelist, (msg.sender, true))
        });
        multicall.multicall(calls);

        // Step 2: Send tokens to user via multiTokenSender
        address[] memory tokens = new address[](1);
        tokens[0] = collateralToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = collateralAmountFor10k;
        MultiTokenSender(multiTokenSender).sendTokens(tokens, msg.sender, amounts);

        if (IMarket(market).MARKET_TYPE() == MarketType.BORROW) {
            tokens[0] = borrowToken;
            amounts[0] = 10_000 ether;
            MultiTokenSender(multiTokenSender).sendTokens(tokens, msg.sender, amounts);
        }

        console.log("Sender funded with collateral");
    }

    function _depositCollateral() internal {
        console.log("Depositing collateral on behalf of user...");

        IERC20(collateralToken).approve(market, collateralAmountFor10k);
        IMarket(market).addCollateral(collateralAmountFor10k, user);

        Position memory pos = IMarket(market).position(user);
        console.log("Collateral deposited:", pos.collateralAssets);
    }

    function _borrowAtMaxLtv() internal {
        console.log("Borrowing at max LTV on behalf of user...");

        IMarket marketContract = IMarket(market);

        uint256 borrowAmount = 10_000 ether;

        if (marketContract.MARKET_TYPE() == MarketType.BORROW) {
            console.log("Supplying DUSD for borrow market...");

            IERC20(borrowToken).approve(address(marketContract), borrowAmount);
            marketContract.addSupply(borrowAmount, 0, msg.sender);

            console.log("DUSD supplied: ", borrowAmount);
        }

        marketContract.borrow(borrowAmount.multiplyWithPrecisionUp(0.745 ether) + 5 ether, 0, user, msg.sender, "");
    }

    function _makePositionLiquidatable() internal {
        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
        calls[0] = AltoMulticallTestnet.Call({
            target: marketOracle,
            allowFailure: false,
            callData: abi.encodeCall(OracleTestnet.setPrice, (defaultOraclePrice.multiplyWithPrecisionUp(0.75 ether)))
        });

        AltoMulticallTestnet(payable(altoMulticall)).multicall(calls);
        console.log("Oracle price set to default");
    }
}

