// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {Market} from "tapioca-bar/markets/Market.sol";
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
    uint256 public immutable BB_DEFAULT_BORROW_CAP;

    constructor(
        address liquidationModule,
        address borrowModule,
        address collateralModule,
        address leverageModule,
        address penrose,
        address leverageExecutor,
        address bigbangMaster,
        address debtRateHelper,
        uint256 defaultBorrowCap
    ) {
        BB_LIQUIDATION = liquidationModule;
        BB_BORROW = borrowModule;
        BB_COLLATERAL = collateralModule;
        BB_LEVERAGE = leverageModule;
        PENROSE = Penrose(penrose);
        LEVERAGE_EXECUTOR = ILeverageExecutor(leverageExecutor);
        BB_MASTER = bigbangMaster;
        BB_DEBT_RATE_HELPER = debtRateHelper;
        BB_DEFAULT_BORROW_CAP = defaultBorrowCap;
    }

    function createBigBang(BigBangRiskParams memory riskParams) external returns (BigBang) {
        //BigBang bigBangInstance = new BigBang();

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

        bytes memory initPayload = abi.encode(abi.encode(modulesData, debtData, initData));
        BigBang bigBangInstance = BigBang(payable(PENROSE.registerBigBang(BB_MASTER, initPayload, true)));

        address[] memory markets = new address[](3);
        bytes[] memory settersData = new bytes[](3);

        markets[0] = address(bigBangInstance);
        markets[1] = address(bigBangInstance);
        markets[2] = address(bigBangInstance);

        settersData[0] = abi.encodeWithSelector(BigBang.setAssetOracle.selector, riskParams.oracle, "0x");
        settersData[1] = abi.encodeWithSelector(BigBang.setDebtRateHelper.selector, BB_DEBT_RATE_HELPER);
        settersData[2] = abi.encodeWithSelector(
                    Market.setMarketConfig.selector,
                    address(0), // ITapiocaOracle
                    "", // OracleDataInput
                    0, // ProtocolFee
                    0, // LiquidationBonusAmount
                    0, // MinLiquidatorReward
                    0, // MaxLiquidatorReward
                    BB_DEFAULT_BORROW_CAP, // TotalBorrowCap
                    0, // CollateralizationRate
                    0, // LiquidationCollateralizationRate
                    0, // MinBorrowAmount
                    0 // MinCollateralAmount
                );

        (bool[] memory success,) = PENROSE.executeMarketFn(markets, settersData, true);

        if (riskParams.isEthMarket) {
            PENROSE.setBigBangEthMarket(address(bigBangInstance));
        }

        if (success[0] == false || success[1] == false) {
            revert MarketCreationFailed();
        }

        return bigBangInstance;
    }
}
