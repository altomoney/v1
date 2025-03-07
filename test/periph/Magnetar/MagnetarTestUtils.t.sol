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
import {TapToken} from "../../../contracts/tap-token/tokens/TapToken.sol";
import {TwTAP} from "../../../contracts/tap-token/governance/TwTAP.sol";
import {TapTokenMock} from "../../tap-token/TapTokenMock.sol";
import {ITapToken} from "../../../contracts/tap-token/tokens/ITapToken.sol";
import {Bucket} from "../../../contracts/tap-token/interfaces/ITWLBase.sol";
import {TapTokenSender} from "../../../contracts/tap-token/tokens/TapTokenSender.sol";
import {TapTokenReceiver} from "../../../contracts/tap-token/tokens/TapTokenReceiver.sol";
import {UnitBaseTest} from "../../tap-token/unit/UnitBaseTest.t.sol";
import {TapiocaOptionBroker} from "../../../contracts/tap-token/options/TapiocaOptionBroker.sol";
import {TapiocaOmnichainExtExec} from
    "../../../contracts/utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {IMarket} from "../../../contracts/utils/interfaces/bar/IMarket.sol";
import {ZeroXSwapperMock} from "../../../contracts/mocks/ZeroXSwapperMock.sol";

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

abstract contract MagnetarTestUtils is TestHelper {
    uint256 internal constant EPOCH_DURATION = 7 days;
    address internal constant TAP_CONTRIBUTOR = address(bytes20(keccak256("TAP_CONTRIBUTOR")));
    address internal constant TAP_EARLY_SUPPORTERS = address(bytes20(keccak256("TAP_EARLY_SUPPORTERS")));
    address internal constant TAP_SUPPORTERS = address(bytes20(keccak256("TAP_SUPPORTERS")));
    address internal constant TAP_LBP = address(bytes20(keccak256("TAP_LBP")));
    address internal constant TAP_DAO = address(bytes20(keccak256("TAP_DAO")));
    address internal constant TAP_AIRDROP = address(bytes20(keccak256("TAP_AIRDROP")));
    uint32 public EID_A = 1;
    address public ENDPOINT_A;

    TapiocaInput internal input;
    TapiocaReport internal report;
    SingularityLauncher internal singularityLauncher;
    BigBangLauncher internal bigBangLauncher;
    TwTAP internal twTap;
    TapiocaOptionBroker internal tob;
    Bucket[] internal buckets;

    uint32 aEid = 1;
    uint32 bEid = 2;

    address __endpoint;
    uint256 __hostEid = aEid;
    address __owner = address(this);
    address __admin = vm.addr(12345678901234567890);

    function setUp() public virtual override {
        setUpEndpoints(3, LibraryType.UltraLightNode);
        ENDPOINT_A = address(endpoints[EID_A]);

        input.owner = __owner;
        input.lzChainId = uint16(aEid);

        input.wrappedNativeToken = address(new ERC20Mock());
        input.tapToken = _createTapToken(
            UnitBaseTest.TapOftInput(
                EPOCH_DURATION,
                ENDPOINT_A,
                TAP_CONTRIBUTOR,
                TAP_EARLY_SUPPORTERS,
                TAP_SUPPORTERS,
                TAP_LBP,
                TAP_DAO,
                TAP_AIRDROP,
                EID_A,
                __admin
            )
        );
        input.zeroXSwapper = address(new ZeroXSwapperMock(ICluster(address(0x0)), __admin));
        input.lzEndpoint = address(endpoints[aEid]);
        __endpoint = address(endpoints[aEid]);

        TapiocaReport memory emptyReport;
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        vm.startPrank(__admin);
        ZeroXSwapperMock(payable(input.zeroXSwapper)).setCluster(ICluster(report.cluster));
        TapTokenMock(payable(input.tapToken)).setCluster(ICluster(report.cluster));
        vm.stopPrank();

        twTap = _createTwTap(payable(input.tapToken), __admin);
        tob = _createTapiocaOptionBroker(input.tapToken, address(report.usdo), report.penrose, __admin, TAP_DAO);
        vm.prank(__admin);
        TapToken(payable(input.tapToken)).setTwTAP(address(twTap));

        TapiocaMulticall.Call[] memory clusterUpdateTwTapCalls = new TapiocaMulticall.Call[](1);
        clusterUpdateTwTapCalls[0] = TapiocaMulticall.Call({
            target: address(report.cluster),
            allowFailure: false,
            callData: abi.encodeWithSelector(ICluster.updateContract.selector, aEid, address(twTap), true)
        });

        vm.startPrank(TapiocaMulticall(report.tapiocaMulticall).owner());
        TapiocaMulticall multicall = TapiocaMulticall(report.tapiocaMulticall);
        multicall.multicall(clusterUpdateTwTapCalls);
        vm.stopPrank();
    }

    function _createTapToken(UnitBaseTest.TapOftInput memory _input) internal returns (address) {
        TapTokenMock tapToken = new TapTokenMock(
            ITapToken.TapTokenConstructorData(
                _input._epochDuration,
                _input._endpoint,
                _input._contributor,
                _input._earlySupporters,
                _input._supporters,
                _input._lbp,
                _input._dao,
                _input._airdrop,
                _input._governanceEid,
                _input._owner,
                address(new TapTokenSender("", "", _input._endpoint, _input._owner, address(0))),
                address(new TapTokenReceiver("", "", _input._endpoint, _input._owner, address(0))),
                address(new TapiocaOmnichainExtExec()),
                ICluster(address(0x0))
            )
        );
        vm.label(address(tapToken), "tapToken");
        return address(tapToken);
    }

    function _createTapiocaOptionBroker(
        address _tapToken,
        address _usdo,
        address _penrose,
        address _owner,
        address _dao
    ) internal returns (TapiocaOptionBroker) {
        TapiocaOptionBroker _tob =
            new TapiocaOptionBroker(payable(_tapToken), _usdo, _dao, EPOCH_DURATION, buckets, _penrose, _owner);

        vm.label(address(_tob), "tob");
        return _tob;
    }

    function _createTwTap(address payable _tapOft, address _owner) internal returns (TwTAP) {
        buckets.push(Bucket({
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
        }));
        TwTAP _twTap = new TwTAP(_tapOft, _owner, 7 days, buckets);
        vm.label(address(_twTap), "twTap");
        return _twTap;
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

    function _assertSingularityLiquidityBalanceUser(address payable _market, address _user, uint256 _amount) internal {
        IERC20 _asset = IERC20(IMarket(_market)._asset());
        assertEq(Singularity(_market).liquidityBalance(_user), _amount, "Invalid user liquidity balance");
<<<<<<< HEAD
=======
    }

    function _assertSingularityLiquidityBalanceMarket(address payable _market, uint256 _amount) internal {
        IERC20 _asset = IERC20(IMarket(_market)._asset());
        assertEq(_asset.balanceOf(address(_market)), _amount, "Invalid market asset balance");
>>>>>>> de59fe4 (feat: add tob actions to magnetar)
    }

    function _assertBigBangUser(address _market, address _user, uint256 _collateralAmount, uint256 _borrowAmount) internal {
        IERC20 _collateral = IERC20(IMarket(_market).asset());
        BigBang _bb = BigBang(payable(_market));

        assertEq(_bb.balanceOf(_user), _collateralAmount, "Invalid user market shares balance");
        assertEq(_bb._userBorrowPart(_user), _borrowAmount, "Invalid user borrow part");
        assertEq(_bb._totalCollateralShare(), _collateralAmount, "Invalid total collateral share");
    }

    function _assertBigBangMarket(address _market, uint256 _marketCollateralBalance, uint256 _marketTotalColalteralShare) internal {
        IERC20 _collateral = IERC20(IMarket(_market).asset());
        BigBang _bb = BigBang(payable(_market));

        assertEq(_collateral.balanceOf(address(_market)), _marketCollateralBalance, "Invalid market collateral balance");
        assertEq(_bb._totalCollateralShare(), _marketTotalColalteralShare, "Invalid market total collateral share");
    }
}
