// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TapiocaReport, TapiocaInput} from "deployments/interfaces/ITapiocaReport.sol";
import {ERC20Mock} from "tap-token/mocks/ERC20Mock.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {SingularityLauncher} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {IPearlmit} from "tap-utils/interfaces/periph/IPearlmit.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TapTokenSender} from "tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "tap-token/tokens/TapTokenReceiver.sol";
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {Bucket} from "tap-token/governance/TWLBase.sol";

contract TOBTestBase is Test {
    address owner;
    Cluster cluster;
    TapToken tapToken;
    TapiocaOptionBroker tob;
    Singularity singularity;
    SingularityLauncher singularityLauncher;

    TapiocaInput input;
    TapiocaReport report;

    uint256 EPOCH_DURATION = 1 weeks;

    address contributors;
    address earlySupporters;
    address supporters;
    address lbp;
    address dao;
    address airdrop;

    ERC20Mock sUSDX;
    ERC20Mock sWETH;
    ERC20Mock usdo;

    Bucket[] buckets;

    function setUp() public {
        deployDependencies();

        buckets.push(
            Bucket({
                enabled: true,
                epochGrowthRate: 1,
                epochDecayRate: 1,
                epochCeiling: 10,
                epochFloor: 1,
                rewardsMultiplier: 5000,
                lockEpochDuration: 1,
                currentEpochInflows: 0,
                lastEpochInflows: 0,
                growthGoal: 1000e18
            })
        );

        tob = new TapiocaOptionBroker(payable(tapToken), address(usdo), dao, EPOCH_DURATION, buckets, owner);
    }

    function deployDependencies() internal {
        contributors = makeAddr("contributors");
        earlySupporters = makeAddr("earlySupporters");
        supporters = makeAddr("supporters");
        lbp = makeAddr("lbp");
        dao = makeAddr("dao");
        airdrop = makeAddr("airdrop");
        owner = makeAddr("multisig");
        sUSDX = new ERC20Mock("sUSDX", "sUSDX");
        sWETH = new ERC20Mock("sWETH", "sWETH");
        usdo = new ERC20Mock("USDO", "USDO");
        TapiocaReport memory emptyReport;

        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);

        tapToken = new TapToken(
            ITapToken.TapTokenConstructorData(
                EPOCH_DURATION,
                input.lzEndpoint,
                contributors,
                earlySupporters,
                supporters,
                lbp,
                dao,
                airdrop,
                0,
                owner,
                address(new TapTokenSender("", "", input.lzEndpoint, owner, address(0))),
                address(new TapTokenReceiver("", "", input.lzEndpoint, owner, address(0))),
                address(address(0)),
                IPearlmit(address(0)),
                ICluster(address(0))
            )
        );
        vm.label(address(tapToken), "TapToken");
        vm.label(address(sUSDX), "sUSDX");
        vm.label(address(usdo), "USDO");
        input.tapToken = address(tapToken);

        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        vm.startPrank(owner);
        tapToken.setPearlmit(IPearlmit(report.pearlmit));
        tapToken.setCluster(ICluster(report.cluster));
        vm.stopPrank();
    }
}
