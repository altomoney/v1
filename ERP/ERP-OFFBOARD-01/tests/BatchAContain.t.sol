// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MintMarketOffboardingTestBase} from "./MintMarketOffboardingTestBase.sol";
import {MintMarketOffboardingPhase} from "../IMintMarketOffboarding.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract MintBatchAContainTest is MintMarketOffboardingTestBase {
    function setUp() public {
        _setUpManifest();
        for (uint256 i; i < mintMarkets.length; ++i) {
            assertFalse(IMarketBase(mintMarkets[i]).paused(FROZEN_TYPE), "fixture market initially frozen");
            assertFalse(IMarketBase(mintMarkets[i]).paused(PAUSE_TYPE), "fixture market initially paused");
        }
    }

    /// @dev Executes Batch A for all seven ordinary Mint Markets and verifies the generated freeze blocks entry, while
    /// the interest accrual, fee claim, market debt-ceiling, and DUSD minter-ceiling calls have their direct effects.
    function testBatchAContainsAllMintMarkets() public {
        manifest.activationId = "mint-batch-a-complete-containment";
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[mintMarkets.length - 1]).pause(FROZEN_TYPE, true);

        uint256[] memory mintedBefore = new uint256[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            (mintedBefore[i],) = dusd.minterConfig(mintMarkets[i]);
        }

        bytes32 operationId = _executeGeneratedBatchA();
        _assertGeneratedArtifacts(operationId, mintMarkets.length - 1);
        assertTrue(timelock.isOperationDone(operationId), "containment operation was not executed");

        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertContainmentState(i, mintedBefore[i]);
            _assertEntrancesBlocked(i);
        }

        // Every market is now frozen, so a rerun must remove the optional stale freezer artifact.
        input = scriptHarness.runPhase(MintMarketOffboardingPhase.BATCH_A_CONTAIN, manifest, input);
        assertFalse(vm.exists(_artifactPath(FREEZE_FILE)), "stale Batch A freezer artifact remains");
    }

    /// @dev Manifest: seven valid Mint Markets, with the full pause additionally enabled on one market. Verifies
    /// generation rejects a market that cannot receive the intended frozen-but-unpaused Batch A state.
    function testBatchARejectsPausedMarket() public {
        manifest.activationId = "mint-batch-a-paused-market";
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(PAUSE_TYPE, true);

        _expectBatchARevert("Batch A: market paused");
    }

    /// @dev Manifest: seven valid Mint Markets, but one approved debt ceiling exceeds its live ceiling. Verifies
    /// containment cannot create new principal borrowing capacity while attempting to off-board the market.
    function testBatchARejectsDebtCeilingIncrease() public {
        manifest.activationId = "mint-batch-a-debt-ceiling-increase";
        manifest.markets[0].debtCeiling = IMarket(mintMarkets[0]).totalSupply().assets + 1;

        _expectBatchARevert("Batch A: debt ceiling increase");
    }

    /// @dev Manifest: seven debt-bearing Mint Markets, but one approved debt ceiling is one unit below accrued debt plus
    /// bad debt. Verifies Batch A rejects a target that the market cannot apply safely.
    function testBatchARejectsDebtCeilingBelowCurrentExposure() public {
        manifest.activationId = "mint-batch-a-debt-ceiling-below-exposure";
        AltoMintMarket market = AltoMintMarket(mintMarkets[0]);
        manifest.markets[0].debtCeiling = IMarket(address(market)).totalBorrowed().assets + market.badDebtAssets() - 1;

        _expectBatchARevert("Batch A: debt ceiling below current exposure");
    }

    /// @dev Manifest: seven valid Mint Markets, but one approved DUSD minter ceiling exceeds its live ceiling. Verifies
    /// containment cannot add DUSD minting capacity.
    function testBatchARejectsDusdMinterCeilingIncrease() public {
        manifest.activationId = "mint-batch-a-dusd-ceiling-increase";
        (, uint256 currentCeiling) = dusd.minterConfig(mintMarkets[0]);
        manifest.markets[0].dusdMinterCeiling = currentCeiling + 1;

        _expectBatchARevert("Batch A: DUSD minter ceiling increase");
    }

    /// @dev Manifest: seven debt-bearing Mint Markets, but one approved DUSD ceiling is below current minted DUSD plus
    /// claimable fees. Verifies containment preserves the capacity required to reconcile existing debt and fees.
    function testBatchARejectsDusdCeilingBelowCurrentFees() public {
        manifest.activationId = "mint-batch-a-dusd-ceiling-below-fees";
        AltoMintMarket market = AltoMintMarket(mintMarkets[0]);
        (uint256 minted,) = dusd.minterConfig(address(market));
        manifest.markets[0].dusdMinterCeiling = minted + market.claimableFeesAssets() - 1;

        _expectBatchARevert("Batch A: DUSD ceiling below current fees");
    }

    function _assertGeneratedArtifacts(bytes32 expectedOperationId, uint256 expectedFreezeCalls) private view {
        _assertFreezeArtifact(expectedFreezeCalls);
        (TimelockArtifactBatch memory scheduled, bytes32 operationId) = _loadAndAssertTimelockPair(
            MintMarketOffboardingPhase.BATCH_A_CONTAIN, CONTAIN_SCHEDULE_FILE, CONTAIN_EXECUTE_FILE, bytes32(0)
        );
        assertEq(operationId, expectedOperationId, "wrong containment operation ID");
        _assertContainmentCalls(scheduled);
    }

    function _assertFreezeArtifact(uint256 expectedCallCount) private view {
        string memory json = vm.readFile(_artifactPath(FREEZE_FILE));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), manifest.freezerSafe, "wrong Freezer Safe");
        for (uint256 i; i < expectedCallCount; ++i) {
            (address target, bytes memory data) = _jsonTransaction(json, i);
            assertEq(target, mintMarkets[i], "freeze market order mismatch");
            assertEq(data, abi.encodeCall(IPausable.pause, (FROZEN_TYPE, true)), "wrong freeze calldata");
        }
        assertFalse(_jsonTransactionExists(json, expectedCallCount), "unexpected freezer transaction");
    }

    function _assertContainmentCalls(TimelockArtifactBatch memory batch) private view {
        uint256 expectedCallCount = mintMarkets.length * 4;
        _assertTimelockCallCount(batch, expectedCallCount);

        for (uint256 i; i < mintMarkets.length; ++i) {
            uint256 offset = i * 4;
            address market = mintMarkets[i];
            _assertTimelockCall(batch, offset, market, abi.encodeCall(IMarketBase.accrueInterest, ()));
            _assertTimelockCall(batch, offset + 1, market, abi.encodeCall(AltoMintMarket.claimInterest, (0)));
            _assertTimelockCall(
                batch,
                offset + 2,
                market,
                abi.encodeCall(AltoMintMarket.setDebtCeiling, (manifest.markets[i].debtCeiling))
            );
            _assertTimelockCall(
                batch,
                offset + 3,
                address(dusd),
                abi.encodeCall(IDUSD.setMinterCeiling, (market, manifest.markets[i].dusdMinterCeiling))
            );
        }
    }
}
