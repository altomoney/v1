// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BorrowMarketOffboardingTestBase} from "./BorrowMarketOffboardingTestBase.sol";
import {BorrowMarketOffboardingPhase} from "../IBorrowMarketOffboarding.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

contract BatchBSetFixedRateIrmTest is BorrowMarketOffboardingTestBase {
    OwnerFixedRateIrmFactory internal factory;
    address[] internal predictedIrms;

    function setUp() public {
        _setUpManifest();
        if (marketAlreadyFrozen) return;

        _seedStandardPositions();
        factory = _ensureFactory();
        _executeContainmentPrerequisite();
        _assertAllFrozenAndUnpaused();
    }

    function testBatchBDeploysAndAttachesDedicatedFixedRateIrmsAndPreservesExitRoutes() public {
        if (marketAlreadyFrozen) return;

        uint256 initialNonce = factory.nonce();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            predictedIrms.push(factory.predictIrmAddress(FIXED_RATE_SPY, address(timelock), initialNonce + i));
        }

        _executeTimelockPhase(
            BorrowMarketOffboardingPhase.BATCH_B_SET_FIXED_RATE_IRM, FIXED_IRM_SCHEDULE_FILE, FIXED_IRM_EXECUTE_FILE
        );

        assertEq(factory.nonce(), initialNonce + borrowMarkets.length, "wrong factory nonce");
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertMarketIrmAndRoutes(i);
        }
    }

    function _assertMarketIrmAndRoutes(uint256 marketIndex) internal {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        FixedRateIrm irm = FixedRateIrm(predictedIrms[marketIndex]);

        assertEq(market.irm(), address(irm), "fixed-rate IRM not attached");
        assertGt(address(irm).code.length, 0, "fixed-rate IRM not deployed");
        assertEq(irm.market(), address(market), "fixed-rate IRM bound to wrong market");
        assertEq(irm.owner(), address(timelock), "Timelock does not own fixed-rate IRM");
        (uint256 borrowRate,) = irm.irState();
        assertEq(borrowRate, FIXED_RATE_SPY, "wrong fixed borrow rate");

        _assertFrozenAndUnpaused(market);
        _exerciseExitAndLiquidationRoutes(market, fixtures[marketIndex]);
        _assertFrozenAndUnpaused(market);
    }
}
