// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Lz
import {TestHelper} from "../../../utils/LZSetup/TestHelper.sol";

// External
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TapiocaOmnichainEngineHelper} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";

import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";

import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";

import {MagnetarCollateralModule} from "tapioca-periph/Magnetar/modules/MagnetarCollateralModule.sol";
import {ITapiocaOmnichainEngine} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarOptionModule} from "tapioca-periph/Magnetar/modules/MagnetarOptionModule.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {MagnetarLeverageModule} from "tapioca-periph/Magnetar/modules/MagnetarLeverageModule.sol";
import {MagnetarBaseModule} from "tapioca-periph/Magnetar/modules/MagnetarBaseModule.sol";
import {Magnetar} from "tapioca-periph/Magnetar/Magnetar.sol";

import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";

import {Usdo} from "tapioca-bar/usdo/Usdo.sol";

import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

import {ZerroXSwapperMockTarget} from "../../../utils/ZeroXSwapper/ZerroXSwapperMockTarget.sol";
import {ZeroXSwapper} from "tap-utils/Swapper/ZeroXSwapper.sol";

import {OracleMock} from "../../mocks/OracleMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";

import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";

import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";

import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";

import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";

import {MagnetarWithdrawData} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";

import "forge-std/Test.sol";

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

struct MagnetarSetupData {
    MagnetarCollateralModule collateralModule;
    MagnetarMintModule mintModule;
    MagnetarOptionModule optionModule;
    MagnetarLeverageModule leverageModule;
}

