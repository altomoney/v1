// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";

// Tapioca
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Module, PauseType} from "tap-utils/interfaces/bar/IMarket.sol";
import {IUsdo} from "tap-utils/interfaces/oft/IUsdo.sol";
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {Market} from "../Market.sol";
import {BBLiquidation} from "./BBLiquidation.sol";
import {BBCollateral} from "./BBCollateral.sol";
import {BBLeverage} from "./BBLeverage.sol";
import {BBCommon} from "./BBCommon.sol";
import {BBBorrow} from "./BBBorrow.sol";

// solhint-disable max-line-length
/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract BigBang is BBCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeApprove for address;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error BadPair();
    error DebtRatesNotValid();
    error MaxDebtRateNotValid();

    error ModuleNotSet();

    // ************ //
    // *** VARS *** //
    // ************ //

    /// @notice returns the liquidation module
    BBLiquidation public liquidationModule;
    /// @notice returns the borrow module
    BBBorrow public borrowModule;
    /// @notice returns the collateral module
    BBCollateral public collateralModule;
    /// @notice returns the leverage module
    BBLeverage public leverageModule;

    struct _InitMemoryData {
        IPenrose _penrose;
        IERC20 _collateral;
        ITapiocaOracle _oracle;
        uint256 _exchangeRatePrecision;
        uint256 _collateralizationRate;
        uint256 _liquidationCollateralizationRate;
        ILeverageExecutor _leverageExecutor;
    }

    struct _InitMemoryModulesData {
        address _liquidationModule;
        address _borrowModule;
        address _collateralModule;
        address _leverageModule;
    }

    struct _InitMemoryDebtData {
        uint256 _debtRateAgainstEth;
        uint256 _debtRateMin;
        uint256 _debtRateMax;
    }

    /// @notice The init function that acts as a constructor
    function init(bytes calldata initData) external onlyOnce {
        (
            _InitMemoryModulesData memory initModulesData,
            _InitMemoryDebtData memory initDebtData,
            _InitMemoryData memory initMemoryData
        ) = abi.decode(initData, (_InitMemoryModulesData, _InitMemoryDebtData, _InitMemoryData));

        _initModules(
            initModulesData._liquidationModule,
            initModulesData._borrowModule,
            initModulesData._collateralModule,
            initModulesData._leverageModule
        );
        _initCoreStorage(
            initMemoryData._penrose,
            initMemoryData._collateral,
            initMemoryData._oracle,
            initMemoryData._exchangeRatePrecision,
            initMemoryData._collateralizationRate,
            initMemoryData._liquidationCollateralizationRate,
            initMemoryData._leverageExecutor
        );
        _initDebtStorage(initDebtData._debtRateAgainstEth, initDebtData._debtRateMin, initDebtData._debtRateMax);
    }

    function _initModules(
        address _liquidationModule,
        address _borrowModule,
        address _collateralModule,
        address _leverageModule
    ) private {
        liquidationModule = BBLiquidation(_liquidationModule);
        collateralModule = BBCollateral(_collateralModule);
        borrowModule = BBBorrow(_borrowModule);
        leverageModule = BBLeverage(_leverageModule);
    }

    function _initDebtStorage(uint256 _debtRateAgainstEth, uint256 _debtRateMin, uint256 _debtRateMax) private {
        isMainMarket = address(collateral()) == _penrose.mainToken();
        if (!isMainMarket) {
            if (_debtRateMin != 0 && _debtRateMax != 0) {
                if (_debtRateMin >= _debtRateMax) revert DebtRatesNotValid();
                if (_debtRateMax > 1e18) revert MaxDebtRateNotValid();
            }
            debtRateAgainstEthMarket = _debtRateAgainstEth;
            maxDebtRate = _debtRateMax;
            minDebtRate = _debtRateMin;
        }
    }

    function _initCoreStorage(
        IPenrose __penrose,
        IERC20 __collateral,
        ITapiocaOracle __oracle,
        uint256 __exchangeRatePrecision,
        uint256 __collateralizationRate,
        uint256 __liquidationCollateralizationRate,
        ILeverageExecutor __leverageExecutor
    ) private {
        _penrose = __penrose;
        address __asset = __penrose.usdoToken();

        if (address(__collateral) == address(0)) revert BadPair();
        if (__asset == address(0)) revert BadPair();
        if (address(__oracle) == address(0)) revert BadPair();
        if (__collateralizationRate > FEE_PRECISION) revert NotValid();
        if (__liquidationCollateralizationRate > FEE_PRECISION) {
            revert NotValid();
        }

        __initialize_MarketERC4626(address(__collateral));
        _asset = IERC20(__asset);
        oracle = __oracle;
        updateExchangeRate();
        protocolFee = 10000; // 10%; used for accrual
        collateralizationRate = __collateralizationRate > 0 ? __collateralizationRate : 75000;
        liquidationCollateralizationRate =
            __liquidationCollateralizationRate > 0 ? __liquidationCollateralizationRate : 80000;

        if (liquidationCollateralizationRate < collateralizationRate) {
            revert NotValid();
        }

        EXCHANGE_RATE_PRECISION = __exchangeRatePrecision > 0 ? __exchangeRatePrecision : 1e18;

        minLiquidatorReward = 88e3;
        maxLiquidatorReward = 925e2;
        liquidationBonusAmount = 3e3;
        liquidationMultiplier = 12000; //12%

        rateValidDuration = 24 hours;
        minMintFee = 0;
        maxMintFee = 1000; // 1%
        maxMintFeeStart = 980000000000000000; // 0.98 *1e18
        minMintFeeStart = 1000000000000000000; // 1*1e18

        leverageExecutor = __leverageExecutor;
        minBorrowAmount = 1e15;
        minCollateralAmount = 1e15;

        _transferOwnership(address(__penrose));
    }

    /// @notice Accrues the interest on the borrowed tokens and handles the accumulation of fees.
    function accrue() external override {
        if (pauseOptions[PauseType.AddCollateral] || pauseOptions[PauseType.RemoveCollateral]) revert AccruePaused();
        _accrue();
    }

    // ************************ //
    // *** VIEW FUNCTIONS ***** //
    // ************************ //
    /// @notice Returns variable opening fee
    /// @param amount the borrow amount to compute for
    function computeVariableOpeningFee(uint256 amount) external view returns (uint256) {
        //get asset <> USDC price ( USDO <> USDC )
        (bool updated, uint256 _exchangeRate) = assetOracle.peek(oracleData);
        if (!updated) revert OracleCallFailed();
        return _computeVariableOpeningFeeView(amount, _exchangeRate);
    }

    // ************************* //
    // *** OWNER FUNCTIONS ***** //
    // ************************* //
    function setDebtRateHelper(address _helper) external onlyOwner {
        if (_helper == address(0)) revert NotValid();
        emit DebtRateHelperUpdated(debtRateHelper, _helper);
        debtRateHelper = _helper;
    }

    /// @notice Reset the open interest debt and return the value
    function consumeMintableOpenInterestDebt() external onlyOwner returns (uint256) {
        uint256 _openInterestDebt = openInterestDebt;
        openInterestDebt = 0;
        return _openInterestDebt;
    }

    /// @notice sets min and max mint range
    /// @dev can only be called by the owner
    /// @param _min the new min start
    /// @param _max the new max start
    function setMinAndMaxMintRange(uint256 _min, uint256 _max) external onlyOwner {
        emit UpdateMinMaxMintRange(minMintFeeStart, _min, maxMintFeeStart, _max);

        if (_max >= _min) revert NotValid();

        minMintFeeStart = _min;
        maxMintFeeStart = _max;
    }

    /// @notice sets min and max mint fee
    /// @dev can only be called by the owner
    /// @param _min the new min fee
    /// @param _max the new max fee
    function setMinAndMaxMintFee(uint256 _min, uint256 _max) external onlyOwner {
        emit UpdateMinMaxMintFee(minMintFee, _min, maxMintFee, _max);
        if (_min >= _max) revert NotValid();
        minMintFee = _min;
        maxMintFee = _max;
    }

    /// @notice updates asset's oracle info
    /// @dev can only be called by the owner
    /// @param _oracle the new ITapiocaOracle address
    /// @param _oracleData the new ITapiocaOracle data
    function setAssetOracle(address _oracle, bytes calldata _oracleData) external onlyOwner {
        if (_oracle != address(0)) {
            emit AssetOracleUpdated(address(assetOracle), _oracle);
            assetOracle = ITapiocaOracle(_oracle);
        }
        if (_oracleData.length > 0) {
            assetOracleData = _oracleData;
            emit AssetOracleDataUpdated();
        }
    }

    /// @notice Transfers fees to penrose
    /// @dev can only be called by the owner or FEES_EXTRACTOR role
    /// @return feeAmount the amount of fees in shares withdrawn under Penrose
    function refreshPenroseFees() external returns (uint256 feeAmount) {
        require(
            _cluster().hasRole(msg.sender, keccak256("FEES_EXTRACTOR")) || msg.sender == owner(),
            "Ownable: caller is not the owner"
        );
        feeAmount = IERC20(_borrowableToken()).balanceOf(address(this));
        if (feeAmount > 0) {
            IERC20(_borrowableToken()).safeTransfer(msg.sender, feeAmount);
        }
    }

    /// @notice sets BigBang specific configuration
    /// @dev values are updated only if > 0 or not address(0)
    /// @param _minDebtRate the minimum debt rate (5000000000000000 is 0.5%)
    /// @param _maxDebtRate the maximum debt rate (50000000000000000 is 5%)
    /// @param _debtRateAgainstEthMarket the debt ratio against the main BB market (200000000000000000 is 20%)
    /// @param _liquidationMultiplier the liquidation bonus percentage (12000 is 12%)
    function setBigBangConfig(
        uint256 _minDebtRate,
        uint256 _maxDebtRate,
        uint256 _debtRateAgainstEthMarket,
        uint256 _liquidationMultiplier
    ) external onlyOwner {
        isMainMarket = collateral() == _penrose.mainToken();

        if (_liquidationMultiplier > 0) {
            if (_liquidationMultiplier >= FEE_PRECISION) revert NotValid();
            emit LiquidationMultiplierUpdated(liquidationMultiplier, _liquidationMultiplier);
            liquidationMultiplier = _liquidationMultiplier;
        }

        if (!isMainMarket) {
            _accrue();
            if (_minDebtRate > 0) {
                if (_minDebtRate >= maxDebtRate) revert DebtRatesNotValid();
                emit MinDebtRateUpdated(minDebtRate, _minDebtRate);
                minDebtRate = _minDebtRate;
            }

            if (_maxDebtRate > 0) {
                if (_maxDebtRate <= minDebtRate) revert DebtRatesNotValid();
                if (_maxDebtRate > 1e18) revert DebtRatesNotValid();
                emit MaxDebtRateUpdated(maxDebtRate, _maxDebtRate);
                maxDebtRate = _maxDebtRate;
            }

            if (_debtRateAgainstEthMarket > 0) {
                emit DebtRateAgainstEthUpdated(debtRateAgainstEthMarket, _debtRateAgainstEthMarket);
                debtRateAgainstEthMarket = _debtRateAgainstEthMarket;
            }
        }
    }

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _extractModule(Module _module) internal view override returns (address) {
        address module;
        if (_module == Module.Base) {
            module = address(this);
        } else if (_module == Module.Borrow) {
            module = address(borrowModule);
        } else if (_module == Module.Collateral) {
            module = address(collateralModule);
        } else if (_module == Module.Liquidation) {
            module = address(liquidationModule);
        } else if (_module == Module.Leverage) {
            module = address(leverageModule);
        }

        if (module == address(0)) revert ModuleNotSet();

        return module;
    }

    function _executeModule(Module _module, bytes memory _data) private returns (bytes memory returnData) {
        bool success = true;

        (success, returnData) = _extractModule(_module).delegatecall(_data);
        if (!success) {
            revert(abi.decode(_getRevertMsg(returnData), (string)));
        }
    }

    receive() external payable {}
}
