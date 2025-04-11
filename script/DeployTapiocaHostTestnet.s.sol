// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";
import {SingularityLauncher, RiskParams} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {BigBangLauncher, BigBangRiskParams} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {Script} from "forge-std/Script.sol";
import {TapToken, ITapToken} from "contracts/tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {TapTokenSender} from "contracts/tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "contracts/tap-token/tokens/TapTokenReceiver.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {TwTAP} from "tap-token/governance/twTAP.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
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
import {TapiocaTestnetTobSetter} from "contracts/deployments/releases/tapioca-v1/actions/TobLauncher.sol";
import "forge-std/console.sol";
import {TapiocaMulticallTestnet} from "contracts/utils/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {IMarket} from "../contracts/utils/interfaces/bar/IMarket.sol";
import {console} from "forge-std/console.sol";

contract DeployTapiocaHostTestnet is Script {
    uint128 public constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;
    uint256 public constant EPOCH_DURATION_INTERNAL_TESTING = 10 minutes;
    uint256 public constant EPOCH_DURATION_PUBLIC_TESTING = 2 days;
    address public constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
    uint256 public constant DEFAULT_MAX_DEBT_BUFFER = 1e4;
    uint256 public constant DEFAULT_BB_MARKET_BORROW_CAP = 3_000_000e18;

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;

        vm.startBroadcast();
        // TapiocaRelease input params
        input.lzChainId = 40217;
        input.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        input.isTestnet = true;
        input.owner = msg.sender;
        input.bbMarketBorrowCap = DEFAULT_BB_MARKET_BORROW_CAP;
        input.zeroXProxy = address(0); // Not used in testnet

        // BigBang risk params
        BigBangRiskParams memory bigBangRiskParams;

        input.wrappedNativeToken = address(new WETH());

        ERC20Testnet stETH = new ERC20Testnet("stETH", 18, input.owner);
        ERC20Testnet usdc = new ERC20Testnet("USDC", 18, input.owner);

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
                    input.lzChainId, // set gov chain same as testnet
                    input.owner,
                    address(new TapTokenSender("", "", input.lzEndpoint, input.owner, address(0))),
                    address(new TapTokenReceiver("", "", input.lzEndpoint, input.owner, address(0))),
                    address(address(0)),
                    ICluster(address(0))
                )
            )
        );

        TestnetOracles memory oracles = deployTestnetOracles(input);

        console.log("WrappedNativeToken: ", input.wrappedNativeToken);
        console.log("IsTestnet: ", input.isTestnet);
        console.log("ZeroXProxy: ", input.zeroXProxy);
        console.log("Deployer:", msg.sender);
        console.log("LzChainId:", vm.toString(input.lzChainId));
        console.log("TapToken: ", input.tapToken);
        console.log("stETH Oracle: ", oracles.stETHOracle);
        console.log("USDO Oracle: ", oracles.usdoOracle);
        console.log("USDC Oracle: ", oracles.usdcOracle);
        console.log("Tap Oracle: ", oracles.tapOracle);

        report = TapiocaRelease.deployTapiocaV1(input, report);
        console.log("Magnetar: ", report.magnetar);
        console.log("MagnetarCollateralModule: ", report.magnetarCollateralModule);
        console.log("MagnetarMintModule: ", report.magnetarMintModule);
        console.log("MagnetarOptionModule: ", report.magnetarOptionModule);
        console.log("MagnetarAssetModule: ", report.magnetarAssetModule);
        console.log("MagnetarLeverageModule: ", report.magnetarLeverageModule);
        console.log("MagnetarHelper: ", report.magnetarHelper);
        console.log("SimpleLeverageExecutor: ", report.simpleLeverageExecutor);
        console.log("ToftHelper: ", report.toftHelper);
        console.log("ZeroXSwapper: ", report.zeroXSwapper);
        console.log("MultiTokenSender: ", report.multiTokenSender);
        console.log("ToeHelper: ", report.toeHelper);
        console.log("Cluster: ", report.cluster);
        console.log("AdbTapOptionOracle: ", report.adbTapOptionOracle);
        console.log("TapiocaMulticall: ", report.tapiocaMulticall);
        console.log("ExtExec: ", report.extExec);
        console.log("LiquidatorReceiver: ", report.liquidatorReceiver);
        console.log("UsdoSenderModule: ", report.usdoSenderModule);
        console.log("UsdoReceiverModule: ", report.usdoReceiverModule);
        console.log("MarketReceiverModule: ", report.marketReceiverModule);
        console.log("OptionReceiverModule: ", report.optionReceiverModule);
        console.log("Usdo: ", report.usdo);
        console.log("SglInit: ", report.sglInit);
        console.log("SGLInterestHelper: ", report.sglInterestHelper);
        console.log("SGLLiquidation: ", report.sglLiquidationModule);
        console.log("SGLBorrow: ", report.sglBorrowModule);
        console.log("SGLCollateral: ", report.sglCollateralModule);
        console.log("SGLLeverage: ", report.sglLeverageModule);
        console.log("Singularity: ", report.singularity);
        console.log("Penrose: ", report.penrose);
        console.log("TapStrat: ", report.tapStrat);
        console.log("WrappedTokenStrat: ", report.wrappedTokenStrat);
        console.log("UsdoStrat: ", report.usdoStrat);
        console.log("MarketHelper: ", report.marketHelper);
        console.log("BbLiquidation: ", report.bbLiquidation);
        console.log("BbBorrow: ", report.bbBorrow);
        console.log("BbCollateral: ", report.bbCollateral);
        console.log("BbLeverage: ", report.bbLeverage);
        console.log("BbDebtRateHelper: ", report.bbDebtRateHelper);
        console.log("Bigbang: ", report.bigbang);
        console.log("SingularityLauncher: ", report.singularityLauncher);
        console.log("BigBangLauncher: ", report.bigBangLauncher);

        {
            TapToken(payable(input.tapToken)).setCluster(ICluster(report.cluster));
            TapToken(payable(input.tapToken)).setToeExtExec(report.extExec);
            Usdo(payable(report.usdo)).setMinterStatus(address(input.owner), true);
            Usdo(payable(report.usdo)).mint(input.owner, 1000000 ether);
        }

        address singularity;
        {
            RiskParams memory singularityRiskParams;
            singularityRiskParams.borrowOpeningFee = 50;
            singularityRiskParams.liquidationMultiplier = 12000;
            singularityRiskParams.minimumTargetUtilization = 600000000000000000;
            singularityRiskParams.maximumTargetUtilization = 700000000000000000;
            singularityRiskParams.minimumInterestPerSecond = 951293760;
            singularityRiskParams.maximumInterestPerSecond = 15854896000;
            singularityRiskParams.interestElasticity = 3600e36;
            singularityRiskParams.minLendAmount = 1e6;
            singularityRiskParams.exchangeRatePrecision = 1e8; // oracles are in 8 decimals (Chainlink USD, 8 decimals)
            singularityRiskParams.collateralizationRate = 75000;
            singularityRiskParams.liquidationCollateralizationRate = 80000;
            singularityRiskParams.oracle = oracles.stETHOracle;
            singularityRiskParams.seedAmount = 100 ether;
            singularityRiskParams.seedOwner = input.owner;
            singularityRiskParams.oracle = oracles.usdcOracle;

            singularity = createSingularityMarket(
                report.tapiocaMulticall,
                report.singularityLauncher,
                address(usdc),
                report.usdo,
                oracles.usdcOracle,
                singularityRiskParams
            );
            console.log("Singularity: ", singularity);
        }

        address bigBang;
        {
            BigBangRiskParams memory bigBangRiskParams;
            bigBangRiskParams.debtRateAgainstEth = 5000000000000000;
            bigBangRiskParams.debtRateMin = 5000000000000000;
            bigBangRiskParams.debtRateMax = 50000000000000000;
            bigBangRiskParams.exchangeRatePrecision = 1e8;
            bigBangRiskParams.collateralizationRate = 75000;
            bigBangRiskParams.liquidationCollateralizationRate = 80000;
            bigBangRiskParams.oracle = oracles.stETHOracle;
            bigBangRiskParams.isEthMarket = true;
            bigBangRiskParams.collateral = address(stETH);

            bigBang = createBigBangMarket(report.tapiocaMulticall, report.bigBangLauncher, bigBangRiskParams);
            console.log("BigBang:   ", bigBang);
            Usdo(payable(report.usdo)).setMinterStatus(bigBang, true);
            Usdo(payable(report.usdo)).setBurnerStatus(bigBang, true);
        }

        {
            TapiocaTestnetTobSetter tobSetter = new TapiocaTestnetTobSetter(
                report,
                singularity,
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
            console.log("TapiocaOptionBroker:   ", address(tob));

            TapToken(payable(input.tapToken)).setMinter(address(tob));

            tob.enableTapTokenRewards();
            tob.transferOwnership(report.tapiocaMulticall);

            address twTap = createTwTap(payable(input.tapToken), input.owner);
            console.log("TwTap:   ", address(twTap));
            
            TapToken(payable(input.tapToken)).setMinter(address(tob));

            // Mint and transfer mock tokens to multitokensender and deployer
            MultiTokenSender(report.multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);
            TapToken(payable(input.tapToken)).transfer(report.multiTokenSender, 20_000_000 ether);
            usdc.mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
            stETH.mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
            Usdo(payable(report.usdo)).mint(report.multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
            TapToken(payable(input.tapToken)).transfer(
                report.tapiocaMulticall, TapToken(payable(input.tapToken)).balanceOf(msg.sender) - 100000e18
            );

            // Add extra admins to the multicall contract
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(
                0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367, true
            );
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(
                0xB0ae5BCc7fE0848Ae9984e12ae57edFfCcc2F630, true
            );
            TapiocaMulticallTestnet(payable(report.tapiocaMulticall)).setOwner(
                0x4778c2AA94a8D05D63e4C07eb68021528985304C, true
            );

            (ITapiocaOracle oracle, bytes memory oracleData) = tob._paymentTokens(address(usdc));
            console.log("TOB payment oracle: ", address(oracle));
            console.log("TOB payment oracle data (might be empty): ");
            console.logBytes(oracleData);
            require(address(oracle) != address(0), "TOB payment oracle is not set");
        }
        Usdo(payable(report.usdo)).transferOwnership(report.tapiocaMulticall);

        address[] memory contracts = new address[](4);
        contracts[0] = bigBang;
        contracts[1] = singularity;
        contracts[2] = report.marketHelper;
        contracts[3] = report.usdo;
        _clusterUpdateContracts(report.tapiocaMulticall, report.cluster, contracts, true);
        vm.stopBroadcast();
    }

    function _clusterUpdateContracts(address multicall, address cluster, address[] memory contracts, bool isUpdate) internal {
        TapiocaMulticall.Call[] memory calls = new TapiocaMulticall.Call[](contracts.length);
        uint256 totalCalls = contracts.length;
        for (uint256 i = 0; i < totalCalls; i++) {
            calls[i] = TapiocaMulticall.Call({
                target: cluster,
                allowFailure: false,
                callData: abi.encodeWithSelector(ICluster.updateContract.selector, 0, contracts[i], isUpdate)
            });
        }

        TapiocaMulticall(payable(multicall)).multicall(calls);
    }

    function createSingularityMarket(
        address multicall,
        address launcher,
        address token,
        address usdo,
        address tokenOracle,
        RiskParams memory riskParams
    ) internal returns (address) {
        SGLInit._InitMemoryTokensData memory tokensData;

        tokensData._asset = IERC20(usdo);
        tokensData._collateral = IERC20(token);

        IERC20(usdo).approve(multicall, riskParams.seedAmount);

        bytes memory payload =
            abi.encodeWithSelector(SingularityLauncher.createSingularity.selector, tokensData, riskParams);
        bytes memory returnData = TapiocaMulticall(payable(multicall)).performDelegateCall(launcher, payload);

        address marketAddress = abi.decode(returnData, (address));
        return marketAddress;
    }

    function createBigBangMarket(address multicall, address launcher, BigBangRiskParams memory riskParams)
        internal
        returns (address)
    {
        bytes memory payload = abi.encodeWithSelector(BigBangLauncher.createBigBang.selector, riskParams);
        bytes memory returnData = TapiocaMulticall(payable(multicall)).performDelegateCall(launcher, payload);

        address bigBangAddress = abi.decode(returnData, (address));
        return bigBangAddress;
    }

    function createTwTap(address payable _tapOft, address _owner) internal returns (address) {
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = Bucket({
            enabled: true,
            lockEpochDuration: 2,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 50_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1000
        });
        return address(new TwTAP(_tapOft, _owner, 7 days, buckets));
    }

    function deployTestnetOracles(TapiocaInput memory input) internal returns (TestnetOracles memory oracles) {
        TestnetOraclesBatch oraclesBatch = new TestnetOraclesBatch();

        return oraclesBatch.getOraclesReport();
    }
}
