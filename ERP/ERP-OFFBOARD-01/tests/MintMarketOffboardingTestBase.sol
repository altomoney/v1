// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {MintBorrowerList, MintMarketOffboardingIO} from "../libraries/MintMarketOffboardingIO.sol";
import {
    MintMarketOffboardingBorrowerMarket,
    MintMarketOffboardingInput,
    MintMarketOffboardingManifest,
    MintMarketOffboardingMarket,
    MintMarketOffboardingPhase,
    MintMarketOffboardingReport,
    MintMarketOffboardingSchedulePhase,
    MintMarketOffboardingSeverity
} from "../IMintMarketOffboarding.sol";
import {MintMarketOffboardingScript} from "../scripts/MintMarketOffboarding.s.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket, IMarketBase, MarketType, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {
    IDcfDlbPriorityLiquidationEngineErrors
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MintMarketOffboardingTestHarness is MintMarketOffboardingScript {
    function runPhase(
        MintMarketOffboardingPhase phase,
        MintMarketOffboardingManifest memory manifest,
        MintMarketOffboardingInput memory input
    ) external returns (MintMarketOffboardingInput memory) {
        return _runPhase(phase, manifest, input);
    }

    function _writeBorrowerList(string memory, MintMarketOffboardingManifest memory manifest)
        internal
        view
        override
        returns (MintBorrowerList memory)
    {
        return MintMarketOffboardingIO.parseBorrowerList(
            vm.readFile(MintMarketOffboardingIO.borrowerListPath(manifest))
        );
    }
}

