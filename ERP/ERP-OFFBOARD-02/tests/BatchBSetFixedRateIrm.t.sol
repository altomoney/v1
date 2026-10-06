// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract BatchBSetFixedRateIrmTest is BorrowMarketOffboardingTestBase {
    OwnerFixedRateIrmFactory internal factory;

    function setUp() public {
        _setUpManifest();
    }

    function _prepareContainedMarkets(string memory activationId) private {
        manifest.activationId = activationId;
        for (uint256 i; i < borrowMarkets.length; ++i) {
            assertFalse(IMarketBase(borrowMarkets[i]).paused(FROZEN_TYPE), "market initially frozen");
        }
        _seedStandardPositions();
        _executeBatchA();
        _assertAllFrozenAndUnpaused();
    }

    /// @dev Manifest: five Batch-A-contained, debt-bearing markets with a fixed rate per market and a common IRM
    /// version; the deployment input has no factory. Deploys a Timelock-owned factory, then executes the generated
    /// schedule/execute pair whose single batch deploys and attaches each market's dedicated versioned fixed-rate IRM.
    /// Verifies rates, ownership, interest accrual, unchanged borrow shares, frozen/unpaused state, and that repayment,
    /// withdrawals, liquidation, and required exit integrations continue to work.
    function testBatchBDeploysAndAttachesDedicatedFixedRateIrmsAndPreservesExitRoutes() public {
        _prepareContainedMarkets("fixed-rate-deploy-and-attach");
        address[] memory oldIrms = new address[](borrowMarkets.length);
        address[] memory predictedIrms = new address[](borrowMarkets.length);
        Balance[] memory borrowedBefore = new Balance[](borrowMarkets.length);

        assertEq(input.contracts.ownerFixedRateIrmFactory, address(0), "test requires missing factory");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            oldIrms[i] = market.irm();
            borrowedBefore[i] = market.totalBorrowed();
            assertGt(borrowedBefore[i].shares, 0, "test requires market debt");
        }

        BorrowMarketOffboardingPhase phase = BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM;
        input = scriptHarness.runPhase(phase, manifest, input);
        factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        assertGt(address(factory).code.length, 0, "factory not deployed");
        assertEq(factory.owner(), address(timelock), "Timelock does not own factory");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            predictedIrms[i] = factory.predictIrmAddress(
                borrowMarkets[i], manifest.fixedRateIrmVersion, manifest.markets[i].fixedRateSpy
            );
        }

        _executeTimelockArtifacts(phase, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketIrmAndRoutes(i, oldIrms[i], predictedIrms[i], borrowedBefore[i]);
        }
    }

    /// @dev Manifest: the same five contained markets, but deployment input points to an existing Timelock-owned factory.
    /// Executes the generated Timelock pair and verifies the factory address is preserved while its versioned IRM for
    /// every manifest market is deployed and attached.
    function testBatchBUsesExistingFactoryWithoutRedeploying() public {
        _prepareContainedMarkets("fixed-rate-existing-factory");
        OwnerFixedRateIrmFactory existingFactory = _setExistingFactory();

        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );

        assertEq(input.contracts.ownerFixedRateIrmFactory, address(existingFactory), "existing factory was replaced");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            (address deployedIrm,,) = existingFactory.deployments(borrowMarkets[i], manifest.fixedRateIrmVersion);
            assertEq(IMarket(borrowMarkets[i]).irm(), deployedIrm, "existing factory IRM not attached");
        }
    }

    /// @dev Manifest: five frozen/unpaused markets, with one market made to report zero borrowed assets and shares.
    /// Verifies fixed-rate preparation rejects the activation with `debt targets reached` instead of attaching an IRM
    /// after that market has already met the ERP terminal debt target.
    function testBatchBRejectsMarketWithNoRemainingDebt() public {
        _prepareContainedMarkets("fixed-rate-zero-debt");
        vm.mockCall(
            borrowMarkets[0], abi.encodeCall(IMarket.totalBorrowed, ()), abi.encode(Balance({assets: 0, shares: 0}))
        );

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: debt targets reached");
    }

    /// @dev Manifest: five Batch-A markets, but the freeze is removed from one market before fixed-rate preparation.
    /// Verifies generation rejects the manifest because every affected market must remain frozen throughout Batch B.
    function testBatchBRejectsUnfrozenMarket() public {
        _prepareContainedMarkets("fixed-rate-unfrozen");
        vm.prank(manifest.freezerSafe);
        IPausable(borrowMarkets[0]).pause(FROZEN_TYPE, false);

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: market not frozen");
    }

    /// @dev Manifest: five frozen markets, with the full pause additionally enabled on one affected market.
    /// Verifies generation rejects the manifest because Batch B requires `FROZEN_TYPE=true` and `PAUSE_TYPE=false` so
    /// repayment, withdrawals, accrual, and liquidation remain available.
    function testBatchBRejectsPausedMarket() public {
        _prepareContainedMarkets("fixed-rate-paused");
        vm.prank(manifest.freezerSafe);
        IPausable(borrowMarkets[0]).pause(PAUSE_TYPE, true);

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: market paused");
    }

    /// @dev Manifest: five valid contained markets, but one market's `fixedRateSpy` exceeds the IRM maximum by one unit.
    /// Verifies the per-market rate bound is enforced before any fixed-rate deployment or attachment is scheduled.
    function testBatchBRejectsRateAboveIrmMaximum() public {
        _prepareContainedMarkets("fixed-rate-above-maximum");
        manifest.markets[0].fixedRateSpy = 8 ether / uint256(365 days) + 1;

        _expectPhaseRevert(BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: rate above IRM maximum");
    }

    /// @dev Manifest input references an existing factory whose ownership has been transferred away from the Timelock.
    /// Verifies preparation rejects the factory rather than generating IRM deployments that governance cannot control.
    function testBatchBRejectsFactoryNotOwnedByTimelock() public {
        _prepareContainedMarkets("fixed-rate-wrong-owner");
        _setExistingFactory();
        vm.prank(address(timelock));
        factory.transferOwnershipSkip2Step(makeAddr("new-factory-owner"));

        _expectPhaseRevert(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: Timelock does not own factory"
        );
    }

    /// @dev Manifest input references an existing Timelock-owned factory with a nonzero pending owner.
    /// Verifies preparation rejects this transitional ownership state before generating the fixed-rate Timelock batch.
    function testBatchBRejectsPendingFactoryOwnershipTransfer() public {
        _prepareContainedMarkets("fixed-rate-pending-owner");
        _setExistingFactory();
        vm.prank(address(timelock));
        factory.transferOwnership(makeAddr("pending-factory-owner"));

        _expectPhaseRevert(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, "Batch B: factory ownership transfer pending"
        );
    }

    function _setExistingFactory() private returns (OwnerFixedRateIrmFactory existingFactory) {
        existingFactory = new OwnerFixedRateIrmFactory(address(timelock));
        factory = existingFactory;
        input.contracts.ownerFixedRateIrmFactory = address(existingFactory);
    }

    function _assertMarketIrmAndRoutes(
        uint256 marketIndex,
        address oldIrm,
        address predictedIrm,
        Balance memory borrowedBefore
    ) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        FixedRateIrm irm = FixedRateIrm(predictedIrm);
        (address deployedIrm, address deployedOwner, uint256 deployedRate) =
            factory.deployments(address(market), manifest.fixedRateIrmVersion);
        assertEq(deployedIrm, address(irm), "wrong versioned IRM deployment");
        assertEq(deployedOwner, address(timelock), "wrong versioned IRM owner");
        assertEq(deployedRate, manifest.markets[marketIndex].fixedRateSpy, "wrong versioned IRM rate");

        assertNotEq(address(irm), oldIrm, "market kept its old IRM");
        assertEq(market.irm(), address(irm), "fixed-rate IRM not attached");
        assertGt(address(irm).code.length, 0, "fixed-rate IRM not deployed");
        assertEq(irm.market(), address(market), "fixed-rate IRM bound to wrong market");
        assertEq(irm.owner(), address(timelock), "Timelock does not own fixed-rate IRM");
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, manifest.markets[marketIndex].fixedRateSpy, "wrong fixed borrow rate");

        Balance memory borrowedAfterAttachment = market.totalBorrowed();
        assertEq(borrowedAfterAttachment.shares, borrowedBefore.shares, "IRM replacement changed borrow shares");
        assertGt(borrowedAfterAttachment.assets, borrowedBefore.assets, "old IRM interest was not accrued");

        _assertFrozenAndUnpaused(market);
        _assertRequiredExitIntegrationsActive(marketIndex);

        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();
        Balance memory borrowedAfterFixedRateAccrual = market.totalBorrowed();
        assertEq(
            borrowedAfterFixedRateAccrual.shares,
            borrowedAfterAttachment.shares,
            "fixed-rate accrual changed borrow shares"
        );
        assertGt(
            borrowedAfterFixedRateAccrual.assets,
            borrowedAfterAttachment.assets,
            "fixed-rate IRM did not accrue interest"
        );

        _exerciseExitAndLiquidationRoutes(market, fixtures[marketIndex]);
        _assertFrozenAndUnpaused(market);
        _assertRequiredExitIntegrationsActive(marketIndex);
    }
}
