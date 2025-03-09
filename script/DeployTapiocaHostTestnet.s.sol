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

import "forge-std/console.sol";

contract DeployTapiocaHostTestnet is Script {
    uint256 public constant EPOCH_DURATION = 1 minutes;

    struct TestnetOracles {
        address stETHOracle;
        address usdoOracle;
        address usdcOracle;
        address tapOracle;
    }

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;

        // TapiocaRelease input params
        input.owner = msg.sender;
        input.lzChainId = 40161;
        input.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        input.isTestnet = true;

        // BigBang risk params
        BigBangRiskParams memory bigBangRiskParams;

        vm.startBroadcast();
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
        }

        {
            RiskParams memory singularityRiskParams;

            singularityRiskParams.borrowOpeningFee = 0;
            singularityRiskParams.liquidationMultiplier = 0;
            singularityRiskParams.minimumTargetUtilization = 0;
            singularityRiskParams.maximumTargetUtilization = 0;
            singularityRiskParams.minimumInterestPerSecond = 0;
            singularityRiskParams.maximumInterestPerSecond = 0;
            singularityRiskParams.interestElasticity = 0;
            singularityRiskParams.minLendAmount = 1e6;
            singularityRiskParams.exchangeRatePrecision = 0;
            singularityRiskParams.collateralizationRate = 75000;
            singularityRiskParams.liquidationCollateralizationRate = 80000;
            singularityRiskParams.oracle = oracles.usdoOracle;
            singularityRiskParams.seedAmount = 1 ether;

            createSingularityMarket(
                report.tapiocaMulticall,
                report.singularityLauncher,
                address(stETH),
                report.usdo,
                oracles.stETHOracle,
                singularityRiskParams
            );

            //createBigBangMarket(
            //    report.tapiocaMulticall, report.bigBangLauncher, input.wrappedNativeToken, bigBangRiskParams
            //);
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
        Singularity._InitMemoryTokensData memory tokensData;

        tokensData._asset = IERC20(usdo);
        tokensData._collateral = IERC20(token);

        bytes memory payload =
            abi.encodeWithSelector(SingularityLauncher.createSingularity.selector, tokensData, riskParams);

        bytes memory returnData = TapiocaMulticall(payable(multicall)).performDelegateCall(launcher, payload);

        address marketAddress = abi.decode(returnData, (address));
        return marketAddress;
    }

    function createBigBangMarket(
        address multicall,
        address launcher,
        address token,
        BigBangRiskParams memory riskParams
    ) internal returns (address) {
        bytes memory payload = abi.encodeWithSelector(BigBangLauncher.createBigBang.selector, token);
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
        TestnetOracle stETHOracle = new TestnetOracle("stETH/USD", "TAP/USD", 2000e8, input.owner);
        TestnetOracle tapOracle = new TestnetOracle("TAP/USD", "TAP/USD", 10e8, input.owner);
        TestnetOracle usdoOracle = new TestnetOracle("USDO/USD", "USDO/USD", 1e8, input.owner);
        TestnetOracle usdcOracle = new TestnetOracle("USDC/USD", "USDO/USD", 1e8, input.owner);

        return TestnetOracles({
            stETHOracle: address(stETHOracle),
            usdoOracle: address(usdoOracle),
            usdcOracle: address(usdcOracle),
            tapOracle: address(tapOracle)
        });
    }
}
