// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {AltoRelease} from "deployments/releases/tapioca-v1/AltoRelease.sol";
import {AltoReport, TapiocaInput} from "deployments/interfaces/IAltoReport.sol";
import {Script} from "forge-std/Script.sol";
import {TapToken, ITapToken} from "contracts/tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {TwTAP} from "tap-token/governance/twTAP.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Bucket} from "tap-token/interfaces/ITWLBase.sol";
import {SeerCLSolo} from "contracts/utils/oracle/SeerCLSolo.sol";
import {OracleChainlinkSingleConstructorData} from "contracts/utils/oracle/OracleChainlinkSingle.sol";
import {TestnetOracle} from "test/utils/mocks/TestnetOracle.sol";
import {ERC20Testnet} from "test/utils/mocks/ERC20Testnet.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {MultiTokenSender} from "../contracts/mocks/MultiTokenSender.sol";
import {
    TestnetOracles,
    TestnetOraclesBatch
} from "contracts/deployments/releases/tapioca-v1/batches/testnet/TestnetOraclesBatch.sol";
import "forge-std/console.sol";
import {TapiocaMulticallTestnet} from "contracts/utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {IMarket} from "../contracts/utils/interfaces/bar/IMarket.sol";
import {console} from "forge-std/console.sol";
import {TapiocaTestnetTobSetter} from "contracts/deployments/releases/tapioca-v1/actions/TobLauncher.sol";

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
        input.zeroXProxy = address(0); // Not used in testnet
        input.wrappedNativeToken = address(new WETH());

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
                    input.owner,
                    address(1)
                )
            )
        );

        TestnetOracles memory oracles = deployTestnetOracles(input);

        input.borrowOracle = oracles.stETHOracle;
        input.mintOracle = oracles.stETHOracle;

        report = AltoRelease.deployAltoV1(input, report);

        TapToken(payable(input.tapToken)).transfer(report.multiTokenSender, 20_000_000 ether);
        ERC20Testnet(usdc).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        ERC20Testnet(stETH).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);

        console.log("SimpleLeverageExecutor: ", report.simpleLeverageExecutor);
        console.log("ZeroXSwapper: ", report.zeroXSwapper);
        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("TapiocaMulticall: ", report.tapiocaMulticall);
        console.log("Usdo: ", report.usdo);
        console.log("MarketLib: check address in broadcast/run-latest.json");
        console.log("WrappedNativeToken: ", input.wrappedNativeToken);
        console.log("IsTestnet: ", input.isTestnet);
        console.log("ZeroXProxy: ", input.zeroXProxy);
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

        vm.stopBroadcast();
    }

    function deployTestnetOracles(TapiocaInput memory input) internal returns (TestnetOracles memory oracles) {
        TestnetOraclesBatch oraclesBatch = new TestnetOraclesBatch();

        return oraclesBatch.getOraclesReport();
    }
}
