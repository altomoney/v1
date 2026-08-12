// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    CurveConfig,
    IRState,
    IPegResponsiveIrmBase,
    IPegResponsiveIrmStaticTypes
} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IDusdPegOracleCurveBase} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";
import {ExpLib} from "@alto/lending/libraries/ExpLib.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

/// @title Price-Responsive Interest Rate Model
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Adjusts a mint market's borrow rate in response to a validated DUSD/quoteToken
/// peg price.
/// @dev This is a discrete, checkpoint-driven controller. Each update first
/// calculates interest for the elapsed interval using the previously stored
/// rate, then samples the oracle and stores a price-derived rate for the next
/// interval.
/// @dev The raw target is flat at `baseRate` above `recoveryPrice`, increases
/// linearly to `stressRate` at `stressPrice`, and increases exponentially below
/// `stressPrice` according to `doublingDistance`, subject to `maxRate`.
/// @dev Stress-mode hysteresis is applied separately from the raw curve. Stress
/// begins at or below `stressPrice` and keeps the effective rate at or above
/// `stressRate` until qualifying recovery checkpoints are separated by at least
/// `recoveryDelay`. This is sampled confirmation; the contract does not prove
/// continuous recovery between checkpoints.
/// @dev An unusable oracle observation holds the stored rate and stress-mode
/// status, but interrupts recovery confirmation. Observation freshness is
/// checked only when the controller is called and does not guarantee checkpoint
/// liveness.
/// @dev Prices, price distances, and rates use 1e18 fixed-point precision.
/// Rates are expressed as second percent yield (SPY). Delay and observation-age
/// parameters are expressed in seconds.
/// @dev The bound market must checkpoint immediately before pausing. Unpausing
/// resets the accrual timestamp and recovery confirmation but does not sample
/// the oracle or replace the pre-pause rate.
/// @dev `setMarket` is permissionless and one-shot. Deployment must bind the
/// intended market atomically or otherwise prevent an unintended first caller.
contract PegResponsiveIrm is AltoOwnable2Step, IPegResponsiveIrmStaticTypes {
    using FixedPointMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @inheritdoc IIrm
    IRMType public constant IRM_TYPE = IRMType.PEG_RESPONSIVE;

    /// @inheritdoc IPegResponsiveIrmBase
    uint256 public constant MAX_BORROW_RATE = 8e18 / uint256(365 days);

    /// @inheritdoc IPegResponsiveIrmBase
    uint256 public constant MAX_RECOVERY_PRICE = 1.01e18;

    /// @inheritdoc IPegResponsiveIrmBase
    uint256 public constant WAD = 1e18;

    /// @inheritdoc IPegResponsiveIrmBase
    uint256 public constant LN_2_WAD = 0.693147180559945309 ether;

    /// @inheritdoc IPegResponsiveIrmBase
    uint256 public constant MAX_EXPONENT_INPUT = 50e18;

    /// @inheritdoc IPegResponsiveIrmBase
    address public oracle;

    /// @inheritdoc IPegResponsiveIrmStaticTypes
    CurveConfig public curveConfig;

    /// @inheritdoc IPegResponsiveIrmStaticTypes
    IRState public irState;

    /// @inheritdoc IPegResponsiveIrmBase
    address public market;

    /// @notice Constructor.
    /// @param _oracle          Oracle returning a validated, timestamped DUSD/quoteToken price.
    /// @param _config          Initial curve, recovery, and oracle-freshness configuration.
    /// @param _initialOwner    Owner of the IRM.
    constructor(address _oracle, CurveConfig memory _config, address _initialOwner) Ownable(_initialOwner) {
        if (_oracle == address(0)) revert PegResponsiveIrmInvalidOracle();
        _validateConfig(_config);

        oracle = _oracle;
        curveConfig = _config;
        irState.borrowRate = _config.baseRate;

        emit SetPegOracle(address(0), _oracle);
        emit SetCurveConfig(_config);
        emit IRStateUpdated(irState);
    }

    /// @inheritdoc IIrm
    function setMarket(address _market) external {
        // No access control: Mirrors current IRM design. Must be deployed and
        // set in one transaction to avoid frontrunning.
        if (market != address(0)) revert IrmMarketAlreadySet();
        if (_market == address(0)) revert IrmInvalidParams();

        market = _market;
        irState.lastUpdate = block.timestamp.toUint48();

        emit IRStateUpdated(irState);
    }

    /// @inheritdoc IIrm
    function onMarketPause(bool _paused) external {
        if (msg.sender != market) revert IrmUnauthorized();

        // The market checkpoints immediately before pausing. Resetting on
        // unpause prevents interest from being charged for the paused interval.
        // Recovery confirmation is also restarted because no observations were
        // processed while the market was paused.
        if (!_paused) {
            irState.lastUpdate = block.timestamp.toUint48();
            _resetRecoveryConfirmation();
            emit IRStateUpdated(irState);
        }
    }

    /// @inheritdoc IIrm
    function updateInterestRateView(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        view
        returns (uint256 interest, uint256 borrowRate)
    {
        return _accrueInterest(_totalSupply, _totalBorrowed);
    }

    /// @inheritdoc IIrm
    function updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        external
        returns (uint256 interest, uint256 borrowRate)
    {
        if (msg.sender != market) revert IrmUnauthorized();
        return _updateInterestRate(_totalSupply, _totalBorrowed);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function setPegOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert PegResponsiveIrmInvalidOracle();

        _checkpointMarket();

        emit SetPegOracle(oracle, _newOracle);
        oracle = _newOracle;
        if (_resetRecoveryConfirmation()) emit IRStateUpdated(irState);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function setCurveConfig(CurveConfig calldata _newConfig) external onlyOwner {
        _validateConfig(_newConfig);
        _checkpointMarket();
        if (irState.borrowRate > _newConfig.maxRate) revert PegResponsiveIrmInvalidRateConfig();

        curveConfig = _newConfig;
        if (_resetRecoveryConfirmation()) emit IRStateUpdated(irState);
        emit SetCurveConfig(_newConfig);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function previewBorrowRate()
        external
        view
        returns (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 borrowRate)
    {
        (priceWad, observedAt, oracleValid) = _readPegPrice();

        if (!oracleValid) return (priceWad, observedAt, false, irState.borrowRate);

        (bool nextStressMode,) = _nextStressState(priceWad, true);
        borrowRate = _effectiveTargetRate(priceWad, nextStressMode);

        return (priceWad, observedAt, oracleValid, borrowRate);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function targetBorrowRate(uint256 _priceWad) public view returns (uint256 borrowRate) {
        CurveConfig memory cfg = curveConfig;

        // 1. Healthy price region: use the minimum configured borrow rate.
        if (_priceWad >= cfg.recoveryPrice) {
            return cfg.baseRate;
        }

        // 2. Recovery-to-stress region: linearly interpolate from baseRate to stressRate.
        if (_priceWad >= cfg.stressPrice) {
            uint256 drop = cfg.recoveryPrice - _priceWad;
            uint256 width = cfg.recoveryPrice - cfg.stressPrice;
            uint256 pos = Math.mulDiv(drop, WAD, width);
            uint256 rateRange = cfg.stressRate - cfg.baseRate;

            return cfg.baseRate + Math.mulDiv(rateRange, pos, WAD);
        }

        // 3. Stress region: increase the stress rate exponentially as price falls.
        uint256 stressDrop = cfg.stressPrice - _priceWad;

        // Convert the price decline into the input for e^x:
        //
        //      2^n = e^(ln(2) * n)
        //
        // where n is the number of configured doubling distances below stressPrice.
        uint256 exp = Math.mulDiv(LN_2_WAD, stressDrop, cfg.doublingDistance);
        exp = Math.min(exp, MAX_EXPONENT_INPUT);

        uint256 mul = ExpLib.wExp(exp.toInt256()).toUint256();
        uint256 uncappedRate = Math.mulDiv(cfg.stressRate, mul, WAD);

        return Math.min(uncappedRate, cfg.maxRate);
    }

    /// @dev Checkpoints the active market before an owner changes controller inputs.
    /// Does nothing when the IRM is not bound to a market or the market is paused.
    function _checkpointMarket() private {
        if (market != address(0) && !IMarket(market).paused(PAUSE_TYPE)) {
            IMarket(market).accrueInterest();
        }
    }

    /// @dev Calculates interest using the rate that was active throughout the
    /// elapsed interval.
    /// @dev The unused supply argument preserves parity with the IRM update interface.
    /// @param _totalBorrowed The market's total outstanding debt before accrual.
    /// @return interest    The interest accrued since the previous update.
    /// @return borrowRate  The stored borrow rate used to calculate the interest.
    function _accrueInterest(uint256, uint256 _totalBorrowed)
        private
        view
        returns (uint256 interest, uint256 borrowRate)
    {
        if (market == address(0)) revert IrmMarketNotSet();

        borrowRate = irState.borrowRate;
        uint256 dt = block.timestamp - irState.lastUpdate;
        interest = _totalBorrowed.multiplyWithPrecision(borrowRate.calculateCompoundInterest(dt));

        return (interest, borrowRate);
    }

    /// @dev Accrues the old rate first, then stores the oracle-driven rate for
    /// the next interval.
    /// @param _totalSupply     The market's total supplied assets before accrual.
    /// @param _totalBorrowed   The market's total outstanding debt before accrual.
    /// @return interest    The interest accrued using the previously stored rate.
    /// @return borrowRate  The previously stored borrow rate used for the elapsed interval.
    function _updateInterestRate(uint256 _totalSupply, uint256 _totalBorrowed)
        private
        returns (uint256 interest, uint256 borrowRate)
    {
        (interest, borrowRate) = _accrueInterest(_totalSupply, _totalBorrowed);

        (uint256 priceWad, uint48 observedAt, bool oracleValid) = _readPegPrice();
        bool nextStressMode = _applyStressState(priceWad, oracleValid);

        uint256 newRate = borrowRate;
        if (oracleValid) {
            newRate = _effectiveTargetRate(priceWad, nextStressMode);
        }

        irState.borrowRate = newRate;
        irState.lastUpdate = block.timestamp.toUint48();

        emit BorrowRateUpdated(borrowRate, newRate, priceWad, observedAt, oracleValid);
        emit IRStateUpdated(irState);

        return (interest, borrowRate);
    }

    /// @dev Returns the controller state implied by the latest observation.
    /// Invalid observations keep stress mode active but interrupt recovery
    /// confirmation.
    /// @param _priceWad    The latest reported DUSD/quoteToken price, using 1e18 precision.
    /// @param _oracleValid Whether the latest oracle observation is usable.
    /// @return stressMode          Whether the controller should be in stress mode.
    /// @return recoveryStartedAt   The recovery confirmation start time, or zero when inactive.
    function _nextStressState(uint256 _priceWad, bool _oracleValid)
        private
        view
        returns (bool stressMode, uint48 recoveryStartedAt)
    {
        IRState memory state = irState;
        CurveConfig memory config = curveConfig;

        // The oracle observation was invalid. Keep the current stress mode status.
        //
        // Reset the recovery timestamp so an invalid observation cannot count
        // towards completing recovery.
        if (!_oracleValid) {
            return (state.stressMode, 0);
        }

        // The system is not currently in stress mode.
        if (!state.stressMode) {
            // The price has reached or fallen below the stress threshold.
            // Enter stress mode with no recovery timer running.
            if (_priceWad <= config.stressPrice) return (true, 0);

            // The price is still above the stress threshold. Remain outside
            // stress mode.
            return (false, 0);
        }

        // From here onward, the system is already in stress mode.

        // The price has not yet reached the recovery threshold.
        // Remain stressed and cancel any recovery timer that may have started.
        if (_priceWad < config.recoveryPrice) {
            return (true, 0);
        }

        // The price is now at or above the recovery threshold, but no recovery
        // timer is currently running. Start the recovery confirmation period now.
        if (state.recoveryStartedAt == 0) {
            return (true, block.timestamp.toUint48());
        }

        // A recovery timer is already running.
        // If the required delay has elapsed, recovery is confirmed:
        // exit stress mode and clear the timer.
        if (block.timestamp - uint256(state.recoveryStartedAt) >= config.recoveryDelay) {
            return (false, 0);
        }

        // The price is still at or above the recovery threshold, but the required
        // recovery delay has not elapsed yet.
        // Remain stressed and preserve the original recovery start time.
        return (true, state.recoveryStartedAt);
    }

    /// @dev Applies and emits the stress state implied by the latest observation.
    /// @param _priceWad    The latest reported DUSD/quoteToken price, using 1e18 precision.
    /// @param _oracleValid Whether the latest oracle observation is usable.
    /// @return stressMode Whether the controller is in stress mode after the update.
    function _applyStressState(uint256 _priceWad, bool _oracleValid) private returns (bool stressMode) {
        bool previousStressMode = irState.stressMode;
        uint48 previousRecoveryStartedAt = irState.recoveryStartedAt;

        (bool nextStressMode, uint48 nextRecoveryStartedAt) = _nextStressState(_priceWad, _oracleValid);

        irState.stressMode = nextStressMode;
        irState.recoveryStartedAt = nextRecoveryStartedAt;

        if (previousStressMode != nextStressMode || previousRecoveryStartedAt != nextRecoveryStartedAt) {
            emit StressStateUpdated(nextStressMode, nextRecoveryStartedAt, _priceWad);
        }

        return nextStressMode;
    }

    /// @dev Applies the stress-mode floor to the raw price-derived target.
    /// @param _priceWad    The latest valid DUSD/quoteToken price, using 1e18 precision.
    /// @param _stressMode  Whether the controller is currently in stress mode.
    /// @return borrowRate The price-derived target rate after applying the stress floor.
    function _effectiveTargetRate(uint256 _priceWad, bool _stressMode) private view returns (uint256 borrowRate) {
        uint256 targetRate = targetBorrowRate(_priceWad);

        if (_stressMode && targetRate < curveConfig.stressRate) {
            return curveConfig.stressRate;
        }

        return targetRate;
    }

    /// @dev Interrupts an in-progress recovery confirmation.
    /// @return reset Whether an active recovery confirmation was cleared.
    function _resetRecoveryConfirmation() private returns (bool reset) {
        if (irState.recoveryStartedAt == 0) return false;

        irState.recoveryStartedAt = 0;
        emit StressStateUpdated(irState.stressMode, 0, 0);
        return true;
    }

    /// @dev Treats reverts, invalid flags, zero/future timestamps, stale data,
    /// and zero prices as unusable.
    /// @return priceWad    The reported DUSD/quoteToken price, or zero when unusable.
    /// @return observedAt  The oracle observation timestamp, or zero when the oracle call reverts.
    /// @return valid       Whether the observation passed all validation checks.
    function _readPegPrice() private view returns (uint256 priceWad, uint48 observedAt, bool valid) {
        try IDusdPegOracleCurveBase(oracle).getPrice() returns (uint256 _priceWad, uint48 _observedAt, bool _valid) {
            observedAt = _observedAt;

            if (!_valid || _priceWad == 0 || _observedAt == 0 || uint256(_observedAt) > block.timestamp) {
                return (0, observedAt, false);
            }

            if (block.timestamp - uint256(_observedAt) > curveConfig.maxOracleAge) {
                return (0, observedAt, false);
            }

            return (_priceWad, observedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    /// @dev Reverts when curve thresholds, rates, or controller timings are
    /// outside supported bounds.
    /// @param _config The curve configuration to validate.
    function _validateConfig(CurveConfig memory _config) private pure {
        // stressPrice must be nonzero and strictly below recoveryPrice.
        // Equal thresholds would make the linear bridge divide by zero, while
        // reversed thresholds would invalidate the ordering of the curve regions.
        // recoveryPrice is also limited to the supported oracle price range.
        //
        // baseRate must be nonzero and no greater than stressRate.
        // stressRate must be strictly below maxRate so the exponential region has
        // room to increase, and maxRate must not exceed the protocol safety limit.
        //
        // doublingDistance must be nonzero to prevent division by zero.
        // recoveryDelay and maxOracleAge must be nonzero so recovery confirmation
        // and oracle freshness validation cannot be disabled accidentally.

        // forgefmt: disable-next-item
        if (
            _config.stressPrice == 0 ||
            _config.recoveryPrice > MAX_RECOVERY_PRICE ||
            _config.stressPrice >= _config.recoveryPrice
        ) {
            revert PegResponsiveIrmInvalidPriceConfig();
        }

        // forgefmt: disable-next-item
        if (
            _config.baseRate == 0 ||
            _config.baseRate > _config.stressRate ||
            _config.stressRate >= _config.maxRate ||
            _config.maxRate > MAX_BORROW_RATE
        ) {
            revert PegResponsiveIrmInvalidRateConfig();
        }

        if (_config.doublingDistance == 0 || _config.recoveryDelay == 0 || _config.maxOracleAge == 0) {
            revert PegResponsiveIrmInvalidControllerConfig();
        }
    }
}
