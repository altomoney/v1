// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {ERPOutputWriter} from "../../libraries/ERPOutputWriter.sol";
import {BorrowerList, BorrowMarketOffboardingIO} from "../libraries/BorrowMarketOffboardingIO.sol";
import {
    BorrowMarketOffboardingBorrowerMarket,
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingManifest,
    BorrowMarketOffboardingMarket,
    BorrowMarketOffboardingPhase,
    BorrowMarketOffboardingReport,
    BorrowMarketOffboardingSchedulePhase,
    BorrowMarketOffboardingSeverity,
    BorrowMarketOffboardingVault
} from "../IBorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingScript} from "../scripts/BorrowMarketOffboarding.s.sol";

import {BorrowMarketBatch, BorrowMarketBatchParams} from "@alto/deployments/ethereum-mainnet/BorrowMarketBatch.sol";
import {
    ALTO_BORROW_MARKET_IMPL,
    KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET,
    NORDSTERN_ROUTER_MAINNET,
    ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET,
    VELORA_AUGUSTUS_MAINNET,
    WETH_MAINNET,
    ZEROX_SWAP_TARGET_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {MarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {EthereumMainnetLendingOracleAsset} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {IAltoVault, IAltoVaultBase, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {ILiquidationPeripheryBase} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BorrowMarketOffboardingTestHarness is BorrowMarketOffboardingScript {
    function runPhase(
        BorrowMarketOffboardingPhase phase,
        BorrowMarketOffboardingManifest memory manifest,
        BorrowMarketOffboardingInput memory input
    ) external returns (BorrowMarketOffboardingInput memory) {
        return _runPhase(phase, manifest, input);
    }

    function _writeBorrowerList(string memory, BorrowMarketOffboardingManifest memory manifest)
        internal
        view
        override
        returns (BorrowerList memory)
    {
        return BorrowMarketOffboardingIO.parseBorrowerList(
            vm.readFile(BorrowMarketOffboardingIO.borrowerListPath(manifest))
        );
    }
}

abstract contract BorrowMarketOffboardingTestBase is Test {
    using AltoBalancesLib for address;

    uint256 internal constant FORK_BLOCK = 25_833_639;
    string internal constant MANIFEST_FILE = "ERP/ERP-OFFBOARD-02/config/borrow-market-offboarding.json";
    string internal constant BORROWER_FIXTURE = "ERP/ERP-OFFBOARD-02/tests/fixtures/borrowers-25833639.json";
    string internal constant FREEZE_FILE = "batch-a-freeze-safe.json";
    string internal constant FIXED_IRM_SCHEDULE_FILE = "batch-b-fixed-rate-irm-schedule.json";
    string internal constant FIXED_IRM_EXECUTE_FILE = "batch-b-fixed-rate-irm-execute.json";
    string internal constant REDUCE_LTV_SCHEDULE_FILE = "batch-b-irm-and-ltv-update-schedule.json";
    string internal constant REDUCE_LTV_EXECUTE_FILE = "batch-b-irm-and-ltv-update-execute.json";
    string internal constant RECOVER_SCHEDULE_FILE = "batch-c-final-removal-schedule.json";
    string internal constant RECOVER_EXECUTE_FILE = "batch-c-final-removal-execute.json";

    address internal constant VAULT_ALLOCATOR = 0x7db7C14533a4186EcC07950F78835859320835Be;

    struct MarketFixture {
        address supplier;
        address exitBorrower;
        address liquidationBorrower;
        address liquidator;
        uint256 livePrice;
    }

    BorrowMarketOffboardingTestHarness internal scriptHarness;
    BorrowMarketOffboardingManifest internal manifest;
    BorrowMarketOffboardingInput internal input;
    TimelockController internal timelock;
    IAltoVault internal vault;
    IERC4626 internal vaultToken;
    IMarketRegistry internal marketRegistry;
    AdapterContractApproval internal altoAdapter;
    address internal liquidationPeriphery;
    address[] internal borrowMarkets;
    address[] internal leverages;
    address[] internal leverageSwappers;
    MarketFixture[] internal fixtures;
    uint256[] internal initialOraclePrices;
    BorrowMarketOffboardingBorrowerMarket[] internal borrowerFixtureMarkets;

    /// @dev Pinned fork block. Override together with `_manifestFile` and `_borrowerFixture` to run the suite's
    /// helpers against another activation manifest.
    function _forkBlock() internal pure virtual returns (uint256) {
        return FORK_BLOCK;
    }

    function _manifestFile() internal pure virtual returns (string memory) {
        return MANIFEST_FILE;
    }

    function _borrowerFixture() internal pure virtual returns (string memory) {
        return BORROWER_FIXTURE;
    }

    function _setUpManifest() internal {
        scriptHarness = new BorrowMarketOffboardingTestHarness();
        BorrowMarketOffboardingManifest memory loadedManifest =
            BorrowMarketOffboardingIO.loadActivationManifest(_manifestFile());
        _storeManifest(loadedManifest);
        assertEq(manifest.sourceBlock, _forkBlock(), "manifest fork block changed");
        vm.createSelectFork(vm.rpcUrl("ethereum"), _forkBlock());
        input = BorrowMarketOffboardingIO.loadCurrentChainInput(manifest.deploymentId);
        if (input.contracts.ownerFixedRateIrmFactory.code.length == 0) {
            input.contracts.ownerFixedRateIrmFactory = address(0);
        }
        _bindManifestState();
        _loadBorrowerFixture();
    }

    function _loadBorrowerFixture() private {
        string memory json = vm.readFile(_borrowerFixture());
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "borrower fixture chain mismatch");
        assertEq(vm.parseJsonUint(json, ".sourceBlock"), _forkBlock(), "borrower fixture block mismatch");

        BorrowerList memory borrowerList = BorrowMarketOffboardingIO.parseBorrowerList(json);
        delete borrowerFixtureMarkets;
        for (uint256 i; i < borrowerList.markets.length; ++i) {
            borrowerFixtureMarkets.push();
            BorrowMarketOffboardingBorrowerMarket storage stored = borrowerFixtureMarkets[i];
            stored.market = borrowerList.markets[i].market;
            for (uint256 j; j < borrowerList.markets[i].borrowers.length; ++j) {
                stored.borrowers.push(borrowerList.markets[i].borrowers[j]);
            }
        }
    }

    function _bindManifestState() internal {
        timelock = TimelockController(payable(input.contracts.timelock));
        vault = IAltoVault(manifest.vaults[0].vault);
        vaultToken = IERC4626(manifest.vaults[0].vault);
        marketRegistry = IMarketRegistry(input.contracts.marketRegistry);
        altoAdapter = AdapterContractApproval(input.contracts.altoAdapter);
        liquidationPeriphery = input.contracts.liquidationPeriphery;

        delete borrowMarkets;
        delete leverages;
        delete leverageSwappers;
        delete initialOraclePrices;
        for (uint256 i; i < manifest.markets.length; ++i) {
            address leverage = manifest.markets[i].leverage;
            borrowMarkets.push(manifest.markets[i].market);
            leverages.push(leverage);
            leverageSwappers.push(address(AltoLeverage(leverage).swapper()));
            initialOraclePrices.push(IOracle(IMarket(manifest.markets[i].market).oracle()).getPrice());
        }
    }

    function _storeManifest(BorrowMarketOffboardingManifest memory source) private {
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

        delete manifest.vaults;
        for (uint256 i; i < source.vaults.length; ++i) {
            _pushManifestVault(source.vaults[i]);
        }

        delete manifest.markets;
        for (uint256 i; i < source.markets.length; ++i) {
            _pushManifestMarket(source.markets[i]);
        }
    }

    function _pushManifestVault(BorrowMarketOffboardingVault memory source) internal {
        manifest.vaults.push();
        BorrowMarketOffboardingVault storage stored = manifest.vaults[manifest.vaults.length - 1];
        stored.allocator = source.allocator;
        stored.maxVaultLossAssets = source.maxVaultLossAssets;
        stored.reallocationBufferAssets = source.reallocationBufferAssets;
        stored.vault = source.vault;
        for (uint256 i; i < source.replacementMarkets.length; ++i) {
            stored.replacementMarkets.push(source.replacementMarkets[i]);
        }
    }

    function _pushManifestMarket(BorrowMarketOffboardingMarket memory source) internal {
        manifest.markets.push();
        BorrowMarketOffboardingMarket storage stored = manifest.markets[manifest.markets.length - 1];
        stored.correctionRateSpy = source.correctionRateSpy;
        stored.fixedRateSpy = source.fixedRateSpy;
        stored.leverage = source.leverage;
        stored.ltvReduction = source.ltvReduction;
        stored.market = source.market;
        stored.maxBadDebtAssets = source.maxBadDebtAssets;
        stored.maxLiquidationFundingAssets = source.maxLiquidationFundingAssets;
        stored.maxProtocolLossAssets = source.maxProtocolLossAssets;
        stored.maxSupplierLossAssets = source.maxSupplierLossAssets;
    }

    function _selectManifestMarkets(uint256[] memory indexes) internal {
        BorrowMarketOffboardingMarket[] memory selected = new BorrowMarketOffboardingMarket[](indexes.length);
        for (uint256 i; i < indexes.length; ++i) {
            require(indexes[i] < manifest.markets.length, "invalid manifest market index");
            selected[i] = manifest.markets[indexes[i]];
        }
        delete manifest.markets;
        for (uint256 i; i < selected.length; ++i) {
            _pushManifestMarket(selected[i]);
        }
        _bindManifestState();
    }

    function _seedStandardPositions() internal {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _seedStandardPosition(i);
        }
    }

    function _seedStandardPosition(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        assertFalse(market.paused(PAUSE_TYPE), "market paused before Batch A");

        MarketFixture memory fixture = MarketFixture({
            supplier: makeAddr(string.concat("supplier-", vm.toString(marketIndex))),
            exitBorrower: makeAddr(string.concat("exit-borrower-", vm.toString(marketIndex))),
            liquidationBorrower: makeAddr(string.concat("liquidation-borrower-", vm.toString(marketIndex))),
            liquidator: makeAddr(string.concat("liquidator-", vm.toString(marketIndex))),
            livePrice: IOracle(market.oracle()).getPrice()
        });

        IERC20 borrowToken = IERC20(market.borrowToken());
        uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals()) / 100;
        uint256 collateralValue = Math.mulDiv(collateralAssets, fixture.livePrice, LENDING_ORACLE_PRICE_PRECISION);
        uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);

        uint256 directSupplyAssets = 1e12;
        deal(address(borrowToken), fixture.supplier, directSupplyAssets);
        vm.startPrank(fixture.supplier);
        borrowToken.approve(address(market), directSupplyAssets);
        market.addSupply(directSupplyAssets, 0, fixture.supplier);
        vm.stopPrank();

        _openBorrowPosition(market, fixture.exitBorrower, collateralAssets, maximumBorrow / 10);
        _openBorrowPosition(market, fixture.liquidationBorrower, collateralAssets, maximumBorrow / 2);
        fixtures.push(fixture);
    }

    function _openBorrowPosition(IMarket market, address borrower, uint256 collateralAssets, uint256 borrowAssets)
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

    function _exerciseExitAndLiquidationRoutes(IMarket market, MarketFixture memory fixture) internal {
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(fixture.livePrice));

        Position memory supplyPosition = market.position(fixture.supplier);
        Position memory exitPosition = market.position(fixture.exitBorrower);
        IERC20 borrowToken = IERC20(market.borrowToken());

        deal(address(borrowToken), fixture.exitBorrower, 1_000_000 ether);
        vm.startPrank(fixture.exitBorrower);
        borrowToken.approve(address(market), type(uint256).max);
        market.repay(0, exitPosition.borrowShares, fixture.exitBorrower);
        market.removeCollateral(exitPosition.collateralAssets, fixture.exitBorrower, fixture.exitBorrower, "");
        vm.stopPrank();

        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(fixture.livePrice / 4));
        Position memory liquidationPosition = market.position(fixture.liquidationBorrower);
        deal(address(borrowToken), fixture.liquidator, 1_000_000 ether);

        vm.startPrank(fixture.liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(fixture.liquidationBorrower, "", "");
        vm.stopPrank();

        Position memory positionAfter = market.position(fixture.liquidationBorrower);
        assertGt(seizedCollateral, 0, "liquidation seized no collateral");
        assertGt(repaidBorrow, 0, "liquidation repaid no debt");
        assertLt(positionAfter.borrowShares, liquidationPosition.borrowShares, "liquidation did not reduce debt");
        assertLt(positionAfter.collateralAssets, liquidationPosition.collateralAssets, "liquidation seized no position");

        vm.prank(fixture.supplier);
        (uint256 withdrawnAssets,) =
            market.removeSupply(0, supplyPosition.supplyShares, fixture.supplier, fixture.supplier);

        assertGt(withdrawnAssets, 0, "removeSupply returned no assets");
        assertEq(market.position(fixture.supplier).supplyShares, 0, "removeSupply failed");
        assertEq(market.position(fixture.exitBorrower).borrowShares, 0, "repay failed");
        assertEq(market.position(fixture.exitBorrower).collateralAssets, 0, "removeCollateral failed");
    }

    function _executeBatchBFixedRate() internal {
        _executeBatchA();
        _executeFixedRatePhase();
    }

    function _executeFixedRatePhase() internal {
        _assertAllFrozenAndUnpaused();
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );
    }

    function _expectPhaseRevert(BorrowMarketOffboardingPhase phase, string memory reason) internal {
        vm.expectRevert(bytes(reason));
        scriptHarness.runPhase(phase, manifest, input);
        vm.stopBroadcast();
    }

    function _executeBatchA() internal {
        _prepareBatchAReplacementMarkets();
        _executeConfiguredBatchA();
    }

    function _executeConfiguredBatchA() internal {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_A_CONTAIN;
        input = scriptHarness.runPhase(phase, manifest, input);
        if (vm.exists(_artifactPath(phase, FREEZE_FILE))) {
            _executeSafeBatch(phase, FREEZE_FILE, manifest.freezerSafe);
        }
        for (uint256 i; i < manifest.vaults.length; ++i) {
            address affectedVault = manifest.vaults[i].vault;
            string memory curatorFile = BorrowMarketOffboarding.vaultCuratorFileName(affectedVault);
            if (vm.exists(_artifactPath(phase, curatorFile))) {
                _executeSafeBatch(phase, curatorFile, IAltoVault(affectedVault).curator());
            }
            string memory allocatorFile = BorrowMarketOffboarding.vaultAllocatorFileName(phase, affectedVault);
            if (vm.exists(_artifactPath(phase, allocatorFile))) {
                _executeAllocatorPlan(phase, allocatorFile, manifest.vaults[i].allocator, affectedVault);
            }
        }
        _advanceSourceBlock();
    }

    function _executeTimelockPhase(
        BorrowMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile
    ) internal {
        input = scriptHarness.runPhase(phase, manifest, input);
        _executeTimelockArtifacts(phase, scheduleFile, executeFile);
    }

    function _executeTimelockArtifacts(
        BorrowMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile
    ) internal {
        _executeSafeBatch(phase, scheduleFile, manifest.timelockSafe);
        vm.warp(block.timestamp + timelock.getMinDelay());
        vm.roll(block.number + 1);
        _executeSafeBatch(phase, executeFile, manifest.timelockSafe);
        manifest.sourceBlock = block.number;
    }

    function _executeAndRecordCorrection() internal {
        bytes32 operationId = _correctionOperationId();
        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_REDUCE_LTV, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE
        );
        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
    }

    function _correctionOperationId() internal view returns (bytes32 operationId) {
        BorrowMarketOffboardingReport memory report =
            BorrowMarketOffboarding.prepareRateAndLtvReduction(manifest, input);
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

    function _advanceTo(uint256 timestamp) internal {
        if (block.timestamp < timestamp) vm.warp(timestamp);
        _advanceSourceBlock();
    }

    function _advanceSourceBlock() internal {
        vm.roll(block.number + 1);
        manifest.sourceBlock = block.number;
    }

    function _executeBatchBToZeroDebt() internal {
        _executeBatchBFixedRate();
        manifest.t0 = block.timestamp;
        _executeMediumCorrectionsToZero(manifest.t0, manifest.activationId);
    }

    function _executeMediumCorrectionsToZero(uint256 t0, string memory activationId) internal {
        manifest.activationId = activationId;
        manifest.severity = BorrowMarketOffboardingSeverity.MEDIUM;
        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.t0 = t0;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(initialOraclePrices[i]));
        }

        uint256[4] memory offsets = [uint256(1 days), 7 days, 14 days, 21 days];
        uint256[4] memory aprs = [uint256(0.1 ether), 0.2 ether, 0.4 ether, 0.8 ether];
        for (uint256 i; i < offsets.length && !_allDebtCleared(); ++i) {
            _advanceTo(manifest.t0 + offsets[i]);
            manifest.step = i + 1;
            _setCorrectionInputs(aprs[i] / uint256(365 days), 0.05 ether);
            _executeAndRecordCorrection();
            _liquidateManifestBorrowers(makeAddr("batch-c-terminal-liquidator"));
        }
        if (_allDebtCleared()) return;

        manifest.schedulePhase = BorrowMarketOffboardingSchedulePhase.TERMINAL;
        _advanceTo(manifest.t0 + 28 days);
        _liquidateManifestBorrowers(makeAddr("batch-c-terminal-liquidator"));

        uint256 terminalSteps;
        while (!_allDebtCleared()) {
            require(terminalSteps++ < 24, "Batch C prerequisite exceeded terminal step bound");
            _advanceTo(manifest.lastStepExecutedAt + 1 hours);
            manifest.step = manifest.lastExecutedStep + 1;
            _setCorrectionInputs(0.8 ether / uint256(365 days), 0.05 ether);
            _executeAndRecordCorrection();
            _liquidateManifestBorrowers(makeAddr("batch-c-terminal-liquidator"));
        }
    }

    function _executeSafeBatch(BorrowMarketOffboardingPhase phase, string memory fileName, address safe) internal {
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

    function _executeAllocatorPlan(
        BorrowMarketOffboardingPhase phase,
        string memory fileName,
        address allocator,
        address affectedVault
    ) internal {
        string memory json = vm.readFile(_artifactPath(phase, fileName));
        assertEq(vm.parseJsonAddress(json, ".caller"), allocator, "wrong allocator caller");
        assertEq(vm.parseJsonAddress(json, ".vault"), affectedVault, "wrong allocator Vault");

        if (phase == BorrowMarketOffboardingPhase.BATCH_A_CONTAIN) {
            uint256 transactionIndex;
            while (_jsonTransactionExists(json, transactionIndex)) {
                (address target, bytes memory callData) = _jsonTransaction(json, transactionIndex);
                assertEq(target, affectedVault, "wrong allocator target");
                _callFrom(allocator, target, callData);
                ++transactionIndex;
            }
            assertGt(transactionIndex, 0, "empty Batch A allocator plan");
            return;
        }

        assertEq(vm.parseJsonAddress(json, ".transaction.to"), affectedVault, "wrong allocator target");
        assertEq(vm.parseJsonString(json, ".transaction.value"), "0", "non-zero allocator value");
        bytes memory data = vm.parseJsonBytes(json, ".transaction.data");
        uint256[] memory indexes =
            abi.decode(vm.parseJson(json, ".transaction.arguments.remainingIndexes"), (uint256[]));
        assertEq(vm.parseJsonString(json, ".transaction.function"), "updateWithdrawQueue(uint256[])");
        assertEq(
            data, abi.encodeCall(IAltoVaultBase.updateWithdrawQueue, (indexes)), "wrong Batch C allocator calldata"
        );
        _callFrom(allocator, affectedVault, data);
    }

    function _executeRecoveryAllocatorPlans() internal {
        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_C_RECOVER;
        input = scriptHarness.runPhase(phase, manifest, input);
        assertFalse(vm.exists(_artifactPath(phase, RECOVER_SCHEDULE_FILE)), "unexpected recovery schedule");
        assertFalse(vm.exists(_artifactPath(phase, RECOVER_EXECUTE_FILE)), "unexpected recovery execution");

        bool executedPlan;
        for (uint256 i; i < manifest.vaults.length; ++i) {
            address affectedVault = manifest.vaults[i].vault;
            string memory fileName = BorrowMarketOffboarding.vaultAllocatorFileName(phase, affectedVault);
            if (!vm.exists(_artifactPath(phase, fileName))) continue;
            executedPlan = true;
            _executeAllocatorPlan(phase, fileName, manifest.vaults[i].allocator, affectedVault);
        }
        assertTrue(executedPlan, "missing Batch C allocator plan");
        _advanceSourceBlock();
    }

    function _artifactPath(BorrowMarketOffboardingPhase phase, string memory fileName)
        internal
        view
        returns (string memory)
    {
        return string.concat(BorrowMarketOffboarding.artifactDirectory(phase, manifest), "/", fileName);
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

    function _affectedVaultSupplyAssets() internal view returns (uint256 assets) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assets += borrowMarkets[i].expectedSupplyAssets(address(vault));
        }
    }

    function _targetExitAllocations(uint256 extraLength) internal view returns (MarketAllocation[] memory allocations) {
        allocations = new MarketAllocation[](borrowMarkets.length + extraLength);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            allocations[i] = MarketAllocation({market: borrowMarkets[i], assets: 0});
        }
    }

    function _prepareBatchAReplacementMarkets() internal {
        bool replacementRequired;
        for (uint256 i; i < manifest.vaults.length; ++i) {
            if (manifest.vaults[i].replacementMarkets.length == 0) replacementRequired = true;
        }
        if (!replacementRequired) return;

        uint256[] memory oraclePrices = new uint256[](borrowMarkets.length);
        for (uint256 i; i < borrowMarkets.length; ++i) {
            oraclePrices[i] = initialOraclePrices[i];
        }

        address replacement = _deployAndEnableReplacementBorrowMarket(type(uint128).max);
        for (uint256 i; i < manifest.vaults.length; ++i) {
            if (manifest.vaults[i].replacementMarkets.length != 0) continue;
            IAltoVault affectedVault = IAltoVault(manifest.vaults[i].vault);
            if (address(affectedVault) != address(vault)) {
                _enableReplacementForVault(affectedVault, replacement, type(uint128).max);
            }
            manifest.vaults[i].replacementMarkets.push(replacement);
        }

        // Cap acceptance advances historical forks beyond the oracle heartbeat. Preserve the source-block prices so
        // containment tests continue to exercise exits against the pinned fork state.
        for (uint256 i; i < borrowMarkets.length; ++i) {
            vm.mockCall(
                IMarket(borrowMarkets[i]).oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(oraclePrices[i])
            );
        }
    }

    function _deployAndApproveReplacementBorrowMarket(uint256 supplyCap) internal returns (address replacement) {
        replacement = _deployAndEnableReplacementBorrowMarket(supplyCap);
        address[] memory supplyQueue = new address[](1);
        supplyQueue[0] = replacement;
        vm.prank(manifest.vaults[0].allocator);
        vault.setSupplyQueue(supplyQueue);
    }

    function _deployAndEnableReplacementBorrowMarket(uint256 supplyCap) internal returns (address replacement) {
        replacement = _deployRegisteredReplacementBorrowMarket();
        _enableReplacementForVault(vault, replacement, supplyCap);
    }

    function _deployRegisteredReplacementBorrowMarket() internal returns (address replacement) {
        _ensureBorrowMarketImplementation();
        MarketContracts memory deployed = BorrowMarketBatch.deploy(_replacementMarketParams());
        replacement = deployed.market;

        assertEq(IMarket(replacement).borrowToken(), vaultToken.asset(), "replacement has wrong borrow token");
        assertEq(IMarket(replacement).collateralToken(), WETH_MAINNET, "replacement has wrong collateral token");

        vm.startPrank(address(timelock));
        marketRegistry.addBorrowMarket(replacement);
        altoAdapter.approveContract(replacement);
        ILiquidationPeripheryBase(liquidationPeriphery).setSupportedMarket(replacement, true);
        IMarket(replacement).setAuthorizedLiquidationPeriphery(liquidationPeriphery, true);
        vm.stopPrank();
    }

    function _enableReplacementForVault(IAltoVault affectedVault, address replacement, uint256 supplyCap) internal {
        vm.prank(affectedVault.curator());
        affectedVault.submitCap(replacement, supplyCap);
        uint256 validAt = affectedVault.pendingCap(replacement).validAt;
        if (block.timestamp < validAt) vm.warp(validAt);
        affectedVault.acceptCap(replacement);
    }

    function _reallocateVaultToReplacement(address replacement) internal {
        MarketAllocation[] memory allocations = _targetExitAllocations(1);
        allocations[borrowMarkets.length] = MarketAllocation({market: replacement, assets: type(uint256).max});

        vm.prank(manifest.vaults[0].allocator);
        vault.reallocate(allocations);
    }

    function _ensureBorrowMarketImplementation() private {
        if (ALTO_BORROW_MARKET_IMPL.code.length != 0) return;

        // The deployment helper's implementation address postdates some historical forks.
        AltoBorrowMarket implementation = new AltoBorrowMarket();
        vm.etch(ALTO_BORROW_MARKET_IMPL, address(implementation).code);
    }

    function _replacementMarketParams() private view returns (BorrowMarketBatchParams memory params) {
        params.owner = address(timelock);
        params.deployer = address(this);
        params.dusd = vaultToken.asset();
        params.altoAdapter = address(altoAdapter);
        params.feeRecipient = IMarket(borrowMarkets[0]).feeRecipient();
        params.collateralToken = WETH_MAINNET;
        params.oracleAsset = EthereumMainnetLendingOracleAsset.WETH;
        params.irmConfig = AdaptiveCurveIrm.AdaptiveCurveIrmConfig({
            curveSteepness: 4 ether,
            adjustmentSpeed: 50 ether / int256(365 days),
            targetUtilization: 0.9 ether,
            initialRateAtTarget: 0.1 ether / int256(365 days),
            minRateAtTarget: 0.001 ether / int256(365 days),
            maxRateAtTarget: 2 ether / int256(365 days)
        });
        params.maxLtv = 0.8 ether;
        params.initialBorrowOpeningFee = 0.0005 ether;
        params.supplyCapAssets = 0;
        params.liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: 0.85 ether,
            dynamicBonusFeeStart: 0.02 ether,
            ltvForCompleteLiquidation: 0.93 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.005 ether,
            protocolFeePercentage: 0.07 ether,
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: 0,
            priorityLiquidationGracePeriod: 0,
            taggerLiquidationGracePeriod: 0,
            liquidationWindowTag: 0
        });
        params.validSwapTargets = _validSwapTargets();
        params.freezer = manifest.freezerSafe;
    }

    function _validSwapTargets() private pure returns (address[] memory targets) {
        targets = new address[](5);
        targets[0] = ZEROX_SWAP_TARGET_MAINNET;
        targets[1] = ONE_INCH_AGGREGATION_ROUTER_V6_MAINNET;
        targets[2] = KYBERSWAP_META_AGGREGATION_ROUTER_V2_MAINNET;
        targets[3] = VELORA_AUGUSTUS_MAINNET;
        targets[4] = NORDSTERN_ROUTER_MAINNET;
    }

    function _assertFrozenAndUnpaused(IMarketBase market) internal view {
        assertTrue(market.paused(FROZEN_TYPE), "market not frozen");
        assertFalse(market.paused(PAUSE_TYPE), "market paused");
    }

    function _assertAllFrozenAndUnpaused() internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertFrozenAndUnpaused(IMarketBase(borrowMarkets[i]));
        }
    }

    function _assertRequiredExitIntegrationsActive(uint256 marketIndex) internal view {
        address market = borrowMarkets[marketIndex];
        address leverage = leverages[marketIndex];

        assertTrue(marketRegistry.isBorrowMarket(market), "market removed from MarketRegistry");
        assertTrue(altoAdapter.isApprovedContract(market), "market removed from AltoAdapter");
        assertTrue(AltoLeverage(leverage).supportedMarkets(market), "leverage market support removed");
        assertTrue(IMarket(market).authorizedCallbacks(leverage), "leverage callback removed");
        assertTrue(
            IAltoLeverageSwapper(leverageSwappers[marketIndex]).isWhitelisted(leverage),
            "leverage swapper permission removed"
        );
        assertTrue(
            ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(market),
            "liquidation periphery market support removed"
        );
        assertTrue(
            IMarket(market).authorizedLiquidationPeriphery(liquidationPeriphery),
            "liquidation periphery permission removed"
        );
    }

    function _assertRecoveryRoutesRemoved(uint256 marketIndex) internal view {
        address market = borrowMarkets[marketIndex];
        address leverage = leverages[marketIndex];

        assertFalse(marketRegistry.isBorrowMarket(market), "market remains registered");
        assertTrue(altoAdapter.isApprovedContract(market), "market removed from adapter withdrawal route");
        assertFalse(AltoLeverage(leverage).supportedMarkets(market), "leverage support remains");
        assertFalse(IMarket(market).authorizedCallbacks(leverage), "leverage callback remains");
        assertFalse(
            IAltoLeverageSwapper(leverageSwappers[marketIndex]).isWhitelisted(leverage),
            "leverage swapper permission remains"
        );
        assertFalse(
            ILiquidationPeripheryBase(liquidationPeriphery).supportedMarkets(market),
            "liquidation periphery support remains"
        );
        assertFalse(
            IMarket(market).authorizedLiquidationPeriphery(liquidationPeriphery),
            "liquidation periphery remains authorized"
        );
        _assertFrozenAndUnpaused(IMarketBase(market));
    }

    function _assertAllRequiredExitIntegrationsActive() internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertRequiredExitIntegrationsActive(i);
        }
    }

    function _isAffectedMarket(address market) internal view returns (bool) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (borrowMarkets[i] == market) return true;
        }
        return false;
    }

    function _isInSupplyQueue(address market) internal view returns (bool) {
        for (uint256 i; i < vault.supplyQueueLength(); ++i) {
            if (vault.supplyQueue(i) == market) return true;
        }
        return false;
    }

    function _isInWithdrawQueue(address market) internal view returns (bool) {
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            if (vault.withdrawQueue(i) == market) return true;
        }
        return false;
    }

    function _assertBorrowerListComplete(uint256 marketIndex) internal view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address[] memory borrowers = _forkBorrowers(marketIndex);
        uint256 listedBorrowShares;
        for (uint256 i; i < borrowers.length; ++i) {
            listedBorrowShares += market.position(borrowers[i]).borrowShares;
        }
        assertEq(
            listedBorrowShares,
            market.totalBorrowed().shares,
            string.concat("stale borrower list for market ", vm.toString(marketIndex))
        );
    }

    function _liquidateBorrowerList(IMarket market, address[] memory borrowers, address liquidator)
        internal
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
        for (uint256 i; i < borrowMarkets.length; ++i) {
            liquidationCount += _liquidateBorrowerList(IMarket(borrowMarkets[i]), _forkBorrowers(i), liquidator);
        }
    }

    function _attemptOrdinaryLiquidation(IMarket market, address borrower) internal returns (bool liquidated) {
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
        for (uint256 i; i < borrowMarkets.length; ++i) {
            Balance memory debt = IMarket(borrowMarkets[i]).totalBorrowed();
            if (debt.assets != 0 || debt.shares != 0) return false;
        }
        return true;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(data, 0x20))
        }
    }

    /// @dev Returns the cached deterministic borrower list captured at the initial fork block.
    function _forkBorrowers(uint256 marketIndex) internal view returns (address[] memory borrowers) {
        require(marketIndex < borrowMarkets.length, "invalid market index");
        address market = borrowMarkets[marketIndex];
        for (uint256 i; i < borrowerFixtureMarkets.length; ++i) {
            if (borrowerFixtureMarkets[i].market == market) return borrowerFixtureMarkets[i].borrowers;
        }
        revert("borrower fixture market mismatch");
    }
}
