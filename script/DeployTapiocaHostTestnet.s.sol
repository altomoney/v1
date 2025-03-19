// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

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
import {
    TestnetOracles,
    TestnetOraclesBatch
} from "contracts/deployments/releases/tapioca-v1/batches/testnet/TestnetOraclesBatch.sol";
import "forge-std/console.sol";

contract DeployTapiocaHostTestnet is Script {
    uint256 public constant EPOCH_DURATION = 1 minutes;

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;

        vm.startBroadcast();
        // TapiocaRelease input params
        input.lzChainId = 40217;
        input.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        input.isTestnet = true;
        input.owner = msg.sender;

        // BigBang risk params
        BigBangRiskParams memory bigBangRiskParams;

        input.wrappedNativeToken = address(new WETH());

        ERC20Testnet stETH = new ERC20Testnet("stETH", 18, input.owner);
        ERC20Testnet usdc = new ERC20Testnet("USDC", 6, input.owner);

        input.tapToken = address(
            new TapToken(
                ITapToken.TapTokenConstructorData(
                    EPOCH_DURATION,
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

        report = TapiocaRelease.deployTapiocaV1(input, report);

        {
            TapToken(payable(input.tapToken)).setCluster(ICluster(report.cluster));
            TapToken(payable(input.tapToken)).setToeExtExec(report.extExec);
            Usdo(payable(report.usdo)).setMinterStatus(address(input.owner), true);
            Usdo(payable(report.usdo)).mint(input.owner, 1000000 ether);
        }

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

            createSingularityMarket(
                report.tapiocaMulticall,
                report.singularityLauncher,
                address(stETH),
                report.usdo,
                oracles.stETHOracle,
                singularityRiskParams
            );

            singularityRiskParams.oracle = oracles.usdcOracle;

            createSingularityMarket(
                report.tapiocaMulticall,
                report.singularityLauncher,
                address(usdc),
                report.usdo,
                oracles.usdcOracle,
                singularityRiskParams
            );
        }
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

            createBigBangMarket(report.tapiocaMulticall, report.bigBangLauncher, bigBangRiskParams);
        }

        {
            address tob = createTapiocaOptionBroker(
                report,
                input.tapToken,
                report.tapiocaMulticall,
                report.tapiocaMulticall,
                address(usdc),
                oracles.usdcOracle,
                oracles.tapOracle,
                EPOCH_DURATION
            );

            createTwTap(payable(input.tapToken), input.owner);

            TapToken(payable(input.tapToken)).setMinter(address(tob));

            // Mint and transfer mock tokens to multitokensender and deployer
            TapToken(payable(input.tapToken)).transfer(report.multiTokenSender, 1000000 ether);
            usdc.mint(report.multiTokenSender, 1000000 ether);
            stETH.mint(report.multiTokenSender, 1000000 ether);
            TapToken(payable(input.tapToken)).transfer(
                report.tapiocaMulticall, TapToken(payable(input.tapToken)).balanceOf(msg.sender) - 100000e18
            );
        }
        vm.stopBroadcast();
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

    function createTapiocaOptionBroker(
        TapiocaReport memory report,
        address tapToken,
        address feeCollector,
        address owner,
        address paymentToken,
        address paymentTokenOracle,
        address tapOracle,
        uint256 epochDuration
    ) internal returns (address) {
        Bucket[] memory buckets = new Bucket[](1);

        buckets[0] = Bucket({
            enabled: true,
            lockEpochDuration: 4,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 100,
            epochFloor: 1,
            rewardsMultiplier: 50_00,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 10 ether
        });

        TapiocaOptionBroker tob = new TapiocaOptionBroker(
            payable(tapToken), address(report.usdo), feeCollector, epochDuration, buckets, report.penrose, msg.sender
        );

        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(feeCollector);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(report.cluster);
        tob.setPenrose(report.penrose);

        TapToken(payable(tapToken)).setMinter(address(tob));

        tob.enableTapTokenRewards();

        tob.transferOwnership(owner);

        return address(tob);
    }

    function deployTestnetOracles(TapiocaInput memory input) internal returns (TestnetOracles memory oracles) {
        TestnetOraclesBatch oraclesBatch = new TestnetOraclesBatch();

        return oraclesBatch.getOraclesReport();
    }
}