contract MagnetarTestHelper is TestHelper {
    Cluster clusterA;
    Cluster clusterB;

    Magnetar magnetarA;
    Magnetar magnetarB;
    MagnetarHelper magnetarHelper;
    OracleMock oracle;
    MarketHelper marketHelper;

    Penrose penrose;
    Singularity sglMC;
    BigBang bbMC;

    SGLInit sglInit;
    Singularity sgl;
    BigBang bb;

    uint32 aEid = 1;
    uint32 bEid = 2;

    ERC20Mock aERC20;
    ERC20Mock bERC20;
    ERC20Mock collateralErc20;
    ERC20Mock weth;
    ERC20Mock tap;

    Usdo assetA;
    uint256 assetAId;
    Usdo assetB;
    uint256 assetBId;

    uint256 wethId;
    uint256 tapId;

    /**
     * DEPLOY setup addresses
     */
    address __endpoint;
    uint256 __hostEid = aEid;
    address __owner = address(this);

    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    uint256 internal userCPKey = 0x3;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    address public userC = vm.addr(userCPKey);

    function createCommonSetup() public {
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aERC20 = new ERC20Mock();
        bERC20 = new ERC20Mock();
        collateralErc20 = new ERC20Mock();
        weth = new ERC20Mock();
        tap = new ERC20Mock();

        clusterA = new Cluster(aEid, address(this));
        clusterB = new Cluster(bEid, address(this));
        magnetarHelper = new MagnetarHelper();
        marketHelper = new MarketHelper();
        oracle = new OracleMock("Test", "TT", 1 ether);

        magnetarA.setHelper(address(magnetarHelper));
        magnetarB.setHelper(address(magnetarHelper));
        sglInit = new SGLInit();
        (penrose, sglMC, bbMC) = createPenrose(address(clusterA), address(tap), address(weth), address(this));

        // crete USDO

        penrose.setUsdoToken(address(assetA));

        sgl = createSingularity(
            TestSingularityData(
                address(penrose),
                address(assetA),
                address(aERC20),
                ITapiocaOracle(address(oracle)),
                ILeverageExecutor(address(0))
            ),
            address(sglMC)
        );
        bb = createBigBang(
            TestBigBangData(
                address(penrose),
                address(aERC20),
                ITapiocaOracle(address(oracle)),
                ILeverageExecutor(address(0)),
                0,
                0,
                0
            ),
            address(bbMC)
        );
        setAssetOracle(penrose, bb, address(oracle));
        penrose.setBigBangEthMarket(address(bb));

        address[] memory markets = new address[](1);
        markets[0] = address(bb);
        bytes[] memory marketsData = new bytes[](1);
        BBDebtRateHelper bbRateHelper = new BBDebtRateHelper();
        marketsData[0] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, address(bbRateHelper));
        penrose.executeMarketFn(markets, marketsData, true);

        assetA.setMinterStatus(address(bb), true);
        assetA.setBurnerStatus(address(bb), true);

        clusterA.updateContract(0, address(magnetarA), true);
        clusterA.updateContract(0, address(magnetarHelper), true);
        clusterA.updateContract(0, address(oracle), true);

        clusterA.updateContract(0, address(assetA), true);
        clusterA.updateContract(0, address(marketHelper), true);
        clusterA.updateContract(bEid, address(assetB), true);
        clusterA.updateContract(0, address(penrose), true);
        clusterA.updateContract(0, address(sgl), true);
        clusterA.updateContract(0, address(bb), true);

        clusterB.updateContract(0, address(magnetarB), true);
        clusterB.updateContract(0, address(magnetarHelper), true);
        clusterB.updateContract(0, address(oracle), true);

        clusterB.updateContract(0, address(assetB), true);
        clusterB.updateContract(0, address(marketHelper), true);
        clusterB.updateContract(aEid, address(assetA), true);
        clusterB.updateContract(0, address(penrose), true);
        clusterB.updateContract(0, address(sgl), true);
        clusterB.updateContract(0, address(bb), true);

        vm.label(address(magnetarA), "Magnetar A");
        vm.label(address(magnetarB), "Magnetar B");
        vm.label(address(magnetarHelper), "MagnetarHelper");
        vm.label(address(oracle), "Oracle");
        vm.label(address(assetA), "Usdo (asset) A");
        vm.label(address(assetB), "Usdo (asset) B");
        vm.label(address(aERC20), "aERC20");
        vm.label(address(bERC20), "bERC20");
        vm.label(address(collateralErc20), "collateralErc20");
        vm.label(address(weth), "WETH");
        vm.label(address(tap), "TapToken");
        vm.label(address(marketHelper), "MarketHelper");
        vm.label(address(clusterA), "Cluster A");
        vm.label(address(clusterB), "Cluster B");
    }
    // -----------------------
    //
    // Setup helpers
    //
    // -----------------------


    function createUsdo(address yieldBox, address cluster, address extExec, uint32 endointId)
        public
        returns (Usdo usdo)
    {
        usdo = new Usdo(address(endpoints[endointId]), __owner, address(cluster));
    }

    function setBBEthMarket(Penrose penrose, address market) external {
        penrose.setBigBangEthMarket(market);
    }

    function createMagnetar(address _cluster) public returns (Magnetar magnetar) {
        TapiocaOmnichainEngineHelper toeHelper = new TapiocaOmnichainEngineHelper();

        MagnetarSetupData memory setup;

        magnetar = new Magnetar(
            ICluster(_cluster),
            address(this),
            payable(setup.collateralModule),
            payable(setup.mintModule),
            payable(setup.optionModule),
            payable(setup.leverageModule),
            address(toeHelper),
            address(new MagnetarHelper())
        );
    }

    function createPenrose(address _cluster, address tapToken_, address mainToken_, address owner)
        public
        returns (Penrose penrose, Singularity mediumRiskMC, BigBang bbMediumRiskMC)
    {
        penrose = new Penrose(ICluster(_cluster), IERC20(tapToken_), IERC20(mainToken_), owner);
        mediumRiskMC = new Singularity();
        bbMediumRiskMC = new BigBang();

        penrose.registerSingularityMasterContract(address(mediumRiskMC), IPenrose.ContractType.mediumRisk);
        penrose.registerBigBangMasterContract(address(bbMediumRiskMC), IPenrose.ContractType.mediumRisk);
    }

    function setAssetOracle(Penrose penrose, BigBang bb, address oracle) public {
        // function executeMarketFn(address[] calldata mc, bytes[] memory data, bool forceSuccess)
        address[] memory markets = new address[](1);
        markets[0] = address(bb);
        bytes[] memory marketsData = new bytes[](1);
        marketsData[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, oracle, "0x");

        penrose.executeMarketFn(markets, marketsData, true);
    }

    function createBigBang(TestBigBangData memory _bb, address _mc) public returns (BigBang) {
        BigBang bb = new BigBang();
        BBDebtRateHelper helper = new BBDebtRateHelper();

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

        address[] memory markets = new address[](1);
        markets[0] = address(bb);
        bytes[] memory marketsData = new bytes[](1);
        BBDebtRateHelper bbRateHelper = new BBDebtRateHelper();
        marketsData[0] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, address(bbRateHelper));
        penrose.executeMarketFn(markets, marketsData, true);

        return bb;
    }

    function createSingularity(TestSingularityData memory _sgl, address _mc) public returns (Singularity) {
        Singularity sgl = new Singularity();
        SGLInit sglInit = new SGLInit();
        (
            SGLInit._InitMemoryModulesData memory _modulesData,
            SGLInit._InitMemoryTokensData memory _tokensData,
            SGLInit._InitMemoryData memory _data
        ) = _getSingularityInitData(_sgl);
        {
            sgl.init(address(sglInit), abi.encode(_modulesData, _tokensData, _data));
        }

        {
            Penrose(_sgl.penrose).addSingularity(_mc, address(sgl));
        }

        {
            SGLInterestHelper sglInterestHelper = new SGLInterestHelper();

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
            Penrose(_sgl.penrose).executeMarketFn(mc, data, false);
        }

        return sgl;
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

        tokensData = SGLInit._InitMemoryTokensData(IERC20(_sgl.asset), IERC20(_sgl.collateral));

        data = SGLInit._InitMemoryData(
            IPenrose(_sgl.penrose), ITapiocaOracle(address(_sgl.oracle)), 0, 75000, 80000, _sgl.leverageExecutor
        );
    }

    // -----------------------
    //
    // Market helpers
    //
    // -----------------------
    function createEmptyWithdrawData() public returns (MagnetarWithdrawData memory) {
        return MagnetarWithdrawData({
            asset: address(0),
            receiver: address(this),
            amount: 1 ether,
            withdraw: false,
            unwrap: false,
            extractFromSender: false
        });
    }

    function depositAsset(Usdo _asset, Singularity _sgl, uint256 amount) public {
        deal(address(_asset), address(this), amount);

        _sgl.addAsset(address(this), address(this), amount); // todo: replace 100 with share
    }

    function depositCollateral(address _collateral, Singularity _sgl, uint256 amount) public {
        deal(_collateral, address(this), amount);

        (Module[] memory modules, bytes[] memory calls) =
            marketHelper.addCollateral(address(this), address(this), 0, 100); // todo: replace 100 with share
        _sgl.execute(modules, calls, true);
    }

    function borrow(Singularity _sgl, uint256 amount, bool expectRevert) public {
        (Module[] memory modules, bytes[] memory calls) = marketHelper.borrow(address(this), address(this), amount);

        if (expectRevert) vm.expectRevert();
        _sgl.execute(modules, calls, true);
    }

    function repay(uint256 part, Singularity _sgl) public {
        (Module[] memory modules, bytes[] memory calls) = marketHelper.repay(address(this), address(this), part);
        _sgl.execute(modules, calls, true);
    }

    // -----------------------
    //
    // Approval helpers
    //
    // -----------------------
    function _createErc20Permit(address _owner, uint256 _pkSigner, address _spender, uint256 _amount, address _asset)
        internal
        returns (ERC20PermitStruct memory permitStruct, uint8 v_, bytes32 r_, bytes32 s_)
    {
        permitStruct = ERC20PermitStruct({owner: _owner, spender: _spender, value: _amount, nonce: 0, deadline: 1 days});
        bytes32 digest_ = ERC20Mock(_asset).getTypedDataHash(permitStruct);
        (v_, r_, s_) = vm.sign(_pkSigner, digest_);
    }
}