abstract contract MintMarketOffboardingTestBase is Test {
    struct TimelockArtifactBatch {
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
    }

    uint256 internal constant FORK_BLOCK = 25_810_052;
    uint256 internal constant MARKET_COUNT = 7;
    uint256 internal constant TEMPORARY_CEILING = 1e30;
    uint256 internal constant FUTURE_FEE_WINDOW = 1 days;

    string internal constant MANIFEST_FILE = "ERP/ERP-OFFBOARD-01/config/mint-market-offboarding.json";
    string internal constant BORROWER_FIXTURE = "ERP/ERP-OFFBOARD-01/tests/fixtures/borrowers-25810052.json";
    string internal constant FREEZE_FILE = "batch-a-freeze-safe.json";
    string internal constant CONTAIN_SCHEDULE_FILE = "batch-a-containment-schedule.json";
    string internal constant CONTAIN_EXECUTE_FILE = "batch-a-containment-execute.json";
    string internal constant FIXED_IRM_SCHEDULE_FILE = "batch-b-fixed-rate-irm-schedule.json";
    string internal constant FIXED_IRM_EXECUTE_FILE = "batch-b-fixed-rate-irm-execute.json";
    string internal constant REDUCE_LTV_SCHEDULE_FILE = "batch-b-irm-and-ltv-update-schedule.json";
    string internal constant REDUCE_LTV_EXECUTE_FILE = "batch-b-irm-and-ltv-update-execute.json";
    string internal constant RECOVER_SCHEDULE_FILE = "batch-c-final-removal-schedule.json";
    string internal constant RECOVER_EXECUTE_FILE = "batch-c-final-removal-execute.json";

    MintMarketOffboardingTestHarness internal scriptHarness;
    MintMarketOffboardingManifest internal manifest;
    MintMarketOffboardingInput internal input;
    TimelockController internal timelock;
    IDUSD internal dusd;
    IMarketRegistry internal marketRegistry;

    address[] internal mintMarkets;
    uint256[] internal initialOraclePrices;
    uint256[] internal expectedBatchAClaims;
    MintMarketOffboardingBorrowerMarket[] internal borrowerFixtureMarkets;
    MintMarketOffboardingBorrowerMarket[] internal testBorrowerMarkets;

    // Fork and manifest setup.

    /// @dev Pinned fork block. Override together with `_manifestFile` and `_borrowerFixture` to run the helpers against
    /// another activation manifest.
    function _forkBlock() internal pure virtual returns (uint256) {
        return FORK_BLOCK;
    }

    function _manifestFile() internal pure virtual returns (string memory) {
        return MANIFEST_FILE;
    }

    function _borrowerFixture() internal pure virtual returns (string memory) {
        return BORROWER_FIXTURE;
    }

    function _loadManifest() internal view virtual returns (MintMarketOffboardingManifest memory) {
        return MintMarketOffboardingIO.loadActivationManifest(_manifestFile());
    }

    function _validateRegistryCoverage() internal view virtual {
        _assertManifestCoversAllOrdinaryMintMarkets();
    }

    /// @dev Existing phase-specific suites use deterministic seeded positions on top of the pinned live state.
    function _setUpManifest() internal {
        _setUpLiveManifest();
        _prepareSeededMarkets();
        _setApprovedContainmentTargets();
    }

    /// @dev Loads the checked-in activation and borrower fixture without modifying protocol state.
    function _setUpLiveManifest() internal {
        scriptHarness = new MintMarketOffboardingTestHarness();
        MintMarketOffboardingManifest memory loaded = _loadManifest();
        _storeManifest(loaded);
        assertEq(manifest.sourceBlock, _forkBlock(), "manifest fork block changed");

        vm.createSelectFork(vm.rpcUrl("ethereum"), _forkBlock());
        assertEq(block.number, _forkBlock(), "wrong fork block");

        input = MintMarketOffboardingIO.loadCurrentChainInput(manifest.deploymentId);
        if (input.contracts.ownerFixedRateIrmFactory.code.length == 0) {
            input.contracts.ownerFixedRateIrmFactory = address(0);
        }
        _bindManifestState();
        _validateRegistryCoverage();
        _loadBorrowerFixture();
    }

    function _loadBorrowerFixture() private {
        string memory json = vm.readFile(_borrowerFixture());
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "borrower fixture chain mismatch");
        assertEq(vm.parseJsonUint(json, ".sourceBlock"), _forkBlock(), "borrower fixture block mismatch");

        MintBorrowerList memory borrowerList = MintMarketOffboardingIO.parseBorrowerList(json);
        assertEq(borrowerList.markets.length, mintMarkets.length, "borrower fixture market count mismatch");
        delete borrowerFixtureMarkets;
        delete testBorrowerMarkets;
        for (uint256 i; i < borrowerList.markets.length; ++i) {
            assertEq(borrowerList.markets[i].market, mintMarkets[i], "borrower fixture market order mismatch");
            borrowerFixtureMarkets.push();
            MintMarketOffboardingBorrowerMarket storage stored = borrowerFixtureMarkets[i];
            stored.market = borrowerList.markets[i].market;
            for (uint256 j; j < borrowerList.markets[i].borrowers.length; ++j) {
                stored.borrowers.push(borrowerList.markets[i].borrowers[j]);
            }

            testBorrowerMarkets.push();
            testBorrowerMarkets[i].market = mintMarkets[i];
        }
    }

    function _storeManifest(MintMarketOffboardingManifest memory source) private {
        manifest.activationId = source.activationId;
        manifest.severity = source.severity;
        manifest.schedulePhase = source.schedulePhase;
        manifest.t0 = source.t0;
        manifest.step = source.step;
        manifest.lastExecutedStep = source.lastExecutedStep;
        manifest.lastStepExecutedAt = source.lastStepExecutedAt;
        manifest.lastOperationId = source.lastOperationId;
        manifest.sourceBlock = source.sourceBlock;
        manifest.deploymentId = source.deploymentId;
        manifest.freezerSafe = source.freezerSafe;
        manifest.timelockSafe = source.timelockSafe;
        manifest.fixedRateIrmVersion = source.fixedRateIrmVersion;

        delete manifest.markets;
        for (uint256 i; i < source.markets.length; ++i) {
            _pushManifestMarket(source.markets[i]);
        }
    }

    function _pushManifestMarket(MintMarketOffboardingMarket memory source) internal {
        manifest.markets.push(source);
    }

    function _bindManifestState() internal {
        timelock = TimelockController(payable(input.contracts.timelock));
        dusd = IDUSD(input.contracts.dusd);
        marketRegistry = IMarketRegistry(input.contracts.marketRegistry);

        delete mintMarkets;
        delete initialOraclePrices;
        for (uint256 i; i < manifest.markets.length; ++i) {
            address market = manifest.markets[i].market;
            mintMarkets.push(market);
            initialOraclePrices.push(IOracle(IMarket(market).oracle()).getPrice());
        }
    }

    function _assertManifestCoversAllOrdinaryMintMarkets() private view {
        address[] memory registered = marketRegistry.getMintMarkets();
        uint256 ordinaryMintMarketCount;
        for (uint256 i; i < registered.length; ++i) {
            if (IMarketBase(registered[i]).MARKET_TYPE() != MarketType.MINT) continue;
            ++ordinaryMintMarketCount;
            assertTrue(_isManifestMarket(registered[i]), "registered Mint Market missing from manifest");
        }

        assertEq(ordinaryMintMarketCount, MARKET_COUNT, "unexpected ordinary Mint Market count");
        assertEq(manifest.markets.length, ordinaryMintMarketCount, "manifest Mint Market count mismatch");
        for (uint256 i; i < mintMarkets.length; ++i) {
            assertGt(mintMarkets[i].code.length, 0, "Mint Market not deployed at fork");
            assertEq(uint256(IMarketBase(mintMarkets[i]).MARKET_TYPE()), uint256(MarketType.MINT), "wrong market type");
            assertTrue(marketRegistry.isMintMarket(mintMarkets[i]), "Mint Market absent from registry");
        }
    }

    function _prepareSeededMarkets() private {
        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            if (market.paused(FROZEN_TYPE)) {
                vm.prank(manifest.freezerSafe);
                IPausable(address(market)).pause(FROZEN_TYPE, false);
            }
            assertFalse(market.paused(PAUSE_TYPE), "market paused before fixture setup");

            vm.startPrank(address(timelock));
            AltoMintMarket(address(market)).setDebtCeiling(TEMPORARY_CEILING);
            dusd.setMinterCeiling(address(market), TEMPORARY_CEILING);
            vm.stopPrank();

            address borrower = makeAddr(string.concat("mint-borrower-", vm.toString(i)));
            uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals());
            uint256 collateralValue =
                Math.mulDiv(collateralAssets, IOracle(market.oracle()).getPrice(), LENDING_ORACLE_PRICE_PRECISION);
            uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);
            assertGt(maximumBorrow, 20, "fixture borrow amount is too small");

            _openMintPosition(market, borrower, collateralAssets, maximumBorrow / 2);
            _registerTestBorrower(i, borrower);
        }
    }

    function _openMintPosition(IMarket market, address borrower, uint256 collateralAssets, uint256 borrowAssets)
        internal
    {
        IERC20 collateralToken = IERC20(market.collateralToken());
        deal(address(collateralToken), borrower, collateralAssets);
        vm.startPrank(borrower);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, borrower);
        market.borrow(borrowAssets, 0, borrower, borrower, "");
        vm.stopPrank();
    }

    // Phase setup and execution.

    function _setApprovedContainmentTargets() internal {
        uint256 executeAt = block.timestamp + timelock.getMinDelay();
        uint256 snapshotId = vm.snapshotState();
        uint256[] memory debtTargets = new uint256[](mintMarkets.length);
        uint256[] memory dusdTargets = new uint256[](mintMarkets.length);
        uint256[] memory claims = new uint256[](mintMarkets.length);
        uint256[] memory feeHeadroom = new uint256[](mintMarkets.length);

        vm.warp(executeAt);
        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket market = AltoMintMarket(mintMarkets[i]);
            market.accrueInterest();
            debtTargets[i] = IMarket(address(market)).totalBorrowed().assets + market.badDebtAssets();
            claims[i] = market.claimableFeesAssets();
            market.claimInterest(0);
        }

        vm.warp(executeAt + FUTURE_FEE_WINDOW);
        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket market = AltoMintMarket(mintMarkets[i]);
            market.accrueInterest();
            (uint256 minted,) = dusd.minterConfig(address(market));
            feeHeadroom[i] = market.claimableFeesAssets();
            dusdTargets[i] = minted + feeHeadroom[i];
        }
        require(vm.revertToState(snapshotId), "failed to restore target projection");

        delete expectedBatchAClaims;
        for (uint256 i; i < mintMarkets.length; ++i) {
            manifest.markets[i].debtCeiling = debtTargets[i];
            manifest.markets[i].dusdMinterCeiling = dusdTargets[i];
            expectedBatchAClaims.push(claims[i]);

            vm.startPrank(address(timelock));
            AltoMintMarket(mintMarkets[i]).setDebtCeiling(debtTargets[i] + 1);
            dusd.setMinterCeiling(mintMarkets[i], dusdTargets[i] + 1);
            vm.stopPrank();
        }
    }

    function _executeGeneratedBatchA() internal returns (bytes32 operationId) {
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_A_CONTAIN;
        input = scriptHarness.runPhase(phase, manifest, input);
        if (vm.exists(_artifactPath(FREEZE_FILE))) _executeSafeBatch(FREEZE_FILE, manifest.freezerSafe);
        operationId = _executeTimelockArtifacts(phase, CONTAIN_SCHEDULE_FILE, CONTAIN_EXECUTE_FILE, false);
    }

    function _executeConfiguredBatchA() internal {
        _executeGeneratedBatchA();
        _advanceSourceBlock();
    }

    function _executeFixedRatePhase() internal {
        _assertAllFrozenAndUnpaused();
        _executeTimelockPhase(
            MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );
    }

    function _prepareContainedMarkets(string memory activationId) internal {
        manifest.activationId = activationId;
        assertEq(block.number, _forkBlock(), "Batch A started at wrong block");
        for (uint256 i; i < mintMarkets.length; ++i) {
            assertFalse(IMarketBase(mintMarkets[i]).paused(FROZEN_TYPE), "market initially frozen");
        }

        _executeGeneratedBatchA();
        _assertAllFrozenAndUnpaused();
        _advanceSourceBlock();

        assertEq(block.number, _forkBlock() + 1, "Batch B generation block mismatch");
        assertEq(manifest.sourceBlock, block.number, "Batch B source block not synchronized");
    }

    function _executeBatchBFixedRate(string memory activationId) internal {
        _prepareContainedMarkets(activationId);
        _executeTimelockPhase(
            MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );
    }

    function _prepareRecoveryTerminalState(string memory activationId) internal {
        _executeBatchBToZeroDebt(activationId);
        _approveCurrentRecoveryResiduals();
    }

    function _executeBatchBToZeroDebt(string memory activationId) internal {
        _executeBatchBFixedRate(activationId);
        manifest.t0 = block.timestamp;

        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            address oracle = market.oracle();
            vm.mockCall(oracle, abi.encodeCall(IOracle.getPrice, ()), abi.encode(initialOraclePrices[i]));
        }
        _executeMediumCorrectionsToZero(manifest.t0);
    }

    function _executeMediumCorrectionsToZero(uint256 t0) private {
        manifest.severity = MintMarketOffboardingSeverity.MEDIUM;
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.t0 = t0;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);

        uint256[4] memory offsets = [uint256(1 days), 7 days, 14 days, 21 days];
        uint256[4] memory aprs = [uint256(0.1 ether), 0.2 ether, 0.4 ether, 0.8 ether];
        address liquidator = makeAddr("mint-batch-c-terminal-liquidator");
        for (uint256 i; i < offsets.length && !_allDebtCleared(); ++i) {
            _advanceTo(t0 + offsets[i]);
            manifest.step = i + 1;
            _setCorrectionInputs(aprs[i] / uint256(365 days), 0.05 ether);
            _prepareCorrectionTargets();
            _executeAndRecordCorrection();
            _liquidateManifestBorrowers(liquidator);
        }
        if (_allDebtCleared()) return;

        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.TERMINAL;
        _advanceTo(t0 + 28 days);
        _liquidateManifestBorrowers(liquidator);

        uint256 terminalSteps;
        while (!_allDebtCleared()) {
            require(terminalSteps++ < 24, "Batch C prerequisite exceeded terminal step bound");
            _advanceTo(manifest.lastStepExecutedAt + 1 hours);
            manifest.step = manifest.lastExecutedStep + 1;
            _setCorrectionInputs(0.8 ether / uint256(365 days), 0.05 ether);
            _prepareCorrectionTargets();
            _executeAndRecordCorrection();
            _liquidateManifestBorrowers(liquidator);
        }
    }

    function _executeAndRecordCorrection() private {
        bytes32 operationId = _correctionOperationId();
        _executeTimelockPhase(
            MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );
        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
    }

    function _claimFeesAndRepayAll(address skippedMarket, address skippedBorrower) internal {
        address payer = makeAddr("mint-recovery-payer");
        deal(address(dusd), payer, TEMPORARY_CEILING);

        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket market = AltoMintMarket(mintMarkets[i]);
            market.claimInterest(0);

            address[] memory borrowers = _forkBorrowers(i);
            uint256 totalBorrowShares = IMarket(address(market)).totalBorrowed().shares;
            uint256 listedBorrowShares;
            for (uint256 j; j < borrowers.length; ++j) {
                Position memory position = IMarket(address(market)).position(borrowers[j]);
                listedBorrowShares += position.borrowShares;
                if (position.borrowShares == 0 || (address(market) == skippedMarket && borrowers[j] == skippedBorrower))
                {
                    continue;
                }

                vm.prank(payer);
                IMarket(address(market)).repay(0, position.borrowShares, borrowers[j]);
            }
            assertEq(listedBorrowShares, totalBorrowShares, "stale recovery borrower list");
        }
    }

    function _approveCurrentRecoveryResiduals() internal {
        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            Balance memory borrowed = market.totalBorrowed();
            (uint256 minted,) = dusd.minterConfig(address(market));
            uint256 badDebtAssets = AltoMintMarket(address(market)).badDebtAssets();

            assertEq(borrowed.assets, 0, "recovery borrowed assets remain");
            assertEq(borrowed.shares, 0, "recovery borrowed shares remain");
            assertEq(AltoMintMarket(address(market)).claimableFeesAssets(), 0, "recovery fees remain");
            _assertFrozenAndUnpaused(market);

            manifest.markets[i].approvedRecoveryBadDebtAssets = badDebtAssets;
            manifest.markets[i].maxUnbackedDusdAssets = minted;
        }
    }

    function _seededBorrower(uint256 marketIndex) internal returns (address) {
        return makeAddr(string.concat("mint-borrower-", vm.toString(marketIndex)));
    }

    function _executeTimelockPhase(
        MintMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile
    ) internal returns (bytes32 operationId) {
        input = scriptHarness.runPhase(phase, manifest, input);
        operationId = _executeTimelockArtifacts(phase, scheduleFile, executeFile);
    }

    function _executeTimelockArtifacts(
        MintMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile
    ) internal returns (bytes32 operationId) {
        operationId = _executeTimelockArtifacts(phase, scheduleFile, executeFile, true);
    }

    function _executeTimelockArtifacts(
        MintMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile,
        bool advanceBlock
    ) internal returns (bytes32 operationId) {
        string memory executeJson = vm.readFile(_artifactPath(phase, executeFile));
        (, bytes memory executeData) = _jsonTransaction(executeJson, 0);
        operationId = _operationIdFromExecuteData(executeData);

        _executeSafeBatch(phase, scheduleFile, manifest.timelockSafe);
        assertTrue(timelock.isOperationPending(operationId), "Timelock operation is not pending");
        vm.warp(timelock.getTimestamp(operationId));
        assertTrue(timelock.isOperationReady(operationId), "Timelock operation is not ready");
        if (advanceBlock) vm.roll(block.number + 1);
        _executeSafeBatch(phase, executeFile, manifest.timelockSafe);
        assertTrue(timelock.isOperationDone(operationId), "Timelock operation was not executed");
        if (advanceBlock) manifest.sourceBlock = block.number;
    }

    function _executeSafeBatch(string memory fileName, address safe) internal {
        _executeSafeBatch(MintMarketOffboardingPhase.BATCH_A_CONTAIN, fileName, safe);
    }

    function _executeSafeBatch(MintMarketOffboardingPhase phase, string memory fileName, address safe) internal {
        string memory json = vm.readFile(_artifactPath(phase, fileName));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), safe, "wrong transaction Safe");

        uint256 transactionIndex;
        while (_jsonTransactionExists(json, transactionIndex)) {
            (address target, bytes memory data) = _jsonTransaction(json, transactionIndex);
            _callFrom(safe, target, data);
            ++transactionIndex;
        }
        assertGt(transactionIndex, 0, "empty Safe batch");
    }

    function _expectBatchARevert(string memory reason) internal {
        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_A_CONTAIN, reason);
    }

    function _expectPhaseRevert(MintMarketOffboardingPhase phase, string memory reason) internal {
        vm.expectRevert(bytes(reason));
        scriptHarness.runPhase(phase, manifest, input);
        vm.stopBroadcast();
    }

    // Batch B correction and simulation fixtures.

    function _correctionOperationId() internal view returns (bytes32 operationId) {
        MintMarketOffboardingReport memory report = MintMarketOffboarding._prepareRateAndLtvReduction(manifest, input);
        (,, operationId) = ERPOutputWriter.timelockCalldata(
            input.contracts.timelock, report.timelockBatch, report.timelockDelay, report.predecessor
        );
    }

    function _setCorrectionInputs(uint256 rateSpy, uint256 ltvReduction) internal {
        for (uint256 i; i < manifest.markets.length; ++i) {
            manifest.markets[i].correctionRateSpy = rateSpy;
            manifest.markets[i].ltvReduction = ltvReduction;
        }
    }

    function _prepareCorrectionTargets() internal returns (uint256[] memory expectedClaims) {
        expectedClaims = new uint256[](mintMarkets.length);
        uint256[] memory debtTargets = new uint256[](mintMarkets.length);
        vm.startPrank(address(timelock));
        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket(mintMarkets[i]).setDebtCeiling(TEMPORARY_CEILING);
            dusd.setMinterCeiling(mintMarkets[i], TEMPORARY_CEILING);
        }
        vm.stopPrank();

        uint256 snapshotId = vm.snapshotState();
        vm.warp(block.timestamp + timelock.getMinDelay());
        for (uint256 i; i < mintMarkets.length; ++i) {
            AltoMintMarket market = AltoMintMarket(mintMarkets[i]);
            market.accrueInterest();
            Balance memory borrowed = IMarket(address(market)).totalBorrowed();
            debtTargets[i] = borrowed.assets + market.badDebtAssets();
            expectedClaims[i] = market.claimableFeesAssets();
        }
        require(vm.revertToState(snapshotId), "failed to restore correction projection");
        for (uint256 i; i < mintMarkets.length; ++i) {
            manifest.markets[i].debtCeiling = debtTargets[i];
            manifest.markets[i].maxDusdMintedAssets = expectedClaims[i];
        }
    }

    function _advanceTo(uint256 timestamp) internal {
        if (block.timestamp < timestamp) vm.warp(timestamp);
        _advanceSourceBlock();
    }

    function _registerTestBorrower(uint256 marketIndex, address borrower) internal {
        testBorrowerMarkets[marketIndex].borrowers.push(borrower);
    }

    function _assertBorrowerListComplete(uint256 marketIndex) internal view {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        address[] memory borrowers = _forkBorrowers(marketIndex);
        uint256 listedBorrowShares;
        for (uint256 i; i < borrowers.length; ++i) {
            listedBorrowShares += market.position(borrowers[i]).borrowShares;
        }
        assertEq(listedBorrowShares, market.totalBorrowed().shares, "stale Mint borrower list");
    }

    function _forkBorrowers(uint256 marketIndex) internal view returns (address[] memory borrowers) {
        uint256 fixtureCount = borrowerFixtureMarkets[marketIndex].borrowers.length;
        uint256 testCount = testBorrowerMarkets[marketIndex].borrowers.length;
        borrowers = new address[](fixtureCount + testCount);
        for (uint256 i; i < fixtureCount; ++i) {
            borrowers[i] = borrowerFixtureMarkets[marketIndex].borrowers[i];
        }
        for (uint256 i; i < testCount; ++i) {
            borrowers[fixtureCount + i] = testBorrowerMarkets[marketIndex].borrowers[i];
        }
    }

    function _liquidateBorrowerList(IMarket market, address[] memory borrowers, address liquidator)
        private
        returns (uint256 liquidationCount)
    {
        IERC20 borrowToken = IERC20(market.borrowToken());
        deal(address(borrowToken), liquidator, type(uint128).max);
        vm.startPrank(liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        for (uint256 i; i < borrowers.length; ++i) {
            if (_attemptOrdinaryLiquidation(market, borrowers[i])) ++liquidationCount;
        }
        vm.stopPrank();
    }

    function _liquidateManifestBorrowers(address liquidator) internal returns (uint256 liquidationCount) {
        for (uint256 i; i < mintMarkets.length; ++i) {
            liquidationCount += _liquidateBorrowerList(IMarket(mintMarkets[i]), _forkBorrowers(i), liquidator);
        }
    }

    function _attemptOrdinaryLiquidation(IMarket market, address borrower) private returns (bool liquidated) {
        uint256 borrowSharesBefore = market.position(borrower).borrowShares;
        if (borrowSharesBefore == 0) return false;

        (bool success, bytes memory returnData) =
            address(market).call(abi.encodeCall(IMarketBase.liquidate, (borrower, bytes(""), bytes(""))));
        if (!success) {
            if (
                _selector(returnData)
                    == IDcfDlbPriorityLiquidationEngineErrors.DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition
                    .selector
            ) return false;
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }

        assertLt(market.position(borrower).borrowShares, borrowSharesBefore, "ordinary liquidation made no progress");
        return true;
    }

    function _allDebtCleared() internal view returns (bool) {
        for (uint256 i; i < mintMarkets.length; ++i) {
            Balance memory debt = IMarket(mintMarkets[i]).totalBorrowed();
            if (debt.assets != 0 || debt.shares != 0) return false;
        }
        return true;
    }

    function _writeSimulationInputs(string memory activationId, uint256[4] memory limits)
        internal
        returns (string memory simulationManifestPath)
    {
        simulationManifestPath = string.concat("ERP/ERP-OFFBOARD-01/output/", activationId, "-manifest.json");
        vm.writeFile(simulationManifestPath, vm.readFile(_manifestFile()));
        vm.writeJson(string.concat('"', activationId, '"'), simulationManifestPath, ".activationId");
        vm.writeJson(vm.toString(uint256(manifest.severity)), simulationManifestPath, ".severity");
        vm.writeJson(vm.toString(uint256(manifest.schedulePhase)), simulationManifestPath, ".schedulePhase");
        vm.writeJson(vm.toString(manifest.t0), simulationManifestPath, ".t0");
        vm.writeJson(vm.toString(manifest.step), simulationManifestPath, ".step");
        vm.writeJson(vm.toString(manifest.lastExecutedStep), simulationManifestPath, ".lastExecutedStep");
        vm.writeJson(vm.toString(manifest.lastStepExecutedAt), simulationManifestPath, ".lastStepExecutedAt");
        vm.writeJson(
            string.concat('"', vm.toString(manifest.lastOperationId), '"'), simulationManifestPath, ".lastOperationId"
        );
        vm.writeJson(vm.toString(manifest.sourceBlock), simulationManifestPath, ".sourceBlock");
        vm.writeJson(_simulationMarketsJson(limits), simulationManifestPath, ".markets");

        MintMarketOffboardingManifest memory simulationManifest = manifest;
        simulationManifest.activationId = activationId;
        string memory outputDirectory =
            MintMarketOffboarding.artifactDirectory(MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV, simulationManifest);
        vm.createDir(outputDirectory, true);
        _writeSimulationBorrowers(string.concat(outputDirectory, "/borrowers.json"));
    }

    function _writeCurrentSimulationInputs() internal returns (string memory simulationManifestPath) {
        require(manifest.markets.length == 1, "current simulation helper requires one market");
        MintMarketOffboardingMarket memory market = manifest.markets[0];
        uint256[4] memory limits = [
            market.maxLiquidationFundingAssets,
            market.maxBadDebtAssets,
            market.maxDusdMintedAssets,
            market.maxSeizedCollateralAssets
        ];
        return _writeSimulationInputs(manifest.activationId, limits);
    }

    function _simulationMarketsJson(uint256[4] memory limits) private view returns (string memory json) {
        for (uint256 i; i < manifest.markets.length; ++i) {
            json = string.concat(json, i == 0 ? "" : ",", _simulationMarketJson(manifest.markets[i], limits));
        }
        return string.concat("[", json, "]");
    }

    function _simulationMarketJson(MintMarketOffboardingMarket memory market, uint256[4] memory limits)
        private
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"approvedRecoveryBadDebtAssets":',
            vm.toString(market.approvedRecoveryBadDebtAssets),
            ',"market":"',
            vm.toString(market.market),
            '","leverage":"',
            vm.toString(market.leverage),
            '","debtCeiling":',
            vm.toString(market.debtCeiling),
            ',"dusdMinterCeiling":',
            vm.toString(market.dusdMinterCeiling),
            ',"fixedRateSpy":',
            vm.toString(market.fixedRateSpy),
            ',"correctionRateSpy":',
            vm.toString(market.correctionRateSpy),
            ',"ltvReduction":',
            vm.toString(market.ltvReduction)
        );
        return string.concat(
            json,
            ',"maxLiquidationFundingAssets":',
            vm.toString(limits[0]),
            ',"maxBadDebtAssets":',
            vm.toString(limits[1]),
            ',"maxDusdMintedAssets":',
            vm.toString(limits[2]),
            ',"maxSeizedCollateralAssets":',
            vm.toString(limits[3]),
            ',"maxUnbackedDusdAssets":',
            vm.toString(market.maxUnbackedDusdAssets),
            "}"
        );
    }

    function _writeSimulationBorrowers(string memory path) private {
        string memory marketsJson;
        for (uint256 i; i < mintMarkets.length; ++i) {
            address[] memory borrowers = _forkBorrowers(i);
            string memory borrowersJson;
            for (uint256 j; j < borrowers.length; ++j) {
                borrowersJson = string.concat(borrowersJson, j == 0 ? "" : ",", '"', vm.toString(borrowers[j]), '"');
            }
            marketsJson = string.concat(
                marketsJson,
                i == 0 ? "" : ",",
                '{"borrowers":[',
                borrowersJson,
                '],"market":"',
                vm.toString(mintMarkets[i]),
                '"}'
            );
        }
        vm.writeFile(
            path,
            string.concat(
                '{"chainId":',
                vm.toString(block.chainid),
                ',"markets":[',
                marketsJson,
                '],"sourceBlock":',
                vm.toString(manifest.sourceBlock),
                ',"subgraphUrl":"test-fixture"}'
            )
        );
    }

    // Protocol-state assertions.

    function _assertContainmentState(uint256 marketIndex, uint256 mintedBefore) internal view {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        Balance memory borrowedAfter = market.totalBorrowed();
        Balance memory supplyAfter = market.totalSupply();
        (uint256 mintedAfter, uint256 ceilingAfter) = dusd.minterConfig(address(market));

        _assertFrozenAndUnpaused(market);
        assertEq(supplyAfter.assets, manifest.markets[marketIndex].debtCeiling, "wrong debt ceiling");
        assertEq(
            borrowedAfter.assets + AltoMintMarket(address(market)).badDebtAssets(),
            manifest.markets[marketIndex].debtCeiling,
            "debt ceiling does not match accrued exposure"
        );
        assertEq(AltoMintMarket(address(market)).claimableFeesAssets(), 0, "Batch A fees remain claimable");
        assertEq(mintedAfter - mintedBefore, expectedBatchAClaims[marketIndex], "wrong DUSD fee mint");
        assertEq(ceilingAfter, manifest.markets[marketIndex].dusdMinterCeiling, "wrong DUSD minter ceiling");
    }

    function _assertEntrancesBlocked(uint256 marketIndex) internal {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        address borrower = makeAddr(string.concat("mint-borrower-", vm.toString(marketIndex)));
        (uint256 mintedBefore,) = dusd.minterConfig(address(market));

        _assertFrozenRevert(
            address(market),
            borrower,
            abi.encodeCall(IMarketBase.addCollateral, (1, borrower)),
            "addCollateral succeeded"
        );
        _assertFrozenRevert(
            address(market),
            borrower,
            abi.encodeCall(IMarketBase.borrow, (1, 0, borrower, borrower, bytes(""))),
            "direct borrow succeeded"
        );
        _assertFrozenRevert(
            address(market),
            borrower,
            abi.encodeCall(
                IMarketBase.borrow, (1, 0, borrower, manifest.markets[marketIndex].leverage, abi.encode(uint256(1)))
            ),
            "leveraged borrow succeeded"
        );

        (uint256 mintedAfter,) = dusd.minterConfig(address(market));
        assertEq(mintedAfter, mintedBefore, "blocked entry minted DUSD");
    }

    function _assertFrozenAndUnpaused(IMarketBase market) internal view {
        assertTrue(market.paused(FROZEN_TYPE), "market not frozen");
        assertFalse(market.paused(PAUSE_TYPE), "market paused");
    }

    function _assertAllFrozenAndUnpaused() internal view {
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertFrozenAndUnpaused(IMarketBase(mintMarkets[i]));
        }
    }

    function _assertAllRequiredExitIntegrationsActive() internal view {
        AltoAdapter adapter = AltoAdapter(payable(input.contracts.altoAdapter));
        ILiquidationPeripheryBase periphery = ILiquidationPeripheryBase(input.contracts.liquidationPeriphery);
        for (uint256 i; i < mintMarkets.length; ++i) {
            address marketAddress = mintMarkets[i];
            IMarket market = IMarket(marketAddress);
            AltoLeverage leverage = AltoLeverage(manifest.markets[i].leverage);

            assertTrue(marketRegistry.isMintMarket(marketAddress), "Mint Market is not registered");
            assertTrue(adapter.isApprovedContract(marketAddress), "AltoAdapter approval is missing");
            assertTrue(leverage.supportedMarkets(marketAddress), "leverage support is missing");
            assertTrue(market.authorizedCallbacks(address(leverage)), "leverage callback is missing");
            assertTrue(leverage.swapper().isWhitelisted(address(leverage)), "swapper permission is missing");
            assertTrue(periphery.supportedMarkets(marketAddress), "liquidation support is missing");
            assertTrue(
                market.authorizedLiquidationPeriphery(address(periphery)), "liquidation authorization is missing"
            );
        }
    }

    function _assertRecoveryRoutesRemoved(uint256 marketIndex, address expectedOracle) internal view {
        address marketAddress = mintMarkets[marketIndex];
        IMarket market = IMarket(marketAddress);
        AltoLeverage leverage = AltoLeverage(manifest.markets[marketIndex].leverage);
        ILiquidationPeripheryBase periphery = ILiquidationPeripheryBase(input.contracts.liquidationPeriphery);

        assertFalse(marketRegistry.isMintMarket(marketAddress), "Mint Market remains registered");
        assertFalse(leverage.supportedMarkets(marketAddress), "leverage support remains");
        assertFalse(market.authorizedCallbacks(address(leverage)), "leverage callback remains");
        assertFalse(leverage.swapper().isWhitelisted(address(leverage)), "swapper permission remains");
        assertFalse(periphery.supportedMarkets(marketAddress), "liquidation support remains");
        assertFalse(market.authorizedLiquidationPeriphery(address(periphery)), "liquidation authorization remains");
        assertTrue(
            AltoAdapter(payable(input.contracts.altoAdapter)).isApprovedContract(marketAddress),
            "AltoAdapter approval was removed"
        );
        assertEq(market.oracle(), expectedOracle, "market oracle changed");
        _assertFrozenAndUnpaused(market);
    }

    function _assertRecoveryRerunContainsOnlyShutdownCalls() internal view {
        TimelockArtifactBatch memory batch;
        (batch,) = _loadAndAssertTimelockPair(
            MintMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE, bytes32(0)
        );
        _assertTimelockCallCount(batch, 4 * mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            address market = mintMarkets[i];
            uint256 callIndex = 4 * i;
            _assertTimelockCall(
                batch,
                callIndex,
                market,
                abi.encodeCall(AltoMintMarket.setDebtCeiling, (AltoMintMarket(market).badDebtAssets()))
            );
            _assertTimelockCall(
                batch, callIndex + 1, address(dusd), abi.encodeCall(IDUSD.setMinterCeiling, (market, 0))
            );
            _assertTimelockCall(
                batch, callIndex + 2, address(dusd), abi.encodeCall(IDUSD.setMinterStatus, (market, false))
            );
            _assertTimelockCall(
                batch, callIndex + 3, address(dusd), abi.encodeCall(IDUSD.setBurnerStatus, (market, false))
            );
        }
    }

    function _assertFrozenRevert(address target, address caller, bytes memory data, string memory message) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        assertFalse(success, message);
        assertEq(returnData, abi.encodeWithSelector(IPausable.IsPaused.selector, FROZEN_TYPE), "wrong freeze revert");
    }

    // Artifact loading and assertions.

    function _loadAndAssertTimelockPair(
        MintMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile,
        bytes32 expectedPredecessor
    ) internal view returns (TimelockArtifactBatch memory scheduled, bytes32 operationId) {
        string memory scheduleJson = vm.readFile(_artifactPath(phase, scheduleFile));
        string memory executeJson = vm.readFile(_artifactPath(phase, executeFile));
        assertEq(
            vm.parseJsonAddress(scheduleJson, ".meta.createdFromSafeAddress"),
            manifest.timelockSafe,
            "wrong schedule Safe"
        );
        assertEq(
            vm.parseJsonAddress(executeJson, ".meta.createdFromSafeAddress"),
            manifest.timelockSafe,
            "wrong execute Safe"
        );
        assertFalse(_jsonTransactionExists(scheduleJson, 1), "multiple schedule transactions");
        assertFalse(_jsonTransactionExists(executeJson, 1), "multiple execute transactions");

        (address scheduleTarget, bytes memory scheduleData) = _jsonTransaction(scheduleJson, 0);
        (address executeTarget, bytes memory executeData) = _jsonTransaction(executeJson, 0);
        assertEq(scheduleTarget, address(timelock), "wrong schedule target");
        assertEq(executeTarget, address(timelock), "wrong execute target");

        scheduled = _decodeSchedule(scheduleData);
        TimelockArtifactBatch memory executed = _decodeExecute(executeData);
        assertEq(scheduled.targets.length, scheduled.values.length, "schedule values length mismatch");
        assertEq(scheduled.targets.length, scheduled.payloads.length, "schedule payloads length mismatch");
        assertEq(executed.targets.length, executed.values.length, "execute values length mismatch");
        assertEq(executed.targets.length, executed.payloads.length, "execute payloads length mismatch");
        assertEq(scheduled.delay, timelock.getMinDelay(), "wrong Timelock delay");
        assertEq(scheduled.predecessor, expectedPredecessor, "wrong schedule predecessor");
        assertEq(executed.predecessor, expectedPredecessor, "wrong execute predecessor");
        assertEq(scheduled.salt, bytes32(0), "non-zero schedule salt");
        assertEq(executed.salt, bytes32(0), "non-zero execute salt");
        assertEq(
            keccak256(abi.encode(scheduled.targets, scheduled.values, scheduled.payloads)),
            keccak256(abi.encode(executed.targets, executed.values, executed.payloads)),
            "schedule and execute calls differ"
        );

        operationId = timelock.hashOperationBatch(
            scheduled.targets, scheduled.values, scheduled.payloads, scheduled.predecessor, scheduled.salt
        );
    }

    function _assertTimelockCallCount(TimelockArtifactBatch memory batch, uint256 expectedCount) internal pure {
        assertEq(batch.targets.length, expectedCount, "wrong Timelock call count");
        assertEq(batch.values.length, expectedCount, "wrong Timelock values length");
        assertEq(batch.payloads.length, expectedCount, "wrong Timelock payloads length");
    }

    function _assertTimelockCall(
        TimelockArtifactBatch memory batch,
        uint256 index,
        address expectedTarget,
        bytes memory expectedPayload
    ) internal pure {
        assertEq(batch.values[index], 0, "Timelock call sends ETH");
        assertEq(batch.targets[index], expectedTarget, "wrong Timelock call target");
        assertEq(batch.payloads[index], expectedPayload, "wrong Timelock call payload");
    }

    function _decodeSchedule(bytes memory data) internal pure returns (TimelockArtifactBatch memory batch) {
        require(_selector(data) == TimelockController.scheduleBatch.selector, "wrong Timelock schedule selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt, batch.delay) =
            abi.decode(_arguments(data), (address[], uint256[], bytes[], bytes32, bytes32, uint256));
    }

    function _decodeExecute(bytes memory data) internal pure returns (TimelockArtifactBatch memory batch) {
        require(_selector(data) == TimelockController.executeBatch.selector, "wrong Timelock execute selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt) =
            abi.decode(_arguments(data), (address[], uint256[], bytes[], bytes32, bytes32));
    }

    function _artifactPath(string memory fileName) internal view returns (string memory) {
        return _artifactPath(MintMarketOffboardingPhase.BATCH_A_CONTAIN, fileName);
    }

    function _artifactPath(MintMarketOffboardingPhase phase, string memory fileName)
        internal
        view
        returns (string memory)
    {
        return string.concat(MintMarketOffboarding.artifactDirectory(phase, manifest), "/", fileName);
    }

    function _advanceSourceBlock() internal {
        vm.roll(block.number + 1);
        manifest.sourceBlock = block.number;
    }

    function _jsonTransaction(string memory json, uint256 index)
        internal
        pure
        returns (address target, bytes memory data)
    {
        string memory prefix = string.concat(".transactions[", vm.toString(index), "]");
        target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
        data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
        assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "non-zero Safe value");
    }

    function _jsonTransactionExists(string memory json, uint256 index) internal view returns (bool) {
        return vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(index), "]"));
    }

    function _callFrom(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        assertTrue(success, string(returnData));
    }

    function _operationIdFromExecuteData(bytes memory data) private pure returns (bytes32 operationId) {
        TimelockArtifactBatch memory batch = _decodeExecute(data);
        operationId = keccak256(abi.encode(batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt));
    }

    function _arguments(bytes memory data) internal pure returns (bytes memory arguments) {
        require(data.length >= 4, "calldata too short");
        arguments = new bytes(data.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = data[i + 4];
        }
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(data, 0x20))
        }
    }

    function _isManifestMarket(address market) private view returns (bool) {
        for (uint256 i; i < mintMarkets.length; ++i) {
            if (mintMarkets[i] == market) return true;
        }
        return false;
    }
}
