// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {BaseMarketInitParams, MintMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {PegResponsiveExponentialIrmConfig} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {OracleMock} from "@alto-test/helpers/OracleMock.sol";
import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {DusdPegCurveOracleValidationConfig} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";
import {MockCurveStableSwapFactory} from "@alto-test/oracles/btt/mocks/MockCurveStableSwapFactory.sol";
import {MockCurveStableSwapNG} from "@alto-test/oracles/btt/mocks/MockCurveStableSwapNG.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";

import {DusdPegCurveOracleCommon} from "@alto-test/oracles/btt/DusdPegCurveOracle/DusdPegCurveOracleCommon.t.sol";

contract DusdPegOracleIntegrationTest is DusdPegCurveOracleCommon {
    uint256 private constant YEAR = 365 days;
    uint256 private constant RECOVERY_PRICE = 1e18;
    uint256 private constant STRESS_PRICE = 0.995e18;
    uint256 private constant MID_BRIDGE_PRICE = 0.9975e18;
    uint256 private constant BASE_RATE = 0.05e18 / YEAR;
    uint256 private constant STRESS_RATE = 0.075e18 / YEAR;
    uint256 private constant MAX_RATE = 8e18 / YEAR;
    uint256 private constant DOUBLING_DISTANCE = 0.0025e18;
    uint256 private constant HELD_RATE = STRESS_RATE * 2;
    uint256 private constant DEEP_DEPEG_PRICE = STRESS_PRICE - DOUBLING_DISTANCE;
    uint48 private constant RECOVERY_DELAY = 6 hours;
    uint256 private constant CHECKPOINT_INTERVAL = 15 minutes;
    uint48 private constant MAX_ORACLE_AGE = 30 minutes;
    address private constant KEEPER = address(0xC0FFEE);
    uint256 private constant MARKET_MAX_LTV = 0.75e18;
    uint256 private constant MARKET_DEBT_CEILING = 1_000_000e18;

    ERC20MockMintable private borrowToken;
    ERC20Mock private collateralToken;

    PegResponsiveExponentialIrm private irm;
    AltoMintMarket private market;

    function setUp() public override {
        super.setUp();
        irm = new PegResponsiveExponentialIrm(address(oracle), _validIrmConfig(), OWNER);
        market = _deployMintMarket();

        assertEq(market.irm(), address(irm), "market IRM");
        assertEq(irm.market(), address(market), "IRM market");
    }

    function test_ValidAdapterObservationFlowsThroughPreviewAndCheckpoint() external {
        _setPoolObservation(MID_BRIDGE_PRICE, uint48(block.timestamp));
        uint256 expectedRate = irm.targetBorrowRate(MID_BRIDGE_PRICE);

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = irm.previewBorrowRate();
        assertEq(priceWad, MID_BRIDGE_PRICE, "priceWad");
        assertEq(observedAt, block.timestamp, "observedAt");
        assertTrue(oracleValid, "oracleValid");
        assertEq(previewRate, expectedRate, "previewRate");

        market.accrueInterest();
        (uint256 borrowRate,,,) = irm.irState();
        assertEq(borrowRate, expectedRate, "checkpoint borrowRate");
    }

    /// @dev Shows that a new pool observation is applied only when any caller checkpoints the Mint Market.
    function test_PoolObservationWaitsForPermissionlessMintMarketCheckpointAndOldRateAccrues() external {
        uint256 borrowedAssets = 100e18;
        _openDebt(borrowedAssets);

        (uint256 initialRate, uint48 initialLastUpdate,,) = irm.irState();
        assertEq(initialRate, BASE_RATE, "initial rate");
        _setPoolObservation(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        vm.warp(block.timestamp + CHECKPOINT_INTERVAL);

        (uint256 storedRateBefore, uint48 lastUpdateBefore,,) = irm.irState();
        (uint128 debtAssetsBefore,) = market.totalBorrowed();
        (uint128 supplyAssetsBefore,) = market.totalSupply();
        (uint256 expectedInterest, uint256 activeRate) =
            irm.updateInterestRateView(supplyAssetsBefore, debtAssetsBefore);
        assertEq(activeRate, BASE_RATE, "active rate before checkpoint");
        assertGt(expectedInterest, 0, "expected interest");
        assertEq(storedRateBefore, BASE_RATE, "oracle update must not change stored rate");
        assertEq(lastUpdateBefore, initialLastUpdate, "oracle update must not checkpoint");

        vm.prank(KEEPER);
        market.accrueInterest();

        (uint128 debtAssetsAfter,) = market.totalBorrowed();
        (uint256 storedRateAfter, uint48 lastUpdateAfter, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(uint256(debtAssetsAfter), uint256(debtAssetsBefore) + expectedInterest, "interest accrued at old rate");
        assertEq(market.claimableFeesAssets(), expectedInterest, "mint market interest accounting");
        assertEq(storedRateAfter, HELD_RATE, "depeg rate installed prospectively");
        assertEq(lastUpdateAfter, block.timestamp, "permissionless checkpoint time");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt");
        assertTrue(stressMode, "stressMode");
    }

    /// @dev Shows that sampled recovery remains in stress mode one second before the configured delay.
    function test_RecoveryRemainsStressedAtDelayMinusOne() external {
        _assertRecoveryBoundary(RECOVERY_DELAY - 1, true);
    }

    /// @dev Shows that a qualifying sampled recovery completes exactly at the configured delay.
    function test_RecoveryCompletesAtExactDelay() external {
        _assertRecoveryBoundary(RECOVERY_DELAY, false);
    }

    /// @dev Shows that a qualifying sampled recovery also completes after the configured delay.
    function test_RecoveryCompletesAtDelayPlusOne() external {
        _assertRecoveryBoundary(RECOVERY_DELAY + 1, false);
    }

    /// @dev Shows that one observation can start and complete recovery while its age equals the freshness limit.
    function test_SameObservationCanStartAndCompleteRecoveryAtFreshnessEquality() external {
        PegResponsiveExponentialIrmConfig memory config = _validIrmConfig();
        config.maxOracleAge = RECOVERY_DELAY;
        vm.prank(OWNER);
        irm.setIrmConfig(config);

        _setHeldRate();
        uint48 observedAt = uint48(block.timestamp);
        _setPoolObservation(RECOVERY_PRICE, observedAt);
        market.accrueInterest();
        (uint256 startingRate,, uint48 recoveryStartedAt, bool startingStressMode) = irm.irState();
        assertEq(startingRate, STRESS_RATE, "recovery floor");
        assertEq(recoveryStartedAt, observedAt, "recovery start");
        assertTrue(startingStressMode, "starting stressMode");

        vm.warp(block.timestamp + RECOVERY_DELAY);
        market.accrueInterest();
        (uint256 recoveredRate,, uint48 recoveredAt, bool recoveredStressMode) = irm.irState();
        assertEq(recoveredRate, BASE_RATE, "same-observation recovery rate");
        assertEq(recoveredAt, 0, "recovery timer cleared");
        assertFalse(recoveredStressMode, "recovered stressMode");
    }

    /// @dev Shows that a stale observation before stress holds the base rate but still advances the checkpoint time.
    function test_StaleObservationBeforeStressHoldsBaseRateAndAdvancesCheckpoint() external {
        vm.warp(block.timestamp + 1 minutes);
        uint48 observedAt = uint48(block.timestamp - MAX_ORACLE_AGE - 1);
        _setPoolObservation(DEEP_DEPEG_PRICE, observedAt);

        (uint256 oraclePrice, uint48 oracleObservedAt, bool adapterValid) = oracle.getPrice();
        assertEq(oraclePrice, DEEP_DEPEG_PRICE, "adapter price");
        assertEq(oracleObservedAt, observedAt, "adapter observedAt");
        assertTrue(adapterValid, "adapter accepts source state");

        (uint256 previewPrice, uint48 previewObservedAt, bool oracleValid, uint256 previewRate) =
            irm.previewBorrowRate();
        assertEq(previewPrice, 0, "PRM priceWad");
        assertEq(previewObservedAt, observedAt, "PRM observedAt");
        assertFalse(oracleValid, "PRM oracleValid");
        assertEq(previewRate, BASE_RATE, "held healthy rate");

        market.accrueInterest();
        (uint256 borrowRate, uint48 lastUpdate, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(borrowRate, BASE_RATE, "stored rate");
        assertEq(lastUpdate, block.timestamp, "successful checkpoint time");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt");
        assertFalse(stressMode, "stressMode");
    }

    /// @dev Shows that a Curve source revert during stress holds both the stored rate and stress mode.
    function test_CurveSourceRevertDuringStressHoldsRateAndMode() external {
        _setHeldRate();
        _mockPoolReadRevert(_priceOracleCall());

        _expectPoolReadRevert();
        oracle.getPrice();

        _assertInvalidPreview(0);
        market.accrueInterest();
        _assertHeldRate();
    }

    /// @dev Shows that a policy-invalid Curve state during stress holds both the stored rate and stress mode.
    function test_PolicyInvalidityDuringStressHoldsRateAndMode() external {
        uint48 observedAt = uint48(block.timestamp);
        _setHeldRate();
        _setPoolObservation(MID_BRIDGE_PRICE, observedAt);
        pool.setMaExpTime(MA_EXP_TIME + 1);

        (uint256 oraclePrice, uint48 oracleObservedAt, bool adapterValid) = oracle.getPrice();
        assertEq(oraclePrice, 0, "adapter price");
        assertEq(oracleObservedAt, observedAt, "adapter observedAt");
        assertFalse(adapterValid, "adapter valid");

        _assertInvalidPreview(observedAt);
        market.accrueInterest();
        _assertHeldRate();
    }

    /// @dev Shows that a stale observation during stress holds both the stored rate and stress mode.
    function test_StaleObservationDuringStressHoldsRateAndMode() external {
        uint48 observedAt = uint48(block.timestamp - MAX_ORACLE_AGE - 1);
        _setHeldRate();
        _setPoolObservation(MID_BRIDGE_PRICE, observedAt);

        (uint256 oraclePrice, uint48 oracleObservedAt, bool adapterValid) = oracle.getPrice();
        assertEq(oraclePrice, MID_BRIDGE_PRICE, "adapter price");
        assertEq(oracleObservedAt, observedAt, "adapter observedAt");
        assertTrue(adapterValid, "adapter valid");

        _assertInvalidPreview(observedAt);
        market.accrueInterest();
        _assertHeldRate();
    }

    /// @dev Replacement checkpoints the old oracle and immediately applies the new observation.
    function test_NewOracleAppliesImmediatelyAfterReplacement() external {
        DusdPegCurveOracle replacementOracle = _deployIndependentOracle(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        _setPoolObservation(MID_BRIDGE_PRICE, uint48(block.timestamp));

        vm.prank(OWNER);
        irm.setPegOracle(address(replacementOracle));

        assertEq(irm.pegOracle(), address(replacementOracle), "replacement oracle");
        (uint256 storedRate,, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(storedRate, HELD_RATE, "new-oracle rate applies immediately");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt");
        assertTrue(stressMode, "stressMode after replacement");

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = irm.previewBorrowRate();
        assertEq(priceWad, DEEP_DEPEG_PRICE, "new-oracle price");
        assertEq(observedAt, block.timestamp, "new-oracle observedAt");
        assertTrue(oracleValid, "new-oracle valid");
        assertEq(previewRate, HELD_RATE, "new-oracle preview rate");

        market.accrueInterest();
        (storedRate,, recoveryStartedAt, stressMode) = irm.irState();
        assertEq(storedRate, HELD_RATE, "new-oracle rate after checkpoint");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt after checkpoint");
        assertTrue(stressMode, "stressMode after checkpoint");
    }

    /// @dev A healthy observation applies the new base rate during the setter.
    function test_NewCurveConfigAppliesNewBaseImmediately() external {
        PegResponsiveExponentialIrmConfig memory newConfig = _validIrmConfig();
        newConfig.baseRate = (BASE_RATE + STRESS_RATE) / 2;
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));

        vm.prank(OWNER);
        irm.setIrmConfig(newConfig);

        (uint256 storedRate,, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(storedRate, newConfig.baseRate, "new base applies immediately");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt");
        assertFalse(stressMode, "stressMode");
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE), newConfig.baseRate, "new configured base");

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = irm.previewBorrowRate();
        assertEq(priceWad, RECOVERY_PRICE, "priceWad");
        assertEq(observedAt, block.timestamp, "observedAt");
        assertTrue(oracleValid, "oracleValid");
        assertEq(previewRate, newConfig.baseRate, "new-config preview rate");

        market.accrueInterest();
        (storedRate,, recoveryStartedAt, stressMode) = irm.irState();
        assertEq(storedRate, newConfig.baseRate, "new-config rate after checkpoint");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt after checkpoint");
        assertFalse(stressMode, "stressMode after checkpoint");
    }

    /// @dev A depeg observation applies the new stressed curve during the setter.
    function test_NewCurveConfigWhileStressedAppliesImmediately() external {
        _setHeldRate();
        PegResponsiveExponentialIrmConfig memory newConfig = _validIrmConfig();
        newConfig.stressRate = HELD_RATE + 1;

        vm.prank(OWNER);
        irm.setIrmConfig(newConfig);

        (uint256 storedRate,, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(storedRate, irm.targetBorrowRate(DEEP_DEPEG_PRICE), "new stressed rate applies immediately");
        assertGe(storedRate, newConfig.stressRate, "new stress floor");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt");
        assertTrue(stressMode, "stressMode");

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = irm.previewBorrowRate();
        assertEq(priceWad, DEEP_DEPEG_PRICE, "priceWad");
        assertEq(observedAt, block.timestamp, "observedAt");
        assertTrue(oracleValid, "oracleValid");
        uint256 expectedTarget = irm.targetBorrowRate(DEEP_DEPEG_PRICE);
        assertEq(previewRate, expectedTarget, "new stressed preview rate");

        market.accrueInterest();
        (storedRate,, recoveryStartedAt, stressMode) = irm.irState();
        assertEq(storedRate, expectedTarget, "new stressed rate after checkpoint");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt after checkpoint");
        assertTrue(stressMode, "stressMode after checkpoint");
    }

    /// @dev Shows that replacement while recovering uses the old oracle checkpoint, then clears recovery confirmation.
    function test_ReplacingOracleWhileRecoveringUsesOldOracleThenClearsRecovery() external {
        _startRecovery();
        DusdPegCurveOracle replacementOracle = _deployIndependentOracle(DEEP_DEPEG_PRICE, uint48(block.timestamp));

        vm.prank(OWNER);
        irm.setPegOracle(address(replacementOracle));

        (uint256 storedRate,, uint48 recoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(storedRate, HELD_RATE, "new-oracle depeg rate");
        assertEq(recoveryStartedAt, 0, "replacement clears recovery");
        assertTrue(stressMode, "stressMode after replacement");
        assertEq(irm.pegOracle(), address(replacementOracle), "replacement oracle");

        market.accrueInterest();
        (storedRate,, recoveryStartedAt, stressMode) = irm.irState();
        assertEq(storedRate, HELD_RATE, "replacement rate after checkpoint");
        assertEq(recoveryStartedAt, 0, "recoveryStartedAt after checkpoint");
        assertTrue(stressMode, "stressMode after checkpoint");
    }

    /// @dev Paused setters refresh the rate without accruing interest for the paused interval.
    function test_ReplacingOracleAndConfigWhilePausedSkipsCheckpointAndClearsRecovery() external {
        _startRecovery();
        _setMarketPaused(true);

        DusdPegCurveOracle replacementOracle = _deployIndependentOracle(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        PegResponsiveExponentialIrmConfig memory newConfig = _validIrmConfig();
        newConfig.baseRate = (BASE_RATE + STRESS_RATE) / 2;
        (, uint48 lastUpdateBefore, uint48 recoveryBefore, bool stressBefore) = irm.irState();
        assertGt(recoveryBefore, 0, "active recovery setup");

        vm.startPrank(OWNER);
        irm.setPegOracle(address(replacementOracle));
        irm.setIrmConfig(newConfig);
        vm.stopPrank();

        (uint256 rateAfter, uint48 lastUpdateAfter, uint48 recoveryAfter, bool stressAfter) = irm.irState();
        assertEq(rateAfter, HELD_RATE, "setters refresh paused rate");
        assertEq(lastUpdateAfter, lastUpdateBefore, "setters skip paused checkpoint");
        assertEq(recoveryAfter, 0, "setter clears recovery");
        assertEq(stressAfter, stressBefore, "setters preserve stress mode");
        assertEq(irm.pegOracle(), address(replacementOracle), "paused oracle replacement");
        assertEq(irm.targetBorrowRate(RECOVERY_PRICE), newConfig.baseRate, "paused config replacement");
    }

    /// @dev An unbound controller refreshes its rate without starting the accrual clock.
    function test_UnboundOracleReplacementChangesInputWithoutCheckpointing() external {
        DusdPegCurveOracle replacementOracle = _deployIndependentOracle(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        PegResponsiveExponentialIrm unboundIrm =
            new PegResponsiveExponentialIrm(address(oracle), _validIrmConfig(), OWNER);

        vm.prank(OWNER);
        unboundIrm.setPegOracle(address(replacementOracle));

        assertEq(unboundIrm.market(), address(0), "unbound market");
        assertEq(unboundIrm.pegOracle(), address(replacementOracle), "unbound replacement oracle");
        (uint256 storedRate, uint48 lastUpdate, uint48 recoveryStartedAt, bool stressMode) = unboundIrm.irState();
        assertEq(storedRate, HELD_RATE, "unbound stored rate");
        assertEq(lastUpdate, 0, "unbound lastUpdate");
        assertEq(recoveryStartedAt, 0, "unbound recoveryStartedAt");
        assertTrue(stressMode, "unbound stressMode");
    }

    /// @dev Shows that a deep depeg during pause is not sampled until a checkpoint after unpause.
    function test_DeepDepegDuringPauseWaitsForPostUnpauseCheckpoint() external {
        (, uint48 initialLastUpdate,,) = irm.irState();
        vm.warp(block.timestamp + CHECKPOINT_INTERVAL);
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));
        _setMarketPaused(true);

        (uint256 pausedRate, uint48 pausedLastUpdate,, bool pausedStressMode) = irm.irState();
        assertEq(pausedRate, BASE_RATE, "pre-pause checkpoint rate");
        assertEq(pausedLastUpdate, block.timestamp, "pre-pause checkpoint time");
        assertGt(pausedLastUpdate, initialLastUpdate, "pause must checkpoint first");
        assertFalse(pausedStressMode, "pre-pause stressMode");

        vm.warp(block.timestamp + 1 hours);
        _setPoolObservation(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        _setMarketPaused(false);

        (uint256 unpausedRate, uint48 unpausedLastUpdate, uint48 recoveryStartedAt, bool unpausedStressMode) =
            irm.irState();
        assertEq(unpausedRate, BASE_RATE, "unpause retains pre-pause rate");
        assertEq(unpausedLastUpdate, block.timestamp, "unpause resets accrual time");
        assertEq(recoveryStartedAt, 0, "unpause recoveryStartedAt");
        assertFalse(unpausedStressMode, "unpause does not sample depeg");

        market.accrueInterest();
        (uint256 refreshedRate, uint48 refreshedAt, uint48 refreshedRecovery, bool refreshedStressMode) = irm.irState();
        assertEq(refreshedRate, HELD_RATE, "post-unpause depeg rate");
        assertEq(refreshedAt, block.timestamp, "post-unpause checkpoint time");
        assertEq(refreshedRecovery, 0, "post-unpause recoveryStartedAt");
        assertTrue(refreshedStressMode, "post-unpause stressMode");
    }

    /// @dev Shows that recovery during pause starts a new confirmation timer only at a post-unpause checkpoint.
    function test_FullRecoveryDuringPauseStartsNewRecoveryOnlyAfterCheckpoint() external {
        _setHeldRate();
        _setMarketPaused(true);
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));

        vm.warp(block.timestamp + RECOVERY_DELAY + 1);
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));

        (uint256 pausedRate,, uint48 pausedRecovery, bool pausedStressMode) = irm.irState();
        assertEq(pausedRate, HELD_RATE, "healthy pause interval retains stressed rate");
        assertEq(pausedRecovery, 0, "healthy pause interval does not start recovery");
        assertTrue(pausedStressMode, "healthy pause interval retains stressMode");

        _setMarketPaused(false);

        (uint256 unpausedRate,, uint48 unpausedRecovery, bool unpausedStressMode) = irm.irState();
        assertEq(unpausedRate, HELD_RATE, "unpause retains stressed rate");
        assertEq(unpausedRecovery, 0, "pause time does not start recovery");
        assertTrue(unpausedStressMode, "unpause retains stressMode");

        market.accrueInterest();
        (uint256 postCheckpointRate,, uint48 postCheckpointRecovery, bool postCheckpointStressMode) = irm.irState();
        assertEq(postCheckpointRate, STRESS_RATE, "recovery checkpoint floor");
        assertEq(postCheckpointRecovery, block.timestamp, "recovery starts after unpause");
        assertTrue(postCheckpointStressMode, "recovery remains stressed");
    }

    /// @dev Shows that an oracle revert does not block unpause and makes the next checkpoint hold the stored rate.
    function test_OracleRevertDoesNotBlockUnpauseAndNextCheckpointHoldsRate() external {
        _setHeldRate();
        _setMarketPaused(true);
        vm.warp(block.timestamp + 1 hours);
        _mockPoolReadRevert(_priceOracleCall());
        _setMarketPaused(false);

        (uint256 unpausedRate, uint48 unpausedAt, uint48 unpausedRecovery, bool unpausedStressMode) = irm.irState();
        assertEq(unpausedRate, HELD_RATE, "oracle-invalid unpause rate");
        assertEq(unpausedAt, block.timestamp, "oracle-invalid unpause time");
        assertEq(unpausedRecovery, 0, "oracle-invalid unpause recovery");
        assertTrue(unpausedStressMode, "oracle-invalid unpause stressMode");

        market.accrueInterest();
        (uint256 checkpointRate, uint48 checkpointAt, uint48 checkpointRecovery, bool checkpointStressMode) =
            irm.irState();
        assertEq(checkpointRate, HELD_RATE, "invalid checkpoint held rate");
        assertEq(checkpointAt, block.timestamp, "invalid checkpoint time");
        assertEq(checkpointRecovery, 0, "invalid checkpoint recovery");
        assertTrue(checkpointStressMode, "invalid checkpoint stressMode");
    }

    function test_LoweringCapAccruesOldDebtBeforeApplyingNewRate() external {
        _openDebt(100e18);
        _setHeldRate();
        vm.warp(block.timestamp + CHECKPOINT_INTERVAL);
        _setPoolObservation(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        (uint128 debtBefore, uint128 sharesBefore) = market.totalBorrowed();
        uint256 feesBefore = market.claimableFeesAssets();
        (uint256 oldInterest, uint256 oldRate) = irm.updateInterestRateView(0, debtBefore);
        assertEq(oldRate, HELD_RATE);
        assertGt(oldInterest, 0);
        PegResponsiveExponentialIrmConfig memory newConfig = _validIrmConfig();
        newConfig.maxRate = STRESS_RATE + 1;

        vm.prank(OWNER);
        irm.setIrmConfig(newConfig);

        (uint128 debtAfter, uint128 sharesAfter) = market.totalBorrowed();
        assertEq(uint256(debtAfter), uint256(debtBefore) + oldInterest);
        assertEq(sharesAfter, sharesBefore);
        assertEq(market.claimableFeesAssets(), feesBefore + oldInterest);
        (uint256 storedRate, uint48 updatedAt,, bool stressed) = irm.irState();
        assertEq(storedRate, newConfig.maxRate);
        assertEq(updatedAt, block.timestamp);
        assertTrue(stressed);
        (uint256 immediateInterest,) = irm.updateInterestRateView(0, debtAfter);
        assertEq(immediateInterest, 0);

        vm.warp(block.timestamp + CHECKPOINT_INTERVAL);
        (uint256 nextInterest, uint256 nextRate) = irm.updateInterestRateView(0, debtAfter);
        assertEq(nextRate, newConfig.maxRate);
        _setPoolObservation(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        market.accrueInterest();
        (uint128 finalDebt,) = market.totalBorrowed();
        assertEq(uint256(finalDebt), uint256(debtAfter) + nextInterest);
    }

    function test_OracleReplacementAccruesOldRateBeforeApplyingNewObservation() external {
        _openDebt(100e18);
        vm.warp(block.timestamp + CHECKPOINT_INTERVAL);
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));
        DusdPegCurveOracle replacement = _deployIndependentOracle(DEEP_DEPEG_PRICE, uint48(block.timestamp));
        (uint128 debtBefore,) = market.totalBorrowed();
        (uint256 oldInterest, uint256 oldRate) = irm.updateInterestRateView(0, debtBefore);
        assertEq(oldRate, BASE_RATE);
        assertGt(oldInterest, 0);

        vm.prank(OWNER);
        irm.setPegOracle(address(replacement));

        (uint128 debtAfter,) = market.totalBorrowed();
        assertEq(uint256(debtAfter), uint256(debtBefore) + oldInterest);
        (uint256 storedRate,,,) = irm.irState();
        assertEq(storedRate, HELD_RATE);
        (uint256 immediateInterest,) = irm.updateInterestRateView(0, debtAfter);
        assertEq(immediateInterest, 0);
    }

    function _setMarketPaused(bool paused) private {
        vm.prank(OWNER);
        market.pause(PAUSE_TYPE, paused);
        assertEq(market.paused(PAUSE_TYPE), paused, "market pause state");
    }

    function _validIrmConfig() private pure returns (PegResponsiveExponentialIrmConfig memory config) {
        config = PegResponsiveExponentialIrmConfig({
            recoveryPrice: RECOVERY_PRICE,
            stressPrice: STRESS_PRICE,
            baseRate: BASE_RATE,
            stressRate: STRESS_RATE,
            maxRate: MAX_RATE,
            doublingDistance: DOUBLING_DISTANCE,
            recoveryDelay: RECOVERY_DELAY,
            maxOracleAge: MAX_ORACLE_AGE
        });
    }

    function _deployMintMarket() private returns (AltoMintMarket deployedMarket) {
        borrowToken = new ERC20MockMintable("DUSD", "DUSD");
        collateralToken = new ERC20Mock("Collateral", "COLL");
        OracleMock lendingOracle = new OracleMock();
        lendingOracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        DlbDcfPriorityLiquidationEngine liquidationEngine = new DlbDcfPriorityLiquidationEngine(OWNER);
        MintMarketInitParams memory params = MintMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: address(borrowToken),
                collateralToken: address(collateralToken),
                irm: address(irm),
                owner: OWNER,
                emergencyAdmin: OWNER,
                oracle: address(lendingOracle),
                maxLtv: MARKET_MAX_LTV,
                feeRecipient: OWNER,
                liquidationEngine: address(liquidationEngine)
            }),
            debtCeiling: MARKET_DEBT_CEILING,
            initialBorrowOpeningFee: 0
        });

        deployedMarket = AltoMintMarket(MarketDeployer.deployMintMarket(params));
    }

    function _openDebt(uint256 borrowedAssets) private {
        uint256 collateralAssets = borrowedAssets * 2;
        deal(address(collateralToken), address(this), collateralAssets);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, address(this));
        market.borrow(borrowedAssets, 0, address(this), address(this), hex"");
    }

    function _deployIndependentOracle(uint256 priceWad, uint48 observedAt)
        private
        returns (DusdPegCurveOracle deployedOracle)
    {
        MockCurveStableSwapNG replacementPool =
            new MockCurveStableSwapNG(_addressArray(QUOTE_TOKEN, DUSD), MA_EXP_TIME, A_PRECISE);
        replacementPool.setMaLastTime(_pack128(observedAt, uint128(block.timestamp)));
        replacementPool.setBalances(_uint256Array(QUOTE_TOKEN_BALANCE, DUSD_BALANCE));
        replacementPool.setPriceData(0, CURRENT_STATE_PRICE_WAD, LAST_STATE_PRICE_WAD, STORED_EMA_PRICE_WAD, priceWad);

        MockCurveStableSwapFactory replacementFactory = new MockCurveStableSwapFactory();
        replacementFactory.registerPool(
            address(replacementPool), _addressArray(QUOTE_TOKEN, DUSD), _uint8Array(0, 0), POOL_IMPLEMENTATION, false
        );

        DusdPegCurveOracleValidationConfig memory validationConfig = DusdPegCurveOracleValidationConfig({
            curveFactory: address(replacementFactory),
            expectedCurvePoolImplementation: POOL_IMPLEMENTATION,
            dusd: DUSD,
            quoteToken: QUOTE_TOKEN
        });

        deployedOracle =
            new DusdPegCurveOracle(address(replacementPool), _validRuntimeConfig(), validationConfig, OWNER);
    }

    function _setPoolObservation(uint256 priceWad, uint48 observedAt) private {
        pool.setMaLastTime(_pack128(observedAt, uint128(block.timestamp)));
        _setPoolPriceData(CURRENT_STATE_PRICE_WAD, LAST_STATE_PRICE_WAD, STORED_EMA_PRICE_WAD, priceWad);
    }

    function _startRecovery() private returns (uint48 recoveryStartedAt) {
        _setHeldRate();
        recoveryStartedAt = uint48(block.timestamp);
        _setPoolObservation(RECOVERY_PRICE, recoveryStartedAt);
        market.accrueInterest();
        (uint256 borrowRate,, uint48 storedRecoveryStartedAt, bool stressMode) = irm.irState();
        assertEq(borrowRate, STRESS_RATE, "recovery floor setup");
        assertEq(storedRecoveryStartedAt, recoveryStartedAt, "recovery timer setup");
        assertTrue(stressMode, "recovery stressMode setup");
    }

    function _assertRecoveryBoundary(uint256 elapsed, bool remainsStressed) private {
        uint48 recoveryStartedAt = _startRecovery();
        vm.warp(block.timestamp + elapsed);
        _setPoolObservation(RECOVERY_PRICE, uint48(block.timestamp));
        market.accrueInterest();

        (uint256 borrowRate, uint48 lastUpdate, uint48 storedRecoveryStartedAt, bool stressMode) = irm.irState();
        uint256 expectedRate = remainsStressed ? STRESS_RATE : BASE_RATE;
        assertEq(borrowRate, expectedRate, "recovery boundary rate");
        assertEq(lastUpdate, block.timestamp, "recovery boundary checkpoint");
        assertEq(storedRecoveryStartedAt, remainsStressed ? recoveryStartedAt : 0, "recovery boundary timer");
        assertEq(stressMode, remainsStressed, "recovery boundary stressMode");
    }

    function _setHeldRate() private {
        _setPoolObservation(STRESS_PRICE - DOUBLING_DISTANCE, uint48(block.timestamp));
        market.accrueInterest();
        (uint256 borrowRate,,, bool stressMode) = irm.irState();
        assertEq(borrowRate, HELD_RATE, "held-rate setup");
        assertTrue(stressMode, "held-rate stressMode setup");
    }

    function _assertInvalidPreview(uint48 expectedObservedAt) private view {
        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 borrowRate) = irm.previewBorrowRate();
        assertEq(priceWad, 0, "PRM priceWad");
        assertEq(observedAt, expectedObservedAt, "PRM observedAt");
        assertFalse(oracleValid, "PRM oracleValid");
        assertEq(borrowRate, HELD_RATE, "PRM preview borrowRate");
    }

    function _assertHeldRate() private view {
        (uint256 borrowRate,,, bool stressMode) = irm.irState();
        assertEq(borrowRate, HELD_RATE, "stored borrowRate");
        assertTrue(stressMode, "stressMode");
    }
}
