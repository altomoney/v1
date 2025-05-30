// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoRelease} from "deployments/releases/tapioca-v1/AltoRelease.sol";
import {AltoReport, TapiocaInput} from "deployments/interfaces/IAltoReport.sol";
import {Script} from "forge-std/Script.sol";
import {TapToken, ITapToken} from "@alto/tokens/TapToken.sol";
// import {TapiocaOptionBroker} from "@alto/tap-token/options/TapiocaOptionBroker.sol";
import {TapiocaMulticall} from "@alto/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {ERC20Testnet} from "@alto/deployments/testnet/ERC20Testnet.sol";
import {Usdo} from "@alto/tokens/Usdo.sol";
import {
    TestnetOracles,
    TestnetOraclesBatch
} from "@alto/deployments/releases/tapioca-v1/batches/testnet/TestnetOraclesBatch.sol";
import "forge-std/console.sol";
import {TapiocaMulticallTestnet} from "@alto/utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {console} from "forge-std/console.sol";
// import {TapiocaTestnetTobSetter} from "@alto/deployments/releases/tapioca-v1/actions/TobLauncher.sol";

contract DeployAltoTestnet is Script {
    uint128 public constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
    uint256 public constant EPOCH_DURATION_INTERNAL_TESTING = 10 minutes;
    uint256 public constant EPOCH_DURATION_PUBLIC_TESTING = 2 days;
    address public constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
    uint256 public constant DEFAULT_MAX_DEBT_BUFFER = 1e4;
    uint256 public constant DEFAULT_BB_MARKET_BORROW_CAP = 3_000_000e18;

    function run() public {
        TapiocaInput memory input;
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
        input.tapToken = address(
            new TapToken(
                ITapToken.TapTokenConstructorData(
                    EPOCH_DURATION_INTERNAL_TESTING,
                    input.lzEndpoint,
                    input.owner,
                    input.owner,
                    input.owner,
                    input.owner,
                    input.owner,
                    input.owner,
                    input.owner
                )
            )
        );

        TestnetOracles memory oracles = deployTestnetOracles(input);

        input.borrowOracle = oracles.usdcOracle;
        input.mintOracle = oracles.stETHOracle;

        report = AltoRelease.deployAltoV1(input, report);

        TapToken(payable(input.tapToken)).transfer(report.multiTokenSender, 20_000_000 ether);
        ERC20Testnet(usdc).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(stETH).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(stETH).mint(report.leverageSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(usdc).mint(report.leverageSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        TapToken(payable(input.tapToken)).transfer(report.multiTokenSender, 20_000_000 ether);
        TapToken(payable(input.tapToken)).transfer(
            report.tapiocaMulticall, TapToken(payable(input.tapToken)).balanceOf(msg.sender) - 100000e18
        );

        console.log("AltoLeverage: ", report.altoLeverage);
        console.log("LeverageSwapper: ", report.leverageSwapper);
        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("TapiocaMulticall: ", report.tapiocaMulticall);
        console.log("Usdo: ", report.usdo);
        console.log("MarketLib: check address in broadcast/run-latest.json");
        console.log("WrappedNativeToken: ", input.wrappedNativeToken);
        console.log("IsTestnet: ", input.isTestnet);
        console.log("Deployer:", msg.sender);
        console.log("LzChainId:", vm.toString(input.lzChainId));
        console.log("TapToken: ", input.tapToken);
        console.log("stETHOracle: ", oracles.stETHOracle);
        console.log("USDOOracle: ", oracles.usdoOracle);
        console.log("USDCOracle: ", oracles.usdcOracle);
        console.log("TapOracle: ", oracles.tapOracle);

        console.log("BorrowMarket: ", address(report.borrowMarket));
        console.log("MintMarket: ", address(report.mintMarket));
        console.log("BorrowIrm: ", address(report.borrowIrm));
        console.log("MintIrm: ", address(report.mintIrm));
        console.log("Bundler3: ", address(report.bundler3));
        console.log("AltoAdapter: ", address(report.altoAdapter));

        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("TapiocaMulticall: ", report.tapiocaMulticall);
        console.log("Usdo: ", report.usdo);

        {
            /*
            TapiocaTestnetTobSetter tobSetter = new TapiocaTestnetTobSetter(
                report,
                address(1), // singularityMarket
                input.tapToken,
                report.tapiocaMulticall,
                input.owner,
                address(usdc),
                oracles.usdcOracle,
                oracles.tapOracle,
                EPOCH_DURATION_INTERNAL_TESTING,
                DEFAULT_MAX_DEBT_BUFFER
            );
            TapiocaOptionBroker tob = tobSetter.tob();
            console.log("TapiocaOptionBroker:", address(tob));

            TapToken(payable(input.tapToken)).setMinter(address(tob));

            tob.enableTapTokenRewards();
            tob.transferOwnership(report.tapiocaMulticall);
            */

            //address twTap = createTwTap(payable(input.tapToken), input.owner);
            //console.log("twTAP:", address(twTap));

            //TapToken(payable(input.tapToken)).setMinter(address(tob));

            // Mint and transfer mock tokens to multitokensender and deployer

            // (ITapiocaOracle oracle, bytes memory oracleData) = tob._paymentTokens(address(usdc));
            // console.log("TOB payment oracle: ", address(oracle));
            // console.log("TOB payment oracle data (might be empty): ");
            // console.logBytes(oracleData);
            // require(address(oracle) != address(0), "TOB payment oracle is not set");
        }

        vm.stopBroadcast();
    }

    function deployTestnetOracles(TapiocaInput memory input) internal returns (TestnetOracles memory oracles) {
        TestnetOraclesBatch oraclesBatch = new TestnetOraclesBatch();

        return oraclesBatch.getOraclesReport();
    }
}
