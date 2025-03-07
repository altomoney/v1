// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";
import {SingularityLauncher, RiskParams} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {BigBangLauncher, BigBangRiskParams} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {Script} from "forge-std/Script.sol";
import {TapToken} from "contracts/tap-token/tokens/TapToken.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {TapTokenSender} from "contracts/tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "contracts/tap-token/tokens/TapTokenReceiver.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {TwTAP} from "tap-token/governance/twTap.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";

contract DeployTapiocaHostTestnet is Script {
    uint256 public constant EPOCH_DURATION = 1 minutes;

    function run() public {
        TapiocaInput memory input;
        TapiocaReport memory report;
        TapiocaReport memory prevReport;

        // TapiocaRelease input params
        input.owner = msg.sender;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new WETH());
        input.isTestnet = true;

        // Singularity risk params
        RiskParams memory singularityRiskParams;

        // BigBang risk params
        BigBangRiskParams memory bigBangRiskParams;

        vm.startBroadcast();

        input.tapToken = address(
            new TapToken(
                ITapToken.TapTokenConstructorData(
                    EPOCH_DURATION,
                    input.lzEndpoint,
                    contributors,
                    earlySupporters,
                    supporters,
                    lbp,
                    dao,
                    airdrop,
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

        input.tapToken.setCluster(report.cluster);
        input.tapToken.setToeExtExec(report.extExec);

        // Markets
        address singularityOne =
            createSingularityMarket(multicall, report.singularityLauncher, input.wrappedNativeToken, report.usdo);
        address bigBangOne = createBigBangMarket(multicall, report.bigBangLauncher, weth);

        // TapiocaOptionBroker (pending batch)
        tob = new TapiocaOptionBroker(
            payable(tapToken), address(report.usdo), dao, EPOCH_DURATION, buckets, report.penrose, owner
        );

        tob.setPaymentToken(address(paymentToken), paymentTokenOracle, "");
        tob.setPaymentTokenBeneficiary(dao);
        tob.setTapOracle(tapOracle, "");
        tob.setCluster(report.cluster);
        tob.setPenrose(report.penrose);

        tapToken.setMinter(address(tob));
        vm.stopPrank();

        vm.startPrank(tob.owner());
        tob.enableTapTokenRewards();

        // TWTap (pending batch)

        twTap = createTwTap(payable(tapOFT), adminAddr);

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

        bytes memory returnData = TapiocaMulticall(multicall).performDelegateCall(launcher, payload);

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
        bytes memory returnData = TapiocaMulticall(multicall).performDelegateCall(launcher, payload);

        address bigBangAddress = abi.decode(returnData, (address));
        return bigBangAddress;
    }
}
