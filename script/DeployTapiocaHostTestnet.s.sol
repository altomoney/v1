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

contract DeployTapiocaHostTestnet is Script {
    uint256 public constant EPOCH_DURATION = 1 minutes;

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;
        TapiocaReport memory prevReport;

        // TapiocaRelease input params
        input.owner = msg.sender;
        input.lzChainId = 1;
        input.wrappedNativeToken = address(new WETH());
        input.isTestnet = true;

        // Singularity risk params
        RiskParams memory singularityRiskParams;

        // BigBang risk params
        BigBangRiskParams memory bigBangRiskParams;

        vm.startBroadcast();
        // create ARB to USD and USDC to USD oracles
        address[] memory guardians = new address[](1);
        guardians[0] = input.owner;

        SeerCLSolo stETHOracle = new SeerCLSolo(
            "CL stETH/USD",
            "stETH/USD",
            8,
            OracleChainlinkSingleConstructorData({
                _poolChainlink: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD Pool
                _isChainlinkMultiplied: uint8(1), // Multiply/divide Uni
                _inBase: 1e8,
                stalePeriod: uint32(86400),
                guardians: guardians,
                _description: bytes32("ETH/USD"),
                _sequencerUptimeFeed: address(0),
                _admin: input.owner
            })
        );
        TestnetOracle tapOracle = new TestnetOracle("TAP/USD", "TAP/USD", 10e8, input.owner);
        TestnetOracle usdoOracle = new TestnetOracle("USDO/USD", "USDO/USD", 1e8, input.owner);

        input.tapToken = address(
            new TapToken(
                ITapToken.TapTokenConstructorData(
                    EPOCH_DURATION,
                    input.lzEndpoint,
                    report.tapiocaMulticall,
                    report.tapiocaMulticall,
                    report.tapiocaMulticall,
                    report.tapiocaMulticall,
                    report.tapiocaMulticall,
                    report.tapiocaMulticall,
                    block.chainid,
                    input.owner,
                    address(new TapTokenSender("", "", input.lzEndpoint, input.owner, address(0))),
                    address(new TapTokenReceiver("", "", input.lzEndpoint, input.owner, address(0))),
                    address(0),
                    ICluster(address(1))
                )
            )
        );

        report = TapiocaRelease.deployTapiocaV1(input, prevReport);

        TapToken(payable(input.tapToken)).setCluster(ICluster(report.cluster));
        TapToken(payable(input.tapToken)).setToeExtExec(report.extExec);

        // Markets
        address singularityOne = createSingularityMarket(
            report.tapiocaMulticall,
            address(0), /*report.singularityLauncher,*/
            input.wrappedNativeToken,
            report.usdo,
            singularityRiskParams
        );
        address bigBangOne = createBigBangMarket(
            report.tapiocaMulticall, address(0), /*report.bigBangLauncher,*/ input.wrappedNativeToken, bigBangRiskParams
        );

        address tob = createTapiocaOptionBroker(
            report,
            input.tapToken,
            report.usdo,
            report.tapiocaMulticall,
            input.owner,
            input.wrappedNativeToken,
            address(tapOracle),
            EPOCH_DURATION
        );
        createTwTap(payable(input.tapToken), input.owner);

        TapToken(payable(input.tapToken)).setMinter(address(tob));

        vm.stopBroadcast();
    }

    function createSingularityMarket(
        address multicall,
        address launcher,
        address token,
        address usdo,
        RiskParams memory riskParams
    ) internal returns (address) {
        Singularity._InitMemoryTokensData memory tokensData;
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
            payable(tapToken), address(report.usdo), feeCollector, epochDuration, buckets, report.penrose, owner
        );

        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(feeCollector);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(report.cluster);
        tob.setPenrose(report.penrose);

        tob.enableTapTokenRewards();

        return address(tob);
    }
}
