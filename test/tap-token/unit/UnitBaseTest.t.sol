// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/**
 * External
 */
import {IERC20 as BoringIERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

/**
 * Tap Token core contracts
 */
import {TapiocaOptionBroker} from "tap-token/options/TapiocaOptionBroker.sol";
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {TwTAP} from "tap-token/governance/twTAP.sol";
import {ITWLBase} from "tap-token/interfaces/ITWLBase.sol";

/**
 * Utils contracts
 */
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {Module as BBModule} from "tap-utils/interfaces/bar/IMarket.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";

import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {Bucket} from "tap-token/interfaces/ITWLBase.sol";

/**
 * Mocks
 */
import {ZeroXSwapperMock} from "tapioca-mocks/ZeroXSwapperMock.sol";
import {OracleMock} from "tapioca-mocks/OracleMock.sol";
import {ERC20Mock} from "tapioca-mocks/ERC20Mock.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";

/**
 * Tests
 */
import {TestHelper} from "test/bar/LZSetup/TestHelper.sol";
import {TapTokenMock} from "../TapTokenMock.sol";
import "forge-std/Test.sol";

contract UnitBaseTest is TestHelper {
    /**
     * Users
     */
    uint256 internal adminPKey = 0x1;
    address public adminAddr = vm.addr(adminPKey);
    uint256 internal alicePKey = 0x2;
    address public aliceAddr = vm.addr(alicePKey);
    uint256 internal bobPKey = 0x3;
    address public bobAddr = vm.addr(bobPKey);

    /**
     * Peripheral contracts
     */
    Cluster public cluster;

    /**
     * Bar contracts
     */
    // Mock tokens
    address public tapMockPenrose;
    address public ethTokenPenrose;
    address public ethTokenPenroseStrat;
    Usdo public usdoMock;

    // main contracts
    Penrose public penrose;
    BigBang public bigBangMasterContract;
    BigBang public bigBangEthMarket;
    Singularity public singularityMasterContract;
    Singularity public singularityEthMarket;

    // misc
    MarketHelper public marketHelper;
    ITapiocaOracle public bigBangEthOracle;
    uint256 public ethTokenPenroseId;
    uint256 singularityEthMarketAssetId = 1;
    uint256 usdoMockTokenId = 100;

    /**
     * Constants
     */
    uint32 public EID_A = 1;
    address public ENDPOINT_A;

    uint32 public EID_B = 2;
    address public ENDPOINT_B;

    function setUp() public virtual override {
        vm.label(adminAddr, "Admin");
        vm.label(aliceAddr, "Alice");
        vm.label(bobAddr, "Bob");

        // Peripheral contracts
        cluster = createCluster(0, adminAddr);

        // Mocks tokens
        tapMockPenrose = address(new ERC20Mock("TAP_MOCK_PENROSE", "TAP_MOCK_PENROSE", 100e18, 18, adminAddr));
        ethTokenPenrose = address(new ERC20Mock("ETH_MOCK_PENROSE", "ETH_MOCK_PENROSE", 100e18, 18, adminAddr));

        // Misc
        vm.warp(10000 weeks); // Set it to a big number

        setUpEndpoints(3, LibraryType.UltraLightNode);
        ENDPOINT_A = address(endpoints[EID_A]);
        ENDPOINT_B = address(endpoints[EID_B]);
        usdoMock = new Usdo(ENDPOINT_A, adminAddr, address(cluster));

        // Bar contracts
        marketHelper = new MarketHelper();

        bigBangEthOracle =
            ITapiocaOracle(address(OracleMock(address(new OracleMock("ETH_ORACLE", "ETH_ORACLE", 5e14)))));

        (penrose, bigBangMasterContract, singularityMasterContract) =
            createPenrose(address(cluster), tapMockPenrose, ethTokenPenrose, adminAddr);

        setUpBigBang();
        setUpSingularity();
    }

    function createTobInstance(
        address payable _tapOFT,
        address _paymentTokenBeneficiary,
        uint256 _epochDuration,
        address _owner
    ) internal returns (TapiocaOptionBroker) {
        /*
        TapiocaOptionBroker tob =
            new TapiocaOptionBroker(_tOLP, _oTAP, _tapOFT, _paymentTokenBeneficiary, _epochDuration, _pearl mit, _owner);

        vm.startPrank(_owner);
        tob.setCluster(ICluster(address(new Cluster(0, _owner))));
        vm.stopPrank();

        return tob;
        */
    }

    struct TapOftInput {
        uint256 _epochDuration;
        address _endpoint;
        address _contributor;
        address _earlySupporters;
        address _supporters;
        address _lbp;
        address _dao;
        address _airdrop;
        uint256 _governanceEid;
        address _owner;
    }

    function createTapOftInstance(TapOftInput memory i) internal returns (TapTokenMock) {
        return new TapTokenMock(
            ITapToken.TapTokenConstructorData(
                i._epochDuration,
                i._endpoint,
                i._contributor,
                i._earlySupporters,
                i._supporters,
                i._lbp,
                i._dao,
                i._airdrop,
                i._owner,
                address(cluster)
            )
        );
    }

    function createTwTap(address _tapOft, address _owner) internal returns (TwTAP) {
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
        return new TwTAP(_tapOft, _owner, 7 days, buckets);
    }

    /**
     * Peripheral contracts
     */

    // -------  Cluster
    function createCluster(uint32 _lzChainId, address _owner) internal returns (Cluster) {
        return new Cluster(_lzChainId, _owner);
    }

    // -------  Bar
    function createPenrose(address _cluster, address _tap, address _mainToken, address _owner)
        internal
        returns (Penrose _penrose, BigBang bbMasterContract, Singularity sglMasterContract)
    {
        _penrose = new Penrose(ICluster(_cluster), BoringIERC20(_tap), BoringIERC20(_mainToken), _owner);

        bbMasterContract = new BigBang();
        sglMasterContract = new Singularity();
        vm.startPrank(adminAddr);
        _penrose.registerBigBangMasterContract(address(bbMasterContract), IPenrose.ContractType.mediumRisk);
        _penrose.registerSingularityMasterContract(address(sglMasterContract), IPenrose.ContractType.mediumRisk);
        _penrose.setUsdoToken(address(usdoMock));
        vm.stopPrank();
    }

    struct BigBangInitData {
        address penrose;
        address collateral;
        ITapiocaOracle oracle;
        ILeverageExecutor leverageExecutor;
        uint256 debtRateAgainstEth;
        uint256 debtRateMin;
        uint256 debtRateMax;
    }

    function createBigBang(BigBangInitData memory _bbInitData, address _mc) internal returns (BigBang) {
        BigBang bigBang = new BigBang();

        vm.prank(adminAddr);
        Penrose(_bbInitData.penrose).addBigBang(_mc, address(bigBang));
        (
            BigBang._InitMemoryModulesData memory initModulesData,
            BigBang._InitMemoryDebtData memory initDebtData,
            BigBang._InitMemoryData memory initMemoryData,
            address debtRateHelper
        ) = _getBigBangInitData(_bbInitData, bigBang);

        bigBang.init(abi.encode(initModulesData, initDebtData, initMemoryData));

        return bigBang;
    }

    function _getBigBangInitData(BigBangInitData memory _bbInitData, BigBang _bigBang)
        private
        returns (
            BigBang._InitMemoryModulesData memory modulesData,
            BigBang._InitMemoryDebtData memory debtData,
            BigBang._InitMemoryData memory data,
            address debtRateHelper
        )
    {
        // Init modules
        BBLiquidation bbLiq = new BBLiquidation();
        BBBorrow bbBorrow = new BBBorrow();
        BBCollateral bbCollateral = new BBCollateral();
        BBLeverage bbLev = new BBLeverage();

        modulesData =
            BigBang._InitMemoryModulesData(address(bbLiq), address(bbBorrow), address(bbCollateral), address(bbLev));

        debtData = BigBang._InitMemoryDebtData(
            _bbInitData.debtRateAgainstEth, _bbInitData.debtRateMin, _bbInitData.debtRateMax
        );

        data = BigBang._InitMemoryData(
            IPenrose(_bbInitData.penrose),
            BoringIERC20(_bbInitData.collateral),
            ITapiocaOracle(address(_bbInitData.oracle)),
            0,
            75000,
            80000,
            _bbInitData.leverageExecutor
        );

        _bigBang.setAssetOracle(address(_bbInitData.oracle), "0x");
        _bigBang.setDebtRateHelper(address(new BBDebtRateHelper()));

        vm.prank(adminAddr);
        Penrose(_bbInitData.penrose).setBigBangEthMarket(address(_bigBang));
    }

    struct SingularityInitData {
        address penrose;
        BoringIERC20 asset;
        BoringIERC20 collateral;
        ITapiocaOracle oracle;
        ILeverageExecutor leverageExecutor;
    }

    function createSingularity(SingularityInitData memory _sglInitData, address _mc) internal returns (Singularity) {
        SGLInterestHelper sglInterestHelper = new SGLInterestHelper();
        Singularity sgl = new Singularity();
        SGLInit sglInit = new SGLInit();

        vm.prank(adminAddr);
        Penrose(_sglInitData.penrose).addSingularity(_mc, address(sgl));

        (
            SGLInit._InitMemoryModulesData memory _modulesData,
            SGLInit._InitMemoryTokensData memory _tokensData,
            SGLInit._InitMemoryData memory _data
        ) = _getSingularityInitData(_sglInitData);

        sgl.init(address(sglInit), abi.encode(_modulesData, _tokensData, _data));

        bytes memory payload = abi.encodeWithSelector(
            Singularity.setSingularityConfig.selector,
            sgl.borrowOpeningFee(),
            0,
            0,
            0,
            0,
            0,
            0,
            address(sglInterestHelper),
            0
        );
        address[] memory mc = new address[](1);
        mc[0] = address(sgl);

        bytes[] memory data = new bytes[](1);
        data[0] = payload;
        vm.prank(adminAddr);
        Penrose(_sglInitData.penrose).executeMarketFn(mc, data, false);

        return sgl;
    }

    function _getSingularityInitData(SingularityInitData memory _sglInitData)
        private
        returns (
            SGLInit._InitMemoryModulesData memory modulesData,
            SGLInit._InitMemoryTokensData memory tokensData,
            SGLInit._InitMemoryData memory data
        )
    {
        SGLLiquidation sglLiq = new SGLLiquidation();
        SGLBorrow sglBorrow = new SGLBorrow();
        SGLCollateral sglCollateral = new SGLCollateral();
        SGLLeverage sglLev = new SGLLeverage();

        modulesData =
            SGLInit._InitMemoryModulesData(address(sglLiq), address(sglBorrow), address(sglCollateral), address(sglLev));

        tokensData = SGLInit._InitMemoryTokensData(_sglInitData.asset, _sglInitData.collateral);

        data = SGLInit._InitMemoryData(
            IPenrose(_sglInitData.penrose),
            ITapiocaOracle(address(_sglInitData.oracle)),
            0,
            75000,
            80000,
            _sglInitData.leverageExecutor
        );
    }

    function createLeverageExecutor(address _swapper, address _cluster) public returns (SimpleLeverageExecutor) {
        return new SimpleLeverageExecutor(IZeroXSwapper(address(_swapper)), ICluster(_cluster), address(0));
    }

    /**
     * @dev Setup a big bang market with ETH as collateral
     * Important to initialize other values before calling this function
     */
    function setUpBigBang() internal {
        ZeroXSwapperMock zeroXSwapper = new ZeroXSwapperMock(cluster, adminAddr);
        SimpleLeverageExecutor leverageExecutor = createLeverageExecutor(address(zeroXSwapper), address(cluster));

        bigBangEthMarket = createBigBang(
            BigBangInitData({
                penrose: address(penrose),
                collateral: ethTokenPenrose,
                oracle: bigBangEthOracle,
                leverageExecutor: ILeverageExecutor(address(leverageExecutor)),
                debtRateAgainstEth: 0,
                debtRateMin: 0,
                debtRateMax: 0
            }),
            address(bigBangMasterContract)
        );
        vm.label(address(bigBangEthMarket), "BigBangEthMarket");

        vm.startPrank(adminAddr);
        cluster.updateContract(0, address(bigBangEthMarket), true);
        vm.stopPrank();
    }

    function depositBBCollateral(address to, uint256 amount) public {
        vm.startPrank(to);

        // approvals
        BoringIERC20(ethTokenPenrose).approve(address(bigBangEthMarket), type(uint256).max);

        // Deposit collateral

        deal(address(ethTokenPenrose), to, amount);
        uint256 share = bigBangEthMarket.convertToShares(amount);
        // TODO review it yieldBox.depositAsset(ethTokenPenroseId, to, share);
        (BBModule[] memory modules, bytes[] memory calls) = marketHelper.addCollateral(to, to, 0, share);
        bigBangEthMarket.execute(modules, calls, true);

        // Borrow

        bigBangEthMarket.updateExchangeRate();
        // amount is gonna be <=75% of the amount of collateral converted into USD at `rate` USD per ETH
        uint256 rate = 1e36 / bigBangEthOracle.peekSpot("");
        uint256 amountUsd = (amount * rate * 50) / 1e21;
        (modules, calls) = marketHelper.borrow(to, to, amountUsd);
        bigBangEthMarket.execute(modules, calls, true);
        vm.stopPrank();
    }

    function depositSGLAsset(address to, uint256 amount) public {
        vm.startPrank(to);
        deal(address(usdoMock), to, amount);
        usdoMock.approve(address(singularityEthMarket), type(uint256).max);

        uint256 share = singularityEthMarket.convertToShares(amount);
        // TODO review it yieldBox.depositAsset(usdoMockTokenId, to, to, 0, share);

        singularityEthMarket.addAsset(to, to, share);

        vm.stopPrank();
    }

    function setUpSingularity() internal {
        // Register tokens in YieldBox

        ZeroXSwapperMock zeroXSwapper = new ZeroXSwapperMock(cluster, adminAddr);
        SimpleLeverageExecutor leverageExecutor = createLeverageExecutor(address(zeroXSwapper), address(cluster));

        singularityEthMarket = createSingularity(
            SingularityInitData({
                penrose: address(penrose),
                asset: BoringIERC20(address(usdoMock)),
                collateral: BoringIERC20(ethTokenPenrose),
                oracle: bigBangEthOracle,
                leverageExecutor: ILeverageExecutor(address(leverageExecutor))
            }),
            address(singularityMasterContract)
        );
        vm.prank(adminAddr);
        cluster.updateContract(0, address(singularityEthMarket), true);
        vm.label(address(singularityEthMarket), "SingularityEthMarket");
    }

    /**
     * UTILS
     */
    function _resetPrank(address caller) internal {
        vm.stopPrank();
        vm.startPrank(caller);
    }

    modifier assumeGt(uint256 a, uint256 b) {
        vm.assume(a > b);
        _;
    }

    modifier assumeLt(uint256 a, uint256 b) {
        vm.assume(a < b);
        _;
    }
}
