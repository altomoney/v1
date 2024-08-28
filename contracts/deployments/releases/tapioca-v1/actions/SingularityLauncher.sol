// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ISingularityLauncher, RiskParams} from "deployments/interfaces/ISingularityLauncher.sol";

/// @notice Contract to create Singularity markets via delegatecall from admin of Penrose
contract SingularityLauncher is ISingularityLauncher {
    address public immutable SGL_INIT;
    address public immutable SGL_MASTER;
    address public immutable SGL_INTEREST_HELPER;
    ILeverageExecutor public immutable LEVERAGE_EXECUTOR;
    Penrose public immutable PENROSE;
    address public immutable SGL_LIQUIDATION_MODULE;
    address public immutable SGL_BORROW_MODULE;
    address public immutable SGL_COLLATERAL_MODULE;
    address public immutable SGL_LEVERAGE_MODULE;

    constructor(
        address liquidationModule,
        address borrowModule,
        address collateralModule,
        address leverageModule,
        address sglInit,
        address penrose,
        address leverageExecutor,
        address sglInterestHelper,
        address singularityMaster
    ) {
        SGL_LIQUIDATION_MODULE = liquidationModule;
        SGL_BORROW_MODULE = borrowModule;
        SGL_COLLATERAL_MODULE = collateralModule;
        SGL_LEVERAGE_MODULE = leverageModule;
        SGL_INIT = sglInit;
        PENROSE = Penrose(penrose);
        LEVERAGE_EXECUTOR = ILeverageExecutor(leverageExecutor);
        SGL_INTEREST_HELPER = sglInterestHelper;
        SGL_MASTER = singularityMaster;
    }

    function createSingularity(Singularity._InitMemoryTokensData memory tokensData, RiskParams memory riskParams)
        public
        returns (Singularity)
    {
        Singularity._InitMemoryModulesData memory sglModules = Singularity._InitMemoryModulesData(
            SGL_LIQUIDATION_MODULE, SGL_BORROW_MODULE, SGL_COLLATERAL_MODULE, SGL_LEVERAGE_MODULE
        );
        Singularity singularityInstance = new Singularity();

        Singularity._InitMemoryData memory initData = Singularity._InitMemoryData(
            IPenrose(address(PENROSE)),
            ITapiocaOracle(riskParams.oracle),
            riskParams.exchangeRatePrecision,
            riskParams.collateralizationRate,
            riskParams.liquidationCollateralizationRate,
            LEVERAGE_EXECUTOR
        );

        singularityInstance.init(SGL_INIT, abi.encode(sglModules, tokensData, initData));

        PENROSE.addSingularity(SGL_MASTER, address(singularityInstance));

        bytes memory payload = abi.encodeWithSelector(
            Singularity.setSingularityConfig.selector,
            riskParams.borrowOpeningFee,
            riskParams.liquidationMultiplier,
            riskParams.minimumTargetUtilization,
            riskParams.maximumTargetUtilization,
            riskParams.minimumInterestPerSecond,
            riskParams.maximumInterestPerSecond,
            riskParams.interestElasticity,
            SGL_INTEREST_HELPER,
            riskParams.minLendAmount
        );
        address[] memory market = new address[](1);
        market[0] = address(singularityInstance);

        bytes[] memory data = new bytes[](1);
        data[0] = payload;

        (bool[] memory success,) = PENROSE.executeMarketFn(market, data, false);

        if (success[0] == false) {
            revert MarketCreationFailed();
        }

        return singularityInstance;
    }
}
