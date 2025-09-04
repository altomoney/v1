// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {ERC20Testnet} from "@alto/deployments/contracts/testnet/ERC20Testnet.sol";
import {USDO} from "@alto/tokens/USDO.sol";
import {
    TestnetBorrowMarketBatch,
    TestnetBorrowMarketBatchParams
} from "@alto/deployments/_testnet/TestnetBorrowMarketBatch.sol";
import {
    TestnetMintMarketBatch, TestnetMintMarketBatchParams
} from "@alto/deployments/_testnet/TestnetMintMarketBatch.sol";
import {ITestnetMarketBatch, TestnetMarketBatchReport} from "@alto/deployments/_testnet/ITestnetMarketBatch.sol";
import {MultiTokenSender} from "@alto/deployments/contracts/testnet/MultiTokenSender.sol";
import {SwapperSimpleMock} from "@alto/lending/mocks/SwapperSimpleMock.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Bundler3} from "@morpho-org/bundler3/Bundler3.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    TestnetRewardsBatch,
    TestnetRewardsBatchReport,
    TestnetRewardsBatchParams
} from "@alto/deployments/_testnet/TestnetRewardsBatch.sol";
import {
    TestnetStakingBatch,
    TestnetStakingBatchParams,
    TestnetStakingBatchReport
} from "@alto/deployments/_testnet/TestnetStakingBatch.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";

struct AltoInput {
    address owner;
    TestnetTokens tokens;
    Contracts contracts;
}

struct Contracts {
    address multiTokenSender;
    address mockSwapper;
    address altoLeverage;
    address bundler3;
    address altoAdapter;
    TestnetMarketBatchReport borrowMarketBatch;
    TestnetMarketBatchReport mintMarketBatch;
    TestnetStakingBatchReport stakingBatch;
    TestnetRewardsBatchReport rewardsBatch;
}

struct TestnetTokens {
    address alto;
    address usdo;
    address usdc;
    address weth;
}

bool constant SKIP_LENDING_DEPLOYMENT = true;

uint128 constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
address constant LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
address constant WRAPPED_NATIVE_TOKEN = address(1);

address constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
uint256 constant ALTO_TOKEN_TOTAL_SUPPLY = 100_000_000 ether;
uint256 constant USDO_TOKEN_SUPPLY_TO_CONTRACTS = 100_000_000_000 ether;
address constant UNIVERSAL_REWARDS_DISTRIBUTOR = 0x018784fE6D9dbf14ba224797f934fcfb71c3bADd;

