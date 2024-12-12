// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

// Lz
import {TestHelper} from "../LZSetup/TestHelper.sol";

// External
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// Tapioca
import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {IOracle} from "tap-utils/oracle/interfaces/IOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";



import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {MagnetarMock} from "../mocks/MagnetarMock.sol";

import {Penrose} from "tapioca-bar/Penrose.sol";
import {SwapperMock} from "../mocks/SwapperMock.sol";
import {OracleMock} from "../mocks/OracleMock.sol";
import {TestUtils} from "../TestUtils.t.sol";

import {BBLiquidation} from "tapioca-bar/markets/bigBang/BBLiquidation.sol";
import {BBCollateral} from "tapioca-bar/markets/bigBang/BBCollateral.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBBorrow} from "tapioca-bar/markets/bigBang/BBBorrow.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {IMarket} from "../../../contracts/utils/interfaces/bar/IMarket.sol";

import {Origins} from "tapioca-bar/markets/origins/Origins.sol";

struct TestPenroseData {
    address cluster;
    address tap;
    address token;
    address owner;
}

struct TestSingularityData {
    address penrose;
    IERC20 asset;
    IERC20 collateral;
    IOracle oracle;
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

contract UsdoTestHelper is TestHelper, TestUtils {
    function createMagnetar(address cluster) public returns (MagnetarMock) {
        return new MagnetarMock(cluster);
    }


    function createCluster(uint32 hostEid, address owner) public returns (Cluster) {
        return new Cluster(hostEid, owner);
    }

    function createSwapper(IMarket _market) public returns (SwapperMock) {
        return new SwapperMock(address(_market));
    }

    function createOracle() public returns (OracleMock) {
        return new OracleMock("Oracle Test", "ORCT", 1 ether);
    }

    function createLeverageExecutor(address, address _swapper, address _cluster)
        public
        returns (SimpleLeverageExecutor)
    {
        return new SimpleLeverageExecutor(IZeroXSwapper(_swapper), ICluster(_cluster), address(0));
    }

    function createPenrose(TestPenroseData memory _data) public returns (Penrose pen, Singularity mediumRiskMC) {

        pen = new Penrose(
            ICluster(_data.cluster),
            IERC20(_data.tap),
            IERC20(_data.token),
            _data.owner
        );
        mediumRiskMC = new Singularity();

        pen.registerSingularityMasterContract(address(mediumRiskMC), IPenrose.ContractType.mediumRisk);
    }

    function createOrigins(
        address owner,
        address asset,
        address collateral,
        ITapiocaOracle oracle,
        uint256 exchangePrecision,
        uint256 collateralizationRate,
        address penrose
    ) public returns (Origins) {
        Origins origins = new Origins(owner);
        origins.init(
            IERC20(asset),
            collateral,
            oracle,
            exchangePrecision,
            collateralizationRate,
            IPenrose(penrose)
        );
        return origins;
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

    function createSingularity(Penrose _penrose, TestSingularityData memory _sgl, address _mc)
        public
        returns (Singularity)
    {
        Singularity sgl = new Singularity();
        SGLInit sglInit = new SGLInit();
        (
            Singularity._InitMemoryModulesData memory _modulesData,
            Singularity._InitMemoryTokensData memory _tokensData,
            Singularity._InitMemoryData memory _data
        ) = _getSingularityInitData(_sgl, address(_penrose));
        {
            sgl.init(address(sglInit), abi.encode(_modulesData, _tokensData, _data));
        }

        {
            _penrose.addSingularity(_mc, address(sgl));
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
            _penrose.executeMarketFn(mc, data, false);
        }

        return sgl;
    }

    function _getSingularityInitData(TestSingularityData memory _sgl, address _penrose)
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

        tokensData = Singularity._InitMemoryTokensData(_sgl.asset, _sgl.collateral);

        data = Singularity._InitMemoryData(
            IPenrose(_penrose), ITapiocaOracle(address(_sgl.oracle)), 0, 75000, 80000, _sgl.leverageExecutor
        );
    }
}
