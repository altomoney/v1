// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents,
    ProtocolFeeCollectorInitParams
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Initialize_Test is ProtocolFeeCollectorCommon {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_RevertWhen_ProxyAlreadyInitialized() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        collector.initialize(params);
    }

    function test_RevertWhen_AdminIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.admin = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_CollateralOperatorIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.collateralOperator = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_PauserIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.pauser = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_DusdIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.dusd = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_MarketRegistryIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.marketRegistry = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_UsmRegistryIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.usmRegistry = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_FlashMinterIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.flashMinter = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_TreasuryIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.treasury = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_ManualSwapReceiverIsZeroAddress() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.manualSwapReceiver = address(0);
        _expectZeroAddressInitializationRevert(params);
    }

    function test_RevertWhen_RewardsBpsExceedsPercentagePrecision() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.rewardsBps = collector.PERCENTAGE_PRECISION() + 1;

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidRewardsBps.selector);
        _deployCollector(params);
    }

    function test_RevertWhen_MinimumRewardAmountIsZero() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.minimumRewardAmount = 0;

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidMinimumRewardAmount.selector);
        _deployCollector(params);
    }

    function test_InitializesAllConfigurationAndRoles() public view {
        assertEq(collector.owner(), ADMIN);
        assertEq(collector.pendingOwner(), address(0));
        assertTrue(collector.isCollateralOperator(COLLATERAL_OPERATOR));
        assertTrue(collector.pausers(PAUSER, PAUSE_TYPE));
        assertTrue(collector.pausers(ADMIN, PAUSE_TYPE));
        assertEq(collector.dusd(), address(dusd));
        assertEq(address(collector.marketRegistry()), address(marketRegistry));
        assertEq(address(collector.usmRegistry()), address(usmRegistry));
        assertEq(collector.flashMinter(), address(flashMinter));
        assertEq(collector.treasury(), TREASURY);
        assertEq(collector.manualSwapReceiver(), MANUAL_SWAP_RECEIVER);
        assertEq(collector.sdusdVault(), address(0));
        assertFalse(collector.paused(PAUSE_TYPE));
        assertEq(collector.rewardsBps(), INITIAL_REWARDS_BPS);
        assertEq(collector.minimumRewardAmount(), INITIAL_MINIMUM_REWARD_AMOUNT);
    }

    function test_EmitsAllConfigurationAndRoleEvents() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), ADMIN);
        vm.expectEmit(true, false, false, true);
        emit IProtocolFeeCollectorEvents.CollateralOperatorSet(COLLATERAL_OPERATOR, true);
        vm.expectEmit(true, false, false, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);
        vm.expectEmit(true, false, false, true);
        emit IPausable.PauserUpdated(ADMIN, PAUSE_TYPE, true);
        vm.expectEmit(true, true, false, true);
        emit IProtocolFeeCollectorEvents.MarketRegistryUpdated(address(0), address(marketRegistry));
        vm.expectEmit(true, true, false, true);
        emit IProtocolFeeCollectorEvents.UsmRegistryUpdated(address(0), address(usmRegistry));
        vm.expectEmit(true, true, false, true);
        emit IProtocolFeeCollectorEvents.FlashMinterUpdated(address(0), address(flashMinter));
        vm.expectEmit(true, true, false, true);
        emit IProtocolFeeCollectorEvents.TreasuryUpdated(address(0), TREASURY);
        vm.expectEmit(true, true, false, true);
        emit IProtocolFeeCollectorEvents.ManualSwapReceiverUpdated(address(0), MANUAL_SWAP_RECEIVER);
        vm.expectEmit(false, false, false, true);
        emit IProtocolFeeCollectorEvents.RewardsBpsUpdated(0, INITIAL_REWARDS_BPS);
        vm.expectEmit(false, false, false, true);
        emit IProtocolFeeCollectorEvents.MinimumRewardAmountUpdated(0, INITIAL_MINIMUM_REWARD_AMOUNT);

        _deployCollector(params);
    }

    function test_InitializesRewardsBpsToZero() public {
        ProtocolFeeCollectorInitParams memory params = _validInitParams();
        params.rewardsBps = 0;

        vm.recordLogs();
        ProtocolFeeCollector deployed = _deployCollector(params);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(deployed.rewardsBps(), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.RewardsBpsUpdated.selector, address(deployed)), 0);
    }

    function test_InitializesRewardsBpsToProvidedNonZeroValue() public view {
        assertEq(collector.rewardsBps(), INITIAL_REWARDS_BPS);
    }

    function _expectZeroAddressInitializationRevert(ProtocolFeeCollectorInitParams memory params) internal {
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        _deployCollector(params);
    }
}
