// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Penrose} from "tapioca-bar/Penrose.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IBigBangLauncher, BigBangRiskParams} from "deployments/interfaces/IBigBangLauncher.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

/// @notice Contract to create BigBang markets via delegatecall from admin of Penrose
contract BigBangLauncher is IBigBangLauncher {
    address public immutable BB_LIQUIDATION;
    address public immutable BB_BORROW;
    address public immutable BB_COLLATERAL;
    address public immutable BB_LEVERAGE;
    ILeverageExecutor public immutable LEVERAGE_EXECUTOR;
    Penrose public immutable PENROSE;
    address public immutable BB_MASTER;
    address public immutable BB_DEBT_RATE_HELPER;
    address public immutable BB_INSTANCE;

    struct BigBangConstructor {
        address liquidationModule;
        address borrowModule;
        address collateralModule;
        address leverageModule;
        address leverageExecutor;
        address bigbangMaster;
        address debtRateHelper;
        address penrose;
        BigBangRiskParams riskParams;
    }

    constructor(BigBangConstructor memory params) {
        BB_LIQUIDATION = params.liquidationModule;
        BB_BORROW = params.borrowModule;
        BB_COLLATERAL = params.collateralModule;
        BB_LEVERAGE = params.leverageModule;
        PENROSE = Penrose(params.penrose);
        LEVERAGE_EXECUTOR = ILeverageExecutor(params.leverageExecutor);
        BB_MASTER = params.bigbangMaster;
        BB_DEBT_RATE_HELPER = params.debtRateHelper;

        BigBangRiskParams memory riskParams = params.riskParams;

        BigBang bigBangInstance = new BigBang();

        BigBang._InitMemoryModulesData memory modulesData =
            BigBang._InitMemoryModulesData(BB_LIQUIDATION, BB_BORROW, BB_COLLATERAL, BB_LEVERAGE);

        BigBang._InitMemoryDebtData memory debtData =
            BigBang._InitMemoryDebtData(riskParams.debtRateAgainstEth, riskParams.debtRateMin, riskParams.debtRateMax);

        BigBang._InitMemoryData memory initData = BigBang._InitMemoryData(
            IPenrose(address(PENROSE)),
            IERC20(riskParams.collateral),
            ITapiocaOracle(riskParams.oracle),
            riskParams.exchangeRatePrecision,
            riskParams.collateralizationRate,
            riskParams.liquidationCollateralizationRate,
            LEVERAGE_EXECUTOR
        );

        bigBangInstance.init(abi.encode(modulesData, debtData, initData));

        PENROSE.addBigBang(BB_MASTER, address(bigBangInstance));

        address[] memory markets = new address[](2);
        bytes[] memory settersData = new bytes[](2);

        markets[0] = address(bigBangInstance);
        markets[1] = address(bigBangInstance);

        settersData[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, riskParams.oracle, "0x");
        settersData[1] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, BB_DEBT_RATE_HELPER);

        (bool[] memory success,) = PENROSE.executeMarketFn(markets, settersData, true);

        if (riskParams.isEthMarket) {
            PENROSE.setBigBangEthMarket(address(bigBangInstance));
        }

        if (success[0] == false || success[1] == false) {
            revert MarketCreationFailed();
        }

        BB_INSTANCE = address(bigBangInstance);
    }
}
