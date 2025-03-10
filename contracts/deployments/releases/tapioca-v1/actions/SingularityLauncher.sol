// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Singularity} from "tapioca-bar/markets/singularity/Singularity.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ISingularityLauncher, RiskParams} from "deployments/interfaces/ISingularityLauncher.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SGLInit} from "tapioca-bar/markets/singularity/SGLInit.sol";
/// @notice Contract to create Singularity markets via delegatecall  from admin of Penrose

contract SingularityLauncher is ISingularityLauncher {
    address public immutable SGL_INIT;
    address public immutable SGL_MASTER;
    address public immutable SGL_INTEREST_HELPER;
    ILeverageExecutor public immutable LEVERAGE_EXECUTOR;
    IPenrose public immutable PENROSE;
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
        PENROSE = IPenrose(penrose);
        LEVERAGE_EXECUTOR = ILeverageExecutor(leverageExecutor);
        SGL_INTEREST_HELPER = sglInterestHelper;
        SGL_MASTER = singularityMaster;
    }

    function createSingularity(SGLInit._InitMemoryTokensData memory tokensData, RiskParams memory riskParams)
        external
        returns (Singularity)
    {
        SGLInit._InitMemoryModulesData memory sglModules = SGLInit._InitMemoryModulesData(
            SGL_LIQUIDATION_MODULE, SGL_BORROW_MODULE, SGL_COLLATERAL_MODULE, SGL_LEVERAGE_MODULE
        );
        Singularity singularityInstance = new Singularity();

        SGLInit._InitMemoryData memory initData = SGLInit._InitMemoryData(
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

        // Add seed amount to owner
        IERC20(address(tokensData._asset)).transferFrom(riskParams.seedOwner, address(this), riskParams.seedAmount);
        tokensData._asset.approve(address(singularityInstance), riskParams.seedAmount);
        singularityInstance.addAsset(address(this), riskParams.seedOwner, riskParams.seedAmount);

        return singularityInstance;
    }
}
