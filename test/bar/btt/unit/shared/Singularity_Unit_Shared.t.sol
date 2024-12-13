// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// Tapioca
import {SGLInterestHelper} from "tapioca-bar/markets/singularity/SGLInterestHelper.sol";
import {SGLLiquidation} from "tapioca-bar/markets/singularity/SGLLiquidation.sol";
import {SGLCollateral} from "tapioca-bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "tapioca-bar/markets/singularity/SGLLeverage.sol";
import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {SGLBorrow} from "tapioca-bar/markets/singularity/SGLBorrow.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";

import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

// tests
import {Markets_Unit_Shared} from "./Markets_Unit_Shared.t.sol";

// mocks
import {LeverageExecutorMock_test} from "../../mocks/LeverageExecutorMock_test.sol";

abstract contract Singularity_Unit_Shared is Markets_Unit_Shared {
    // ************ //
    // *** VARS *** //
    // ************ //
    Singularity randomSglMC;
    Singularity randomSgl;

    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public virtual override {
        super.setUp();

        // create default BB master contract
        randomSglMC = new Singularity();
        penrose.registerSingularityMasterContract(address(randomSglMC), IPenrose.ContractType.lowRisk);

        // create main BB market
        // it handles after deployment set-up
        randomSgl = Singularity(payable(_registerSGLMarket(address(mainToken), address(usdo))));
    }

    // **************** //
    // *** INTERNAL *** //
    // **************** //

    function _registerSGLMarket(address _collateral, address _asset) internal returns (address) {
        (
            Singularity._InitMemoryModulesData memory modulesData,
            Singularity._InitMemoryTokensData memory tokensData,
            Singularity._InitMemoryData memory data
        ) = _getSingularityInitData(
            SingularityInitData(
                address(penrose),
                _asset,
                _collateral, //collateral
                ITapiocaOracle(address(oracle)),
                ILeverageExecutor(address(leverageExecutor))
            )
        );

        Singularity sgl = new Singularity();
        SGLInit sglInit = new SGLInit();
        sgl.init(address(sglInit), abi.encode(modulesData, tokensData, data));
        penrose.addSingularity(address(randomSglMC), address(sgl));

        // *** AFTER DEPLOYMENT *** //
        {
            SGLInterestHelper sglInterestHelper = new SGLInterestHelper();

            bytes memory payload = abi.encodeWithSelector(
                Singularity.setSingularityConfig.selector, 0, 0, 0, 0, 0, 0, 0, address(sglInterestHelper), 0
            );
            address[] memory mc = new address[](1);
            mc[0] = address(sgl);

            bytes[] memory penroseData = new bytes[](1);
            penroseData[0] = payload;
            penrose.executeMarketFn(mc, penroseData, false);
        }

        vm.label(address(sgl), "Singularity market");
        return address(sgl);
    }

    function _getSingularityInitData(SingularityInitData memory _sgl)
        internal
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
            IPenrose(_sgl.penrose), ITapiocaOracle(address(_sgl.oracle)), 0, CR_RATE, LQ_CR_RATE, _sgl.leverageExecutor
        );
    }

    function _approveForCollateral(address txExecutor) internal virtual override resetPrank(txExecutor) {}
}