contract DeployAltoTestnet is Script {
    AltoInput input;

    function run() public {
        _loadCurrentChainInput();

        vm.startBroadcast();

        input.owner = msg.sender;

        _deployLending();
        _deployStaking();
        _deployRewards();

        IERC20(input.tokens.usdo).transfer(
            input.contracts.stakingBatch.universalRewardsDistributor, USDO_TOKEN_SUPPLY_TO_CONTRACTS
        );
        IERC20(input.tokens.alto).transfer(input.contracts.rewardsBatch.rewardsDistributor, ALTO_TOKEN_TOTAL_SUPPLY / 2);

        vm.stopBroadcast();

        // Store input to JSON format
        _writeInputToJson();

        console.log("Deployment completed successfully");
    }

    function _deployMintFundTokens(address multiTokenSender, address swapper) internal {
        input.tokens.alto = address(new AltoToken(LZ_ENDPOINT, input.owner));
        // all ALTO is already minted to the owner in the constructor
        input.tokens.usdo = address(new USDO(LZ_ENDPOINT, input.owner));
        USDO(input.tokens.usdo).setMinterStatus(input.owner, true);
        // we can't mint uint256 max as markets need to be able to mint during borrow/repay
        USDO(input.tokens.usdo).mint(input.owner, type(uint128).max);
        USDO(input.tokens.usdo).setMinterStatus(input.owner, false);

        input.tokens.weth = address(new ERC20Testnet("WETH", 18, input.owner));
        ERC20Testnet(input.tokens.weth).mint(input.owner, type(uint256).max);
        input.tokens.usdc = address(new ERC20Testnet("USDC", 6, input.owner));
        ERC20Testnet(input.tokens.usdc).mint(input.owner, type(uint256).max);

        // fund tokens to the multi token sender
        IERC20(input.tokens.usdo).transfer(multiTokenSender, USDO_TOKEN_SUPPLY_TO_CONTRACTS);
        IERC20(input.tokens.alto).transfer(multiTokenSender, ALTO_TOKEN_TOTAL_SUPPLY / 4);

        IERC20(input.tokens.weth).transfer(multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).transfer(multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);

        // fund tokens to swapper
        IERC20(input.tokens.usdo).transfer(swapper, USDO_TOKEN_SUPPLY_TO_CONTRACTS);

        IERC20(input.tokens.weth).transfer(swapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        IERC20(input.tokens.usdc).transfer(swapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
    }

    function _deployLending() internal {
        if (SKIP_LENDING_DEPLOYMENT) {
            return;
        }

        // deploy bundler3 and alto adapter
        input.contracts.bundler3 = address(new Bundler3());
        input.contracts.altoAdapter = address(new AltoAdapter(input.contracts.bundler3, WRAPPED_NATIVE_TOKEN));

        // deploy multi token sender
        input.contracts.multiTokenSender = address(new MultiTokenSender(input.owner));
        MultiTokenSender(input.contracts.multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);

        // deploy leverage and mock swapper
        input.contracts.mockSwapper = address(new SwapperSimpleMock(input.owner));
        input.contracts.altoLeverage = address(new AltoLeverage(input.contracts.mockSwapper, input.owner));
        SwapperSimpleMock(payable(input.contracts.mockSwapper)).setWhitelisted(
            address(input.contracts.altoLeverage), true
        );

        // deploy and mint tokens to the owner
        _deployMintFundTokens(input.contracts.multiTokenSender, input.contracts.mockSwapper);

        input.contracts.borrowMarketBatch = (
            new TestnetBorrowMarketBatch(
                TestnetBorrowMarketBatchParams({
                    owner: input.owner,
                    collateralToken: address(input.tokens.usdc),
                    borrowToken: address(input.tokens.usdo),
                    marketOraclePrice: 1e48,
                    maxLtv: 0.75 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.borrowMarketBatch.market, true);
        IMarket(input.contracts.borrowMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);

        input.contracts.mintMarketBatch = (
            new TestnetMintMarketBatch(
                TestnetMintMarketBatchParams({
                    owner: input.owner,
                    collateralToken: address(input.tokens.weth),
                    borrowToken: address(input.tokens.usdo),
                    marketOraclePrice: 4000 * ORACLE_PRICE_PRECISION,
                    maxLtv: 0.75 ether,
                    debtCeiling: 3_000_000 ether
                })
            )
        ).getMarketReport();

        AltoLeverage(input.contracts.altoLeverage).setMarket(input.contracts.mintMarketBatch.market, true);
        IMarket(input.contracts.mintMarketBatch.market).setAuthorizedCallback(input.contracts.altoLeverage, true);
        USDO(input.tokens.usdo).setMinterStatus(input.contracts.mintMarketBatch.market, true);
        USDO(input.tokens.usdo).setBurnerStatus(input.contracts.mintMarketBatch.market, true);
    }

    function _deployStaking() internal {
        input.contracts.stakingBatch = (
            new TestnetStakingBatch(
                TestnetStakingBatchParams({
                    owner: input.owner,
                    rewardToken: address(input.tokens.alto),
                    epochDuration: 1 days,
                    universalRewardsDistributorTimelock: 1 days
                })
            )
        ).getStakingContractReport();
        input.contracts.stakingBatch.universalRewardsDistributor = UNIVERSAL_REWARDS_DISTRIBUTOR;
        Ownable2Step(input.contracts.stakingBatch.stakingContract).acceptOwnership();
    }

    function _deployRewards() internal {
        input.contracts.rewardsBatch = (
            new TestnetRewardsBatch(
                TestnetRewardsBatchParams({
                    owner: input.owner,
                    rewardToken: address(input.tokens.alto),
                    merkleRootTimelock: 1 days,
                    paymentToken: address(input.tokens.usdc),
                    paymentUsdOraclePrice: 1 * USD_ORACLE_PRICE_PRECISION,
                    rewardTokenUsdOraclePrice: 1.2 ether * ORACLE_PRICE_PRECISION / 1 ether,
                    lockBonusDiscount: 0.15 ether,
                    stakingContract: input.contracts.stakingBatch.stakingContract
                })
            )
        ).getRewardsDistributorReport();
        Ownable2Step(input.contracts.rewardsBatch.rewardsDistributor).acceptOwnership();
    }

    function _writeInputToJson() internal {
        string memory json = "";

        // Build owner JSON
        json = vm.serializeAddress("", "owner", input.owner);

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

        // Write to file
        string memory fileName = string.concat("./deployments/testnet-", vm.toString(block.chainid), ".json");
        vm.writeJson(json, fileName);

        console.log("Deployment data saved to:", fileName);
    }

    function _loadInputFromJson(string memory fileName) internal {
        string memory json = vm.readFile(fileName);

        AltoInput memory loadedInput;

        // Load owner
        loadedInput.owner = vm.parseJsonAddress(json, ".owner");

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
        string memory fileName = string.concat("./deployments/testnet-", vm.toString(block.chainid), ".json");
        _loadInputFromJson(fileName);
    }
}
