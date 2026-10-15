// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MintMarketOffboardingTestBase} from "./MintMarketOffboardingTestBase.sol";
import {MintMarketOffboarding} from "../MintMarketOffboarding.sol";
import {
    MintMarketOffboardingPhase,
    MintMarketOffboardingSchedulePhase,
    MintMarketOffboardingSeverity
} from "../IMintMarketOffboarding.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {Balance, IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {FROZEN_TYPE} from "@alto/utils/Constants.sol";

/// @notice ERP-OFFBOARD-01 development pre-simulation. Executes the complete Medium-severity response against the live
/// refreshed WETH Mint Market at block 26,225,900 using the checked-in manifest and borrower fixtures.
contract RefreshWethMintMarketEndToEndTest is MintMarketOffboardingTestBase {
    address internal constant REFRESH_WETH_MINT_MARKET = 0x81b2CcE73052f67312eD9994385f62D413eE566e;
    uint256 internal constant REFRESH_WETH_FORK_BLOCK = 26_225_900;

    uint256 internal correctionCount;
    uint256 internal liquidationCount;

    function _forkBlock() internal pure override returns (uint256) {
        return REFRESH_WETH_FORK_BLOCK;
    }

    function _manifestFile() internal pure override returns (string memory) {
        return "ERP/ERP-OFFBOARD-01/tests/fixtures/manifest-refresh-weth-26225900.json";
    }

    function _borrowerFixture() internal pure override returns (string memory) {
        return "ERP/ERP-OFFBOARD-01/tests/fixtures/borrowers-refresh-weth-26225900.json";
    }

    function _validateRegistryCoverage() internal view override {
        assertGt(REFRESH_WETH_MINT_MARKET.code.length, 0, "refreshed WETH market is not deployed");
        assertTrue(marketRegistry.isMintMarket(REFRESH_WETH_MINT_MARKET), "refreshed WETH market is not registered");
    }

    function setUp() public {
        _setUpLiveManifest();
    }

    /// @dev Runs containment, fixed-rate attachment, every gated Medium correction, ordinary debt clearance, and
    /// ordinary recovery through the production entrypoints.
    function testMediumSeverityRefreshWethMintMarketOffboarding() public {
        assertEq(mintMarkets.length, 1, "pre-simulation targets one market");
        assertEq(mintMarkets[0], REFRESH_WETH_MINT_MARKET, "unexpected target market");
        IMarket target = IMarket(REFRESH_WETH_MINT_MARKET);
        _assertBorrowerListComplete(0);

        Balance memory debtBefore = target.totalBorrowed();
        address originalIrm = target.irm();
        address originalOracle = target.oracle();
        uint256 maxLtvBefore = target.maxLtv();
        assertGt(debtBefore.assets, 0, "live refreshed WETH market has no debt");
        assertFalse(target.paused(FROZEN_TYPE), "live refreshed WETH market is already frozen");
        emit log_named_decimal_uint("live market debt (DUSD)", debtBefore.assets, 18);
        emit log_named_uint("live borrowers", _forkBorrowers(0).length);

        // Batch A: freeze the market, claim fees, and install the approved debt and DUSD ceilings.
        _executeConfiguredBatchA();
        _assertAllFrozenAndUnpaused();
        _assertAllRequiredExitIntegrationsActive();
        assertEq(target.totalSupply().assets, manifest.markets[0].debtCeiling, "wrong Batch A debt ceiling");
        (, uint256 minterCeiling) = dusd.minterConfig(REFRESH_WETH_MINT_MARKET);
        assertEq(minterCeiling, manifest.markets[0].dusdMinterCeiling, "wrong Batch A DUSD ceiling");
        _assertEntrancesBlocked(0);

        // Batch B: attach the dedicated fixed-rate IRM and execute every simulation-gated correction.
        _advanceTo(manifest.t0);
        _executeFixedRatePhase();
        assertNotEq(target.irm(), originalIrm, "fixed-rate IRM not attached");
        _executeGatedMediumCorrectionsToZero();
        assertTrue(_allDebtCleared(), "ordinary liquidations did not clear WETH debt");
        assertLt(target.maxLtv(), maxLtvBefore, "WETH max LTV was not reduced");
        assertEq(AltoMintMarket(REFRESH_WETH_MINT_MARKET).claimableFeesAssets(), 0, "final claimable fees remain");
        assertEq(AltoMintMarket(REFRESH_WETH_MINT_MARKET).badDebtAssets(), 0, "ordinary liquidation created bad debt");
        (uint256 finalMinted,) = dusd.minterConfig(REFRESH_WETH_MINT_MARKET);
        assertEq(finalMinted, 0, "market-attributed DUSD remains");

        // Batch C: remove Mint authority and integrations while retaining the oracle and collateral-withdrawal route.
        _executeTimelockPhase(MintMarketOffboardingPhase.BATCH_C_RECOVER, RECOVER_SCHEDULE_FILE, RECOVER_EXECUTE_FILE);
        _assertRecoveryRoutesRemoved(0, originalOracle);
        Balance memory debtAfter = target.totalBorrowed();
        assertEq(debtAfter.assets, 0, "recovery debt assets remain");
        assertEq(debtAfter.shares, 0, "recovery debt shares remain");
        assertEq(target.totalSupply().assets, 0, "final debt ceiling is not zero");
        (uint256 recoveredMinted, uint256 recoveredCeiling) = dusd.minterConfig(REFRESH_WETH_MINT_MARKET);
        assertEq(recoveredMinted, 0, "recovery DUSD remains");
        assertEq(recoveredCeiling, 0, "final DUSD ceiling is not zero");
        assertFalse(dusd.allowedMinter(REFRESH_WETH_MINT_MARKET), "WETH market remains a DUSD minter");
        assertFalse(dusd.allowedBurner(REFRESH_WETH_MINT_MARKET), "WETH market remains a DUSD burner");
        _assertEntrancesBlocked(0);

        // Completed Mint recovery reruns retain only the four unconditional shutdown calls.
        input = scriptHarness.runPhase(MintMarketOffboardingPhase.BATCH_C_RECOVER, manifest, input);
        _assertRecoveryRerunContainsOnlyShutdownCalls();

        assertEq(correctionCount, 17, "unexpected correction count");
        assertEq(liquidationCount, 26, "unexpected liquidation count");
        emit log_named_uint("gated corrections executed", correctionCount);
        emit log_named_uint("ordinary liquidations executed", liquidationCount);
        emit log_named_uint("debt cleared (days after t0)", (manifest.lastStepExecutedAt - manifest.t0) / 1 days);
    }

    /// @dev Mirrors the Medium schedule while running each correction through the production simulation gate.
    function _executeGatedMediumCorrectionsToZero() private {
        manifest.severity = MintMarketOffboardingSeverity.MEDIUM;
        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.SCHEDULED;
        manifest.lastExecutedStep = 0;
        manifest.lastStepExecutedAt = 0;
        manifest.lastOperationId = bytes32(0);
        vm.mockCall(
            IMarket(REFRESH_WETH_MINT_MARKET).oracle(),
            abi.encodeCall(IOracle.getPrice, ()),
            abi.encode(initialOraclePrices[0])
        );

        address liquidator = makeAddr("weth-mint-terminal-liquidator");
        uint256[4] memory offsets = [uint256(1 days), 7 days, 14 days, 21 days];
        uint256[4] memory aprs = [uint256(0.1 ether), 0.2 ether, 0.4 ether, 0.8 ether];
        for (uint256 i; i < offsets.length && !_allDebtCleared(); ++i) {
            _advanceTo(manifest.t0 + offsets[i]);
            manifest.step = i + 1;
            _setCorrectionInputs(aprs[i] / uint256(365 days), 0.05 ether);
            _executeGatedCorrection();
            liquidationCount += _liquidateManifestBorrowers(liquidator);
        }
        if (_allDebtCleared()) return;

        manifest.schedulePhase = MintMarketOffboardingSchedulePhase.TERMINAL;
        _advanceTo(manifest.t0 + 28 days);
        liquidationCount += _liquidateManifestBorrowers(liquidator);

        uint256 terminalSteps;
        while (!_allDebtCleared()) {
            require(terminalSteps++ < 24, "terminal step bound exceeded");
            _advanceTo(manifest.lastStepExecutedAt + 1 hours);
            manifest.step = manifest.lastExecutedStep + 1;
            _setCorrectionInputs(0.8 ether / uint256(365 days), 0.05 ether);
            _executeGatedCorrection();
            liquidationCount += _liquidateManifestBorrowers(liquidator);
        }
    }

    function _executeGatedCorrection() private {
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_REDUCE_LTV;
        bytes32 operationId = _correctionOperationId();
        string memory manifestPath = _writeCurrentSimulationInputs();

        scriptHarness.run(uint256(phase), manifestPath);

        string memory outputDirectory = MintMarketOffboarding.artifactDirectory(phase, manifest);
        string memory report = vm.readFile(string.concat(outputDirectory, "/simulation-report.json"));
        assertTrue(vm.parseJsonBool(report, ".passed"), "phase-2 simulation did not pass");
        assertEq(
            vm.parseJsonString(report, ".operationId"), vm.toString(operationId), "simulation covered another operation"
        );
        uint256 funding = vm.parseJsonUint(report, ".markets[0].totals.liquidationFundingAssets");
        uint256 burned = vm.parseJsonUint(report, ".markets[0].totals.dusdBurnedAssets");
        assertEq(burned, funding, "reported DUSD burn differs from liquidation funding");

        assertEq(
            _executeTimelockArtifacts(phase, REDUCE_LTV_SCHEDULE_FILE, REDUCE_LTV_EXECUTE_FILE),
            operationId,
            "executed another correction operation"
        );
        manifest.lastExecutedStep = manifest.step;
        manifest.lastStepExecutedAt = block.timestamp;
        manifest.lastOperationId = operationId;
        ++correctionCount;
    }
}
