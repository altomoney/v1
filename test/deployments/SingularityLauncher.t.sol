// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {SingularityLauncher} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import {RiskParams} from "deployments/interfaces/ISingularityLauncher.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {OracleMock} from "../bar/mocks/OracleMock.sol";
import {UsdoTestHelper, TestPenroseData, TestSingularityData} from "../bar/helpers/UsdoTestHelper.t.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";

contract TapiocaReleaseTest is Test {
    address owner;

    TapiocaInput input;
    TapiocaReport report;

    SingularityLauncher singularityLauncher;

    ERC20Mock usda;

    function setUp() public {
        owner = address(this);
        TapiocaReport memory emptyReport;
        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);
        usda = new ERC20Mock("USDA", "USDA");
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);
        singularityLauncher = new SingularityLauncher(
            report.sglLiquidationModule,
            report.sglBorrowModule,
            report.sglCollateralModule,
            report.sglLeverageModule,
            report.sglInit,
            report.penrose,
            report.simpleLeverageExecutor,
            report.sglInterestHelper,
            report.singularity
        );
    }

    function test_launchSingularityMarket() public returns (Singularity singularity) {
        SGLInit._InitMemoryTokensData memory tokensData;
        RiskParams memory riskParams;

        tokensData._collateral = IERC20(input.wrappedNativeToken);
        tokensData._asset = IERC20(address(usda));

        riskParams.borrowOpeningFee = 0;
        riskParams.liquidationMultiplier = 0;
        riskParams.minimumTargetUtilization = 0;
        riskParams.maximumTargetUtilization = 0;
        riskParams.minimumInterestPerSecond = 0;
        riskParams.maximumInterestPerSecond = 0;
        riskParams.interestElasticity = 0;
        riskParams.minLendAmount = 0;
        riskParams.exchangeRatePrecision = 0;
        riskParams.collateralizationRate = 0;
        riskParams.liquidationCollateralizationRate = 0;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.seedAmount = 1 ether;

        deal(input.wrappedNativeToken, address(this), 1 ether);
        bytes memory payload =
            abi.encodeWithSelector(singularityLauncher.createSingularity.selector, tokensData, riskParams);

        vm.prank(owner);
        bytes memory returnData = TapiocaMulticall(payable(report.tapiocaMulticall)).performDelegateCall(
            address(singularityLauncher), payload
        );
        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Singularity market address should not be zero");
    }
}
