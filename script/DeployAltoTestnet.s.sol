// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoRelease} from "deployments/releases/alto-v1/AltoRelease.sol";
import {AltoReport, AltoInput} from "deployments/interfaces/IAltoReport.sol";
import {Script} from "forge-std/Script.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";
import {AltoMulticall} from "@alto/deployments/contracts/multicall/AltoMulticall.sol";
import {ERC20Testnet} from "@alto/deployments/contracts/testnet/ERC20Testnet.sol";
import {USDO} from "@alto/tokens/USDO.sol";
import {
    TestnetOracles,
    TestnetOraclesBatch
} from "@alto/deployments/releases/alto-v1/batches/testnet/TestnetOraclesBatch.sol";
import "forge-std/console.sol";
import {AltoMulticallTestnet} from "@alto/deployments/contracts/multicall/AltoMulticallTestnet.sol";
import {console} from "forge-std/console.sol";

contract DeployAltoTestnet is Script {
    uint128 public constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
    uint256 public constant EPOCH_DURATION_INTERNAL_TESTING = 10 minutes;
    uint256 public constant EPOCH_DURATION_PUBLIC_TESTING = 2 days;
    address public constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
    uint256 public constant DEFAULT_MAX_DEBT_BUFFER = 1e4;
    uint256 public constant DEFAULT_BB_MARKET_BORROW_CAP = 3_000_000e18;

    function run() public {
        AltoInput memory input;
        AltoReport memory report;

        vm.startBroadcast();
        // AltoRelease input params
        input.lzChainId = 40217;
        input.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        input.isTestnet = true;
        input.owner = msg.sender;
        input.bbMarketBorrowCap = DEFAULT_BB_MARKET_BORROW_CAP;
        input.wrappedNativeToken = address(1);

        ERC20Testnet stETH = new ERC20Testnet("stETH", 18, input.owner);
        ERC20Testnet usdc = new ERC20Testnet("USDC", 6, input.owner);

        input.collateralTokenMintMarket = address(stETH);
        input.collateralTokenBorrowMarket = address(usdc);
        input.altoToken = address(new AltoToken(input.lzEndpoint, input.owner));

        TestnetOracles memory oracles = deployTestnetOracles(input);

        input.borrowOracle = oracles.usdcOracle;
        input.mintOracle = oracles.stETHOracle;

        report = AltoRelease.deployAltoV1(input, report);

        ERC20Testnet(usdc).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(stETH).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(stETH).mint(report.leverageSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(usdc).mint(report.leverageSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        AltoToken(payable(input.altoToken)).transfer(report.multiTokenSender, 20_000_000 ether);

        console.log("AltoLeverage: ", report.altoLeverage);
        console.log("LeverageSwapper: ", report.leverageSwapper);
        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("AltoMulticall: ", report.altoMulticall);
        console.log("USDO: ", report.usdo);
        console.log("MarketLib: check address in broadcast/run-latest.json");
        console.log("WrappedNativeToken: ", input.wrappedNativeToken);
        console.log("IsTestnet: ", input.isTestnet);
        console.log("Deployer:", msg.sender);
        console.log("LzChainId:", vm.toString(input.lzChainId));
        console.log("AltoToken: ", input.altoToken);
        console.log("stETHOracle: ", oracles.stETHOracle);
        console.log("USDOOracle: ", oracles.usdoOracle);
        console.log("USDCOracle: ", oracles.usdcOracle);
        console.log("AltoOracle: ", oracles.altoOracle);

        console.log("BorrowMarket: ", address(report.borrowMarket));
        console.log("MintMarket: ", address(report.mintMarket));
        console.log("BorrowIrm: ", address(report.borrowIrm));
        console.log("MintIrm: ", address(report.mintIrm));
        console.log("Bundler3: ", address(report.bundler3));
        console.log("AltoAdapter: ", address(report.altoAdapter));

        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("AltoMulticall: ", report.altoMulticall);
        console.log("USDO: ", report.usdo);
        console.log("AltoToken: ", report.altoToken);
        console.log("RewardsDistributor: ", report.rewardsDistributor);
        console.log("TWAltoStaking: ", report.twAltoStaking);

        vm.stopBroadcast();
    }

    function deployTestnetOracles(AltoInput memory input) internal returns (TestnetOracles memory oracles) {
        TestnetOraclesBatch oraclesBatch = new TestnetOraclesBatch();

        return oraclesBatch.getOraclesReport();
    }
}
