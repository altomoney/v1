// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    PegResponsiveIrmConfig,
    IRState,
    IPegResponsiveIrmBase,
    IPegResponsiveIrmStaticTypes
} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IDusdPegOracle} from "@alto/oracles/dusd/interfaces/IDusdPegOracle.sol";
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
    address public pegOracle;

    /// @inheritdoc IPegResponsiveIrmStaticTypes
    PegResponsiveIrmConfig public irmConfig;

    /// @inheritdoc IPegResponsiveIrmStaticTypes
    IRState public irState;

    /// @inheritdoc IPegResponsiveIrmBase
    address public market;

    /// @notice Constructor.
    /// @param initialPegOracle Oracle returning a validated, timestamped DUSD/quoteToken price.
    /// @param initialConfig Initial curve, recovery, and oracle-freshness configuration.
    /// @param initialOwner Owner of the IRM.
    constructor(address initialPegOracle, PegResponsiveIrmConfig memory initialConfig, address initialOwner)
        Ownable(initialOwner)
    {
        if (initialPegOracle == address(0)) revert PegResponsiveIrmInvalidOracle();
        _validateConfig(initialConfig);

        pegOracle = initialPegOracle;
        irmConfig = initialConfig;
        irState.borrowRate = initialConfig.baseRate;

        emit SetPegOracle(address(0), initialPegOracle);
        emit SetIrmConfig(initialConfig);
        emit IRStateUpdated(irState);
    }

    /// @inheritdoc IIrm
    function setMarket(address newMarket) external {
        // No access control: Mirrors current IRM design. Must be deployed and
        // set in one transaction to avoid frontrunning.
        if (market != address(0)) revert IrmMarketAlreadySet();
        if (newMarket == address(0)) revert IrmInvalidParams();

        market = newMarket;
        irState.lastUpdate = block.timestamp.toUint48();

        emit IRStateUpdated(irState);
    }

    /// @inheritdoc IIrm
    function onMarketPause(bool paused) external {
        if (msg.sender != market) revert IrmUnauthorized();

        // The market checkpoints immediately before pausing. Resetting on
        // unpause prevents interest from being charged for the paused interval.
        // Recovery confirmation is also restarted because no observations were
        // processed while the market was paused.
        if (!paused) {
            irState.lastUpdate = block.timestamp.toUint48();
            _resetRecoveryConfirmation();
            emit IRStateUpdated(irState);
        }
    }

    /// @inheritdoc IIrm
    function updateInterestRateView(uint256, uint256 totalBorrowed)
        external
        view
        returns (uint256 interest, uint256 borrowRate)
    {
        return _accrueInterest(totalBorrowed);
    }

    /// @inheritdoc IIrm
    function updateInterestRate(uint256, uint256 totalBorrowed)
        external
        returns (uint256 interest, uint256 borrowRate)
    {
        if (msg.sender != market) revert IrmUnauthorized();
        return _updateInterestRate(totalBorrowed);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function setPegOracle(address newPegOracle) external onlyOwner {
        if (newPegOracle == address(0)) revert PegResponsiveIrmInvalidOracle();

        _checkpointMarket();

        emit SetPegOracle(pegOracle, newPegOracle);
        pegOracle = newPegOracle;
        if (_resetRecoveryConfirmation()) emit IRStateUpdated(irState);
    }

    /// @inheritdoc IPegResponsiveIrmBase
    function setIrmConfig(PegResponsiveIrmConfig calldata newConfig) external onlyOwner {
        _validateConfig(newConfig);
        _checkpointMarket();
        if (irState.borrowRate > newConfig.maxRate) revert PegResponsiveIrmInvalidRateConfig();

        irmConfig = newConfig;
        if (_resetRecoveryConfirmation()) emit IRStateUpdated(irState);
        emit SetIrmConfig(newConfig);
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
    function targetBorrowRate(uint256 priceWad) public view returns (uint256 borrowRate) {
        PegResponsiveIrmConfig memory config = irmConfig;

        if (priceWad >= config.recoveryPrice) return config.baseRate;

        if (priceWad >= config.stressPrice) {
            uint256 position =
                Math.mulDiv(config.recoveryPrice - priceWad, WAD, config.recoveryPrice - config.stressPrice);
            uint256 rateIncrease = Math.mulDiv(config.stressRate - config.baseRate, position, WAD);

            return config.baseRate + rateIncrease;
        }

        uint256 stressDrop = config.stressPrice - priceWad;

        // Convert the price decline into the input for e^x:
        //
        //      2^n = e^(ln(2) * n)
        //
        // where n is the number of configured doubling distances below stressPrice.
        uint256 exponent = Math.min(Math.mulDiv(LN_2_WAD, stressDrop, config.doublingDistance), MAX_EXPONENT_INPUT);
        uint256 multiplier = ExpLib.wExp(exponent.toInt256()).toUint256();

        return Math.min(Math.mulDiv(config.stressRate, multiplier, WAD), config.maxRate);
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
    /// @param totalBorrowed The market's total outstanding debt before accrual.
    /// @return interest    The interest accrued since the previous update.
    /// @return borrowRate  The stored borrow rate used to calculate the interest.
    function _accrueInterest(uint256 totalBorrowed) private view returns (uint256 interest, uint256 borrowRate) {
        if (market == address(0)) revert IrmMarketNotSet();

        borrowRate = irState.borrowRate;
        uint256 dt = block.timestamp - irState.lastUpdate;
        interest = totalBorrowed.multiplyWithPrecision(borrowRate.calculateCompoundInterest(dt));

        return (interest, borrowRate);
    }

    /// @dev Accrues the old rate first, then stores the oracle-driven rate for
    /// the next interval.
    /// @param totalBorrowed The market's total outstanding debt before accrual.
    /// @return interest    The interest accrued using the previously stored rate.
    /// @return borrowRate  The previously stored borrow rate used for the elapsed interval.
    function _updateInterestRate(uint256 totalBorrowed) private returns (uint256 interest, uint256 borrowRate) {
        (interest, borrowRate) = _accrueInterest(totalBorrowed);

        (uint256 priceWad, uint48 observedAt, bool oracleValid) = _readPegPrice();
        bool nextStressMode = _applyStressState(priceWad, oracleValid);
        uint256 newRate = oracleValid ? _effectiveTargetRate(priceWad, nextStressMode) : borrowRate;

        irState.borrowRate = newRate;
        irState.lastUpdate = block.timestamp.toUint48();

        emit BorrowRateUpdated(borrowRate, newRate, priceWad, observedAt, oracleValid);
        emit IRStateUpdated(irState);

        return (interest, borrowRate);
    }

    /// @dev Returns the controller state implied by the latest observation.
    /// Invalid observations keep stress mode active but interrupt recovery
    /// confirmation.
    /// @param priceWad The latest reported DUSD/quoteToken price, using 1e18 precision.
    /// @param oracleValid Whether the latest oracle observation is usable.
    /// @return stressMode          Whether the controller should be in stress mode.
    /// @return recoveryStartedAt   The recovery confirmation start time, or zero when inactive.
    function _nextStressState(uint256 priceWad, bool oracleValid)
        private
        view
        returns (bool stressMode, uint48 recoveryStartedAt)
    {
        IRState memory state = irState;
        PegResponsiveIrmConfig memory config = irmConfig;

        // Invalid observations preserve stress mode but interrupt recovery.
        if (!oracleValid) return (state.stressMode, 0);

        // Crossing the stress threshold enters stress mode immediately.
        if (!state.stressMode) return (priceWad <= config.stressPrice, 0);

        // Falling below the recovery threshold interrupts recovery.
        if (priceWad < config.recoveryPrice) return (true, 0);

        // The first healthy checkpoint starts recovery confirmation.
        if (state.recoveryStartedAt == 0) return (true, block.timestamp.toUint48());

        // A later healthy checkpoint exits stress once the delay has elapsed.
        if (block.timestamp - uint256(state.recoveryStartedAt) < config.recoveryDelay) {
            return (true, state.recoveryStartedAt);
        }

        return (false, 0);
    }

    /// @dev Applies and emits the stress state implied by the latest observation.
    /// @param priceWad The latest reported DUSD/quoteToken price, using 1e18 precision.
    /// @param oracleValid Whether the latest oracle observation is usable.
    /// @return stressMode Whether the controller is in stress mode after the update.
    function _applyStressState(uint256 priceWad, bool oracleValid) private returns (bool stressMode) {
        uint48 recoveryStartedAt;
        (stressMode, recoveryStartedAt) = _nextStressState(priceWad, oracleValid);
        _setStressState(stressMode, recoveryStartedAt, priceWad);
    }

    /// @dev Applies the stress-mode floor to the raw price-derived target.
    /// @param priceWad The latest valid DUSD/quoteToken price, using 1e18 precision.
    /// @param stressMode Whether the controller is currently in stress mode.
    /// @return borrowRate The price-derived target rate after applying the stress floor.
    function _effectiveTargetRate(uint256 priceWad, bool stressMode) private view returns (uint256 borrowRate) {
        uint256 targetRate = targetBorrowRate(priceWad);
        return stressMode ? Math.max(targetRate, irmConfig.stressRate) : targetRate;
    }

    /// @dev Interrupts an in-progress recovery confirmation.
    /// @return reset Whether an active recovery confirmation was cleared.
    function _resetRecoveryConfirmation() private returns (bool reset) {
        return _setStressState(irState.stressMode, 0, 0);
    }

    /// @dev Stores and emits a stress-state transition when either field changes.
    /// @return changed Whether the stress state changed.
    function _setStressState(bool stressMode, uint48 recoveryStartedAt, uint256 priceWad)
        private
        returns (bool changed)
    {
        if (irState.stressMode == stressMode && irState.recoveryStartedAt == recoveryStartedAt) {
            return false;
        }

        irState.stressMode = stressMode;
        irState.recoveryStartedAt = recoveryStartedAt;
        emit StressStateUpdated(stressMode, recoveryStartedAt, priceWad);
        return true;
    }

    /// @dev Treats reverts, invalid flags, zero/future timestamps, stale data,
    /// and zero prices as unusable.
    /// @return priceWad    The reported DUSD/quoteToken price, or zero when unusable.
    /// @return observedAt  The oracle observation timestamp, or zero when the oracle call reverts.
    /// @return valid       Whether the observation passed all validation checks.
    function _readPegPrice() private view returns (uint256 priceWad, uint48 observedAt, bool valid) {
        try IDusdPegOracle(pegOracle).getPrice() returns (
            uint256 reportedPriceWad, uint48 reportedAt, bool observationValid
        ) {
            observedAt = reportedAt;

            // Keep this order: each timestamp check relies on the prior checks
            // short-circuiting before the age subtraction.
            if (
                !observationValid || reportedPriceWad == 0 || reportedAt == 0 || uint256(reportedAt) > block.timestamp
                    || block.timestamp - uint256(reportedAt) > irmConfig.maxOracleAge
            ) {
                return (0, observedAt, false);
            }

            return (reportedPriceWad, observedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    /// @dev Reverts when curve thresholds, rates, or controller timings are
    /// outside supported bounds.
    /// @param config The IRM configuration to validate.
    function _validateConfig(PegResponsiveIrmConfig memory config) private pure {
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
            config.stressPrice == 0 ||
            config.recoveryPrice > MAX_RECOVERY_PRICE ||
            config.stressPrice >= config.recoveryPrice
        ) {
            revert PegResponsiveIrmInvalidPriceConfig();
        }

        // forgefmt: disable-next-item
        if (
            config.baseRate == 0 ||
            config.baseRate > config.stressRate ||
            config.stressRate >= config.maxRate ||
            config.maxRate > MAX_BORROW_RATE
        ) {
            revert PegResponsiveIrmInvalidRateConfig();
        }

        if (config.doublingDistance == 0 || config.recoveryDelay == 0 || config.maxOracleAge == 0) {
            revert PegResponsiveIrmInvalidControllerConfig();
        }
    }
}
