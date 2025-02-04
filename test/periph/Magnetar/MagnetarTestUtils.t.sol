// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

import {Penrose} from "tapioca-bar/Penrose.sol";

import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";

import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";

import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {ZerroXSwapperMockTarget} from "../../utils//ZeroXSwapper/ZerroXSwapperMockTarget.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";
import {SingularityMock} from "../mocks/SingularityMock.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {SingularityLauncher} from "deployments/releases/tapioca-v1/actions/SingularityLauncher.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {RiskParams} from "deployments/interfaces/ISingularityLauncher.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {TestHelper} from "test/bar/LZSetup/TestHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TapiocaMulticall} from "tap-utils/TapiocaMulticall/TapiocaMulticall.sol";
import {BigBangLauncher, BigBangRiskParams} from "deployments/releases/tapioca-v1/actions/BigBangLauncher.sol";
import {OracleMock} from "test/utils/mocks/OracleMock.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {IBigBang} from "tap-utils/interfaces/bar/IBigBang.sol";

struct TestSingularityData {
    address penrose;
    address asset;
    address collateral;
    ITapiocaOracle oracle;
    ILeverageExecutor leverageExecutor;
}

struct TestBigBangData {
    address penrose;
    address collateral;
    ITapiocaOracle oracle;
    ILeverageExecutor leverageExecutor;
    uint256 debtRateAgainstEth;
    uint256 debtRateMin;
    uint256 debtRateMax;
}

