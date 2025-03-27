// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// Tapioca
import {ILeverageExecutor} from "tap-utils/interfaces/bar/ILeverageExecutor.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {Module, PauseType} from "tap-utils/interfaces/bar/IMarket.sol";
import {Market} from "../Market.sol";
import {SGLLiquidation} from "./SGLLiquidation.sol";
import {SGLCollateral} from "./SGLCollateral.sol";
import {SGLLeverage} from "./SGLLeverage.sol";
import {SGLStorage} from "./SGLStorage.sol";
import {SGLCommon} from "./SGLCommon.sol";
import {SGLBorrow} from "./SGLBorrow.sol";
import {MarketERC4626} from "../MarketERC4626.sol";

// solhint-disable max-line-length

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/// @title Tapioca market
contract Singularity is SGLCommon {
    using SafeCast for uint256;
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;

    // ************ //
    // *** VARS *** //
    // ************ //
    /// @notice returns the liquidation module
    SGLLiquidation public liquidationModule;
    /// @notice returns the borrow module
    SGLBorrow public borrowModule;
    /// @notice returns the collateral module
    SGLCollateral public collateralModule;
    /// @notice returns the leverage module
    SGLLeverage public leverageModule;

    struct _InitMemoryTokensData {
        IERC20 _asset;
        IERC20 _collateral;
    }

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error ModuleNotSet();
    error NotAuthorized();
    error SameState();
    error MinLendAmountNotMet();

    function totalAssetSupply() public view returns (uint256) {
        return totalAsset.base;
    }

    function name() public view override(SGLStorage) returns (string memory) {
        return SGLStorage.name();
    }

    function symbol() public view override(SGLStorage) returns (string memory) {
        return SGLStorage.symbol();
    }

    /**
     * @notice Initializes the Singularity contract via the SGLInit contract
     */
    function init(address sglInit, bytes calldata initData) external onlyOnce {
        (bool success,) = sglInit.delegatecall(abi.encodeWithSignature("init(bytes)", initData));
        require(success, "Init failed");
    }

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    /// @notice Accrues the interest on the borrowed tokens and handles the accumulation of fees.
    function accrue() external override {
        if (pauseOptions[PauseType.AddCollateral] || pauseOptions[PauseType.RemoveCollateral]) revert AccruePaused();
        _accrue();
    }

    /// @notice Add liquidity to the lending pair.
    /// @param from Address to add liquidity from.
    /// @param to The address of the user to receive the assets.
    /// @param amount The amount of liquidity to supply
    /// @return fraction Total fractions added.
    function addAsset(address from, address to, uint256 amount) external nonReentrant returns (uint256 fraction) {
        _allowedLend(from, amount);
        _optionNotPaused(PauseType.AddAsset);
        if (amount <= minLendAmount) revert MinLendAmountNotMet();

        _accrue();

        IERC20(_asset).safeTransferFrom(from, address(this), amount);

        Rebase memory _totalAsset = totalAsset;
        uint256 allShare = _totalAsset.elastic + totalBorrow.elastic;
        fraction = allShare == 0 ? amount : (amount * _totalAsset.base) / allShare;
        if (_totalAsset.base + fraction.toUint128() < 1000) {
            return 0;
        }
        totalAsset = _totalAsset.add(amount, fraction);

        liquidityBalance[to] += fraction;

        emit LogAddAsset(from, to, amount, fraction);
    }

    /// @notice Removes an asset from `from` and transfers it to `to`.
    /// @param from Account to debit assets from.
    /// @param to The user that receives the removed assets.
    /// @param fraction The amount/fraction of assets held to remove.
    /// @return share The amount of shares transferred to `to`.
    function removeAsset(address from, address to, uint256 fraction) external nonReentrant returns (uint256 share) {
        _optionNotPaused(PauseType.RemoveAsset);
        _accrue();
        share = _removeAsset(from, to, fraction);
        _allowedLend(from, share);
    }

    // *********************** //
    // *** OWNER FUNCTIONS *** //
    // *********************** //

    /// @notice Transfers fees to penrose
    /// @dev can only be called by the owner or FEES_EXTRACTOR role
    /// @return feeAmount the amount of fees withdrawn under Penrose
    function refreshPenroseFees() external returns (uint256 feeAmount) {
        require(
            _cluster().hasRole(msg.sender, keccak256("FEES_EXTRACTOR")) || msg.sender == owner(),
            "Ownable: caller is not the owner"
        );
        address _feeTo = address(_penrose);
        // withdraw the fees accumulated in `accrueInfo.feesEarnedFraction` to the balance of `feeTo`.
        if (accrueInfo.feesEarnedFraction > 0) {
            _accrue();
            // Fees are in assets (asset liquidity), not shares.
            uint256 _feesEarnedFraction = accrueInfo.feesEarnedFraction;
            liquidityBalance[_feeTo] += _feesEarnedFraction;
            emit LogAddAsset(msg.sender, _feeTo, 0, _feesEarnedFraction);
            accrueInfo.feesEarnedFraction = 0;
            emit LogWithdrawFees(_feeTo, _feesEarnedFraction);
        }
        feeAmount = liquidityBalance[_feeTo];
        _removeAsset(_feeTo, msg.sender, liquidityBalance[_feeTo]);
    }

    /// @notice sets Singularity specific configuration
    /// @dev values are updated only if > 0 or not address(0)
    ///     - borrowOpeningFee is always updated!
    function setSingularityConfig(
        uint256 _borrowOpeningFee,
        uint256 _liquidationMultiplier,
        uint256 _minimumTargetUtilization,
        uint256 _maximumTargetUtilization,
        uint64 _minimumInterestPerSecond,
        uint64 _maximumInterestPerSecond,
        uint256 _interestElasticity,
        address _interestHelper,
        uint256 _minLendAmount
    ) external onlyOwner {
        // this needs to be set first
        // if `interestHelper` is address(0), the next _accrue() call won't work
        if (_interestHelper != address(0)) {
            emit InterestHelperUpdated(interestHelper, _interestHelper);
            interestHelper = _interestHelper;
        }

        _accrue();

        if (_borrowOpeningFee > FEE_PRECISION) revert NotValid();
        emit LogBorrowingFee(borrowOpeningFee, _borrowOpeningFee);
        borrowOpeningFee = _borrowOpeningFee;

        if (_minimumTargetUtilization > 0) {
            emit MinimumTargetUtilizationUpdated(minimumTargetUtilization, _minimumTargetUtilization);
            minimumTargetUtilization = _minimumTargetUtilization;
        }

        if (_maximumTargetUtilization > 0) {
            if (_maximumTargetUtilization >= 1e18) {
                //1e18 = FULL_UTILIZATION
                revert NotValid();
            }

            emit MaximumTargetUtilizationUpdated(maximumTargetUtilization, _maximumTargetUtilization);
            maximumTargetUtilization = _maximumTargetUtilization;
        }

        if (_minimumInterestPerSecond > 0) {
            if (_minimumInterestPerSecond >= maximumInterestPerSecond) {
                revert NotValid();
            }
            emit MinimumInterestPerSecondUpdated(minimumInterestPerSecond, _minimumInterestPerSecond);
            minimumInterestPerSecond = _minimumInterestPerSecond;
        }

        if (_maximumInterestPerSecond > 0) {
            if (_maximumInterestPerSecond <= minimumInterestPerSecond) {
                revert NotValid();
            }
            emit MaximumInterestPerSecondUpdated(maximumInterestPerSecond, _maximumInterestPerSecond);
            maximumInterestPerSecond = _maximumInterestPerSecond;
        }

        if (_interestElasticity > 0) {
            emit InterestElasticityUpdated(interestElasticity, _interestElasticity);
            interestElasticity = _interestElasticity;
        }

        if (_liquidationMultiplier > 0) {
            if (_liquidationMultiplier > FEE_PRECISION) revert NotValid();
            emit LiquidationMultiplierUpdated(liquidationMultiplier, _liquidationMultiplier);
            liquidationMultiplier = _liquidationMultiplier;
        }

        if (_minLendAmount > 0) {
            emit MinLendAmountUpdate(minLendAmount, _minLendAmount);
            minLendAmount = _minLendAmount;
        }
    }

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _extractModule(Module _module) internal view override returns (address) {
        address module;
        if (_module == Module.Base) {
            return address(this);
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

    /// @dev Concrete implementation of `removeAsset`.
    function _removeAsset(address from, address to, uint256 fraction) private returns (uint256 share) {
        if (totalAsset.base == 0) {
            return 0;
        }
        Rebase memory _totalAsset = totalAsset;
        uint256 allShare = _totalAsset.elastic + totalBorrow.elastic;
        share = (fraction * allShare) / _totalAsset.base;

        _totalAsset.base -= fraction.toUint128();
        liquidityBalance[from] -= fraction;

        if (_totalAsset.base < 1000) revert MinLimit();
        _totalAsset.elastic -= share.toUint128();
        totalAsset = _totalAsset;
        emit LogRemoveAsset(from, to, share, fraction);

        IERC20(_asset).safeTransfer(to, share);
    }

    receive() external payable {}
}
