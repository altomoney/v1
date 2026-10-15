// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MintMarketOffboardingTestBase} from "./MintMarketOffboardingTestBase.sol";
import {MintMarketOffboardingPhase} from "../IMintMarketOffboarding.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract MintBatchBSetFixedRateIrmTest is MintMarketOffboardingTestBase {
    function setUp() public {
        _setUpManifest();
    }

    /// @dev Runs Batch A at block 25,810,052, advances to the Batch B source block, deploys the missing factory, and
    /// verifies the exact ordered Timelock calls deploy and attach one dedicated fixed-rate IRM per Mint Market.
    function testBatchBDeploysAndAttachesDedicatedFixedRateIrms() public {
        _prepareContainedMarkets("mint-fixed-rate-deploy-and-attach");
        assertEq(input.contracts.ownerFixedRateIrmFactory, address(0), "test requires missing factory");

        address[] memory oldIrms = new address[](mintMarkets.length);
        Balance[] memory borrowedBefore = new Balance[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            IMarket market = IMarket(mintMarkets[i]);
            oldIrms[i] = market.irm();
            borrowedBefore[i] = market.totalBorrowed();
            assertGt(borrowedBefore[i].shares, 0, "test requires market debt");
        }

        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM;
        input = scriptHarness.runPhase(phase, manifest, input);
        OwnerFixedRateIrmFactory irmFactory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        assertGt(address(irmFactory).code.length, 0, "factory not deployed");
        assertEq(irmFactory.owner(), address(timelock), "Timelock does not own factory");
        address[] memory predictedIrms = _predictIrms(irmFactory);

        bytes32 operationId = _assertGeneratedArtifacts(irmFactory, predictedIrms);
        _executeTimelockArtifacts(phase, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE);

        assertEq(block.number, _forkBlock() + 2, "Batch B execution block mismatch");
        assertEq(manifest.sourceBlock, block.number, "post-execution source block not synchronized");
        assertTrue(timelock.isOperationDone(operationId), "fixed-rate operation was not executed");
        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertMarketIrm(irmFactory, i, oldIrms[i], predictedIrms[i], borrowedBefore[i]);
        }
    }

    /// @dev Supplies an existing Timelock-owned factory after containment. Verifies the factory is retained and its
    /// deterministic versioned IRMs are deployed and attached through the same generated calls.
    function testBatchBUsesExistingFactoryWithoutRedeploying() public {
        _prepareContainedMarkets("mint-fixed-rate-existing-factory");
        OwnerFixedRateIrmFactory existingFactory = new OwnerFixedRateIrmFactory(address(timelock));
        input.contracts.ownerFixedRateIrmFactory = address(existingFactory);

        address[] memory predictedIrms = _predictIrms(existingFactory);

        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM;
        input = scriptHarness.runPhase(phase, manifest, input);
        assertEq(input.contracts.ownerFixedRateIrmFactory, address(existingFactory), "existing factory was replaced");
        _assertGeneratedArtifacts(existingFactory, predictedIrms);
        _executeTimelockArtifacts(phase, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE);

        for (uint256 i; i < mintMarkets.length; ++i) {
            _assertIrmDeploymentAndAttachment(existingFactory, i, predictedIrms[i]);
        }
    }

    /// @dev Makes one contained market report zero borrowed assets and shares. Verifies generation stops because the
    /// market has already reached the Batch B debt target and does not require a fixed-rate IRM.
    function testBatchBRejectsMarketWithNoRemainingDebt() public {
        _prepareContainedMarkets("mint-fixed-rate-zero-debt");
        vm.mockCall(
            mintMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
        );

        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: debt targets reached");
    }

    /// @dev Removes the Batch A freeze from one market. Verifies fixed-rate generation rejects a market that can still
    /// accept new collateral and principal borrowing.
    function testBatchBRejectsUnfrozenMarket() public {
        _prepareContainedMarkets("mint-fixed-rate-unfrozen");
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(FROZEN_TYPE, false);

        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: market not frozen");
    }

    /// @dev Fully pauses one contained market. Verifies fixed-rate generation requires the Batch B target state to
    /// remain frozen but not fully paused.
    function testBatchBRejectsPausedMarket() public {
        _prepareContainedMarkets("mint-fixed-rate-paused");
        vm.prank(manifest.freezerSafe);
        IPausable(mintMarkets[0]).pause(PAUSE_TYPE, true);

        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: market paused");
    }

    /// @dev Sets one approved initial SPY rate one unit above the FixedRateIrm maximum. Verifies generation rejects the
    /// out-of-range rate before scheduling any deployment or attachment.
    function testBatchBRejectsRateAboveIrmMaximum() public {
        _prepareContainedMarkets("mint-fixed-rate-above-maximum");
        manifest.markets[0].fixedRateSpy = 8 ether / uint256(365 days) + 1;

        _expectPhaseRevert(MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: rate above IRM maximum");
    }

    function _assertGeneratedArtifacts(OwnerFixedRateIrmFactory irmFactory, address[] memory predictedIrms)
        private
        view
        returns (bytes32 operationId)
    {
        MintMarketOffboardingPhase phase = MintMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM;
        TimelockArtifactBatch memory scheduled;
        (scheduled, operationId) =
            _loadAndAssertTimelockPair(phase, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE, bytes32(0));
        _assertFixedRateCalls(scheduled, irmFactory, predictedIrms);
    }

    function _assertFixedRateCalls(
        TimelockArtifactBatch memory batch,
        OwnerFixedRateIrmFactory irmFactory,
        address[] memory predictedIrms
    ) private view {
        uint256 marketCount = mintMarkets.length;
        uint256 expectedCallCount = marketCount * 2;
        _assertTimelockCallCount(batch, expectedCallCount);
        assertEq(predictedIrms.length, marketCount, "wrong predicted IRM count");

        for (uint256 i; i < marketCount; ++i) {
            _assertTimelockCall(
                batch,
                i,
                address(irmFactory),
                abi.encodeCall(
                    OwnerFixedRateIrmFactory.deploy,
                    (mintMarkets[i], manifest.fixedRateIrmVersion, manifest.markets[i].fixedRateSpy)
                )
            );

            uint256 attachmentIndex = marketCount + i;
            _assertTimelockCall(
                batch, attachmentIndex, mintMarkets[i], abi.encodeCall(IMarketBase.setIrm, (predictedIrms[i], false))
            );
        }
    }

    function _predictIrms(OwnerFixedRateIrmFactory irmFactory) private view returns (address[] memory predictedIrms) {
        predictedIrms = new address[](mintMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            predictedIrms[i] = irmFactory.predictIrmAddress(
                mintMarkets[i], manifest.fixedRateIrmVersion, manifest.markets[i].fixedRateSpy
            );
        }
    }

    function _assertIrmDeploymentAndAttachment(
        OwnerFixedRateIrmFactory irmFactory,
        uint256 marketIndex,
        address predictedIrm
    ) private view {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        FixedRateIrm irm = FixedRateIrm(predictedIrm);
        (address deployedIrm, address deployedOwner, uint256 deployedRate) =
            irmFactory.deployments(address(market), manifest.fixedRateIrmVersion);

        assertEq(deployedIrm, predictedIrm, "wrong versioned IRM deployment");
        assertEq(deployedOwner, address(timelock), "wrong versioned IRM owner");
        assertEq(deployedRate, manifest.markets[marketIndex].fixedRateSpy, "wrong versioned IRM rate");
        assertEq(market.irm(), predictedIrm, "fixed-rate IRM not attached");
        assertGt(predictedIrm.code.length, 0, "fixed-rate IRM not deployed");
        assertEq(irm.market(), address(market), "fixed-rate IRM bound to wrong market");
        assertEq(irm.owner(), address(timelock), "Timelock does not own fixed-rate IRM");
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, manifest.markets[marketIndex].fixedRateSpy, "wrong fixed borrow rate");
    }

    function _assertMarketIrm(
        OwnerFixedRateIrmFactory irmFactory,
        uint256 marketIndex,
        address oldIrm,
        address predictedIrm,
        Balance memory borrowedBefore
    ) private {
        IMarket market = IMarket(mintMarkets[marketIndex]);
        _assertIrmDeploymentAndAttachment(irmFactory, marketIndex, predictedIrm);
        assertNotEq(predictedIrm, oldIrm, "market kept its old IRM");

        Balance memory borrowedAfter = market.totalBorrowed();
        assertEq(borrowedAfter.shares, borrowedBefore.shares, "IRM replacement changed borrow shares");
        assertGt(borrowedAfter.assets, borrowedBefore.assets, "old IRM interest was not accrued");
        _assertFrozenAndUnpaused(market);
        _assertEntrancesBlocked(marketIndex);
    }
}
