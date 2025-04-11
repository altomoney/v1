// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {BigBangLauncher} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {BigBangRiskParams} from "deployments/interfaces/IBigBangLauncher.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {OracleMock} from "../bar/mocks/OracleMock.sol";
import {UsdoTestHelper, TestPenroseData, TestSingularityData} from "../bar/helpers/UsdoTestHelper.t.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TapiocaMulticall} from "contracts/utils/TapiocaMulticall/TapiocaMulticall.sol";

contract BigBangLauncherTests is Test {
    address owner;

    TapiocaInput input;
    TapiocaReport report;

    BigBangLauncher bigBangLauncher;

    ERC20Mock usda;

    function setUp() public {
        owner = address(this);
        TapiocaReport memory emptyReport;
        input.owner = owner;
        input.lzChainId = 0;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));
        input.bbMarketBorrowCap = 3_000_000e18;

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXProxy = address(1);
        usda = new ERC20Mock("USDA", "USDA");
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        bigBangLauncher = new BigBangLauncher(
            report.bbLiquidation,
            report.bbBorrow,
            report.bbCollateral,
            report.bbLeverage,
            report.penrose,
            report.simpleLeverageExecutor,
            report.bigbang,
            report.bbDebtRateHelper,
            input.bbMarketBorrowCap
        );
    }

    function test_launchBigBangMarket() public returns (BigBang bigbang) {
        BigBangRiskParams memory riskParams;

        riskParams.debtRateAgainstEth;
        riskParams.debtRateMin;
        riskParams.debtRateMax;
        riskParams.exchangeRatePrecision;
        riskParams.collateralizationRate;
        riskParams.liquidationCollateralizationRate;
        riskParams.collateral = input.wrappedNativeToken;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.isEthMarket = true;

        bytes memory payload = abi.encodeWithSelector(bigBangLauncher.createBigBang.selector, riskParams);

        vm.prank(owner);
        bytes memory returnData =
            TapiocaMulticall(payable(report.tapiocaMulticall)).performDelegateCall(address(bigBangLauncher), payload);
        address payable marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Big Bang market address should not be zero");
        bigbang = BigBang(marketAddress);
    }
}