contract MagnetarTestUtils is TestHelper {
    TapiocaInput internal input;
    TapiocaReport internal report;
    SingularityLauncher internal singularityLauncher;
    BigBangLauncher internal bigBangLauncher;

    uint32 aEid = 1;
    uint32 bEid = 2;

    address __endpoint;
    uint256 __hostEid = aEid;
    address __owner = address(this);

    function setUp() public virtual override {
        setUpEndpoints(3, LibraryType.UltraLightNode);

        input.owner = __owner;
        input.lzChainId = uint16(aEid);

        input.wrappedNativeToken = address(new ERC20Mock());
        input.tapToken = address(new ERC20Mock());
        input.zeroXSwapper = address(1);
        input.lzEndpoint = address(endpoints[aEid]);
        __endpoint = address(endpoints[aEid]);

        TapiocaReport memory emptyReport;
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);
    }

    function launchSingularity(TapiocaReport memory reportOut, address asset, address collateral, address oracle)
        public
        returns (ISingularity singularity)
    {
        Singularity._InitMemoryTokensData memory tokensData;
        RiskParams memory riskParams;

        tokensData._asset = IERC20(asset);
        tokensData._collateral = IERC20(collateral);

        riskParams.oracle = oracle;
        riskParams.seedAmount = 1 ether;

        singularityLauncher = new SingularityLauncher(
            reportOut.sglLiquidationModule,
            reportOut.sglBorrowModule,
            reportOut.sglCollateralModule,
            reportOut.sglLeverageModule,
            reportOut.sglInit,
            reportOut.penrose,
            reportOut.simpleLeverageExecutor,
            reportOut.sglInterestHelper,
            reportOut.singularity
        );
        address admin = Ownable(reportOut.tapiocaMulticall).owner();

        deal(collateral, admin, 1 ether);

        bytes memory payload =
            abi.encodeWithSelector(singularityLauncher.createSingularity.selector, tokensData, riskParams);

        vm.startPrank(admin);
        bytes memory returnData =
            TapiocaMulticall(reportOut.tapiocaMulticall).performDelegateCall(address(singularityLauncher), payload);
        vm.stopPrank();

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "Singularity market address should not be zero");
        return ISingularity(marketAddress);
    }

    function launchBigBang(TapiocaReport memory reportOut, address collateral) internal returns (IBigBang) {
        bigBangLauncher = new BigBangLauncher(
            reportOut.bbLiquidation,
            reportOut.bbBorrow,
            reportOut.bbCollateral,
            reportOut.bbLeverage,
            reportOut.penrose,
            reportOut.simpleLeverageExecutor,
            reportOut.bigbang,
            reportOut.bbDebtRateHelper
        );

        BigBangRiskParams memory riskParams;
        riskParams.debtRateAgainstEth = 0;
        riskParams.debtRateMin = 0;
        riskParams.debtRateMax = 0;
        riskParams.exchangeRatePrecision = 1e18;
        riskParams.collateralizationRate = 75000;
        riskParams.liquidationCollateralizationRate = 80000;
        riskParams.collateral = collateral;
        riskParams.oracle = address(new OracleMock("Oracle Test", "ORCT", 1 ether));
        riskParams.seedAmount = 1 ether;
        riskParams.isEthMarket = true;

        address admin = Ownable(reportOut.tapiocaMulticall).owner();

        deal(collateral, admin, 1 ether);
        bytes memory payload = abi.encodeWithSelector(bigBangLauncher.createBigBang.selector, riskParams);

        vm.startPrank(admin);
        bytes memory returnData =
            TapiocaMulticall(reportOut.tapiocaMulticall).performDelegateCall(address(bigBangLauncher), payload);
        vm.stopPrank();

        address marketAddress = abi.decode(returnData, (address));
        assertTrue(marketAddress != address(0), "BigBang market address should not be zero");

        Usdo usdo = Usdo(payable(report.usdo));

        vm.startPrank(admin);
        usdo.setMinterStatus(marketAddress, true);
        usdo.setBurnerStatus(marketAddress, true);
        vm.stopPrank();

        return IBigBang(payable(marketAddress));
    }

    function setBBEthMarket(Penrose penrose, address market) external {
        penrose.setBigBangEthMarket(market);
    }

    function createPenrose(ICluster _cluster, address tapToken_, address mainToken_)
        external
        returns (Penrose penrose, Singularity mediumRiskMC, BigBang bbMediumRiskMC)
    {
        penrose = new Penrose(_cluster, IERC20(tapToken_), IERC20(mainToken_), address(this));
        mediumRiskMC = new Singularity();
        bbMediumRiskMC = new BigBang();

        penrose.registerSingularityMasterContract(address(mediumRiskMC), IPenrose.ContractType.mediumRisk);
        penrose.registerBigBangMasterContract(address(bbMediumRiskMC), IPenrose.ContractType.mediumRisk);
    }

    function setAssetOracle(Penrose penrose, BigBang bb, address oracle) external {
        // function executeMarketFn(address[] calldata mc, bytes[] memory data, bool forceSuccess)
        address[] memory markets = new address[](1);
        markets[0] = address(bb);
        bytes[] memory marketsData = new bytes[](1);
        marketsData[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, oracle, "0x");

        penrose.executeMarketFn(markets, marketsData, true);
    }

    function createBigBang(TestBigBangData memory _bb, address _mc) public returns (BigBang) {
        BigBang bb = new BigBang();

        (
            BigBang._InitMemoryModulesData memory initModulesData,
            BigBang._InitMemoryDebtData memory initDebtData,
            BigBang._InitMemoryData memory initMemoryData
        ) = _getBigBangInitData(_bb);

        {
            bb.init(abi.encode(initModulesData, initDebtData, initMemoryData));
        }

        {
            Penrose(_bb.penrose).addBigBang(_mc, address(bb));
        }

        BBDebtRateHelper helper = new BBDebtRateHelper();
        address[] memory markets = new address[](1);
        markets[0] = address(bb);
        bytes[] memory marketsData = new bytes[](1);
        BBDebtRateHelper bbRateHelper = new BBDebtRateHelper();
        marketsData[0] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, address(bbRateHelper));
        Penrose(_bb.penrose).executeMarketFn(markets, marketsData, true);

        return bb;
    }

    function _getBigBangInitData(TestBigBangData memory _bb)
        private
        returns (
            BigBang._InitMemoryModulesData memory modulesData,
            BigBang._InitMemoryDebtData memory debtData,
            BigBang._InitMemoryData memory data
        )
    {
        BBLiquidation bbLiq = new BBLiquidation();
        BBBorrow bbBorrow = new BBBorrow();
        BBCollateral bbCollateral = new BBCollateral();
        BBLeverage bbLev = new BBLeverage();

        modulesData =
            BigBang._InitMemoryModulesData(address(bbLiq), address(bbBorrow), address(bbCollateral), address(bbLev));

        debtData = BigBang._InitMemoryDebtData(_bb.debtRateAgainstEth, _bb.debtRateMin, _bb.debtRateMax);

        data = BigBang._InitMemoryData(
            IPenrose(_bb.penrose),
            IERC20(_bb.collateral),
            ITapiocaOracle(address(_bb.oracle)),
            0,
            75000,
            80000,
            _bb.leverageExecutor
        );
    }

    function _getSingularityInitData(TestSingularityData memory _sgl)
        private
        returns (
            Singularity._InitMemoryModulesData memory modulesData,
            Singularity._InitMemoryTokensData memory tokensData,
            Singularity._InitMemoryData memory data
        )
    {
        SGLLiquidation sglLiq = new SGLLiquidation();
        SGLBorrow sglBorrow = new SGLBorrow();
        SGLCollateral sglCollateral = new SGLCollateral();
        SGLLeverage sglLev = new SGLLeverage();

        modulesData = Singularity._InitMemoryModulesData(
            address(sglLiq), address(sglBorrow), address(sglCollateral), address(sglLev)
        );

        tokensData = Singularity._InitMemoryTokensData(IERC20(_sgl.asset), IERC20(_sgl.collateral));

        data = Singularity._InitMemoryData(
            IPenrose(_sgl.penrose), ITapiocaOracle(address(_sgl.oracle)), 0, 75000, 80000, _sgl.leverageExecutor
        );
    }
}
