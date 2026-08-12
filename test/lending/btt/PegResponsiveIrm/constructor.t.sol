// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {
    PegResponsiveIrmConfig,
    IRState,
    IPegResponsiveIrmErrors,
    IPegResponsiveIrmEvents
} from "@alto/lending/interfaces/IPegResponsiveIrm.sol";
import {PegResponsiveIrmHarness} from "./PegResponsiveIrmHarness.sol";
import {PegResponsiveIrmCommon} from "./PegResponsiveIrmCommon.t.sol";

contract PegResponsiveIrmConstructorTest is PegResponsiveIrmCommon {
    function test_RevertWhen_InitialOwnerIsZero_BeforeOtherValidation() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;

        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        _deployIrm(invalidConfig, address(0), address(0));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_RevertWhen_OracleIsZero_BeforeConfigValidation() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;

        vm.expectRevert(IPegResponsiveIrmErrors.PegResponsiveIrmInvalidOracle.selector);
        _deployIrm(invalidConfig, address(0), OWNER);
    }

    function test_RevertWhen_StressPriceIsZero() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_RecoveryPriceExceedsMaximum() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE() + 1;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_StressPriceEqualsRecoveryPrice() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_StressPriceExceedsRecoveryPrice() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = invalidConfig.recoveryPrice + 1;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_BaseRateIsZero() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = 0;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_BaseRateExceedsStressRate() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = invalidConfig.stressRate + 1;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_StressRateEqualsMaxRate() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressRate = invalidConfig.maxRate;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_StressRateExceedsMaxRate() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressRate = invalidConfig.maxRate + 1;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_MaxRateExceedsMaximumBorrowRate() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.maxRate = irm.MAX_BORROW_RATE() + 1;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_RevertWhen_DoublingDistanceIsZero() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.doublingDistance = 0;
        _expectDeployConfigRevert(
            invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_RecoveryDelayIsZero() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.recoveryDelay = 0;
        _expectDeployConfigRevert(
            invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_MaxOracleAgeIsZero() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.maxOracleAge = 0;
        _expectDeployConfigRevert(
            invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidControllerConfig.selector
        );
    }

    function test_RevertWhen_PriceAndLaterGroupsAreInvalid_PrioritizesPriceError() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.stressPrice = 0;
        invalidConfig.baseRate = 0;
        invalidConfig.doublingDistance = 0;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidPriceConfig.selector);
    }

    function test_RevertWhen_RateAndControllerGroupsAreInvalid_PrioritizesRateError() external {
        PegResponsiveIrmConfig memory invalidConfig = irmConfig;
        invalidConfig.baseRate = 0;
        invalidConfig.doublingDistance = 0;
        _expectDeployConfigRevert(invalidConfig, IPegResponsiveIrmErrors.PegResponsiveIrmInvalidRateConfig.selector);
    }

    function test_AcceptsPriceBoundaryConfigurations() external {
        PegResponsiveIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.stressPrice = 1;
        boundaryConfig.recoveryPrice = 2;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.stressPrice = boundaryConfig.recoveryPrice - 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryPrice = irm.MAX_RECOVERY_PRICE();
        _deployAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsRateBoundaryConfigurations() external {
        PegResponsiveIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.baseRate = 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.baseRate = boundaryConfig.stressRate;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxRate = boundaryConfig.stressRate + 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxRate = irm.MAX_BORROW_RATE();
        _deployAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsControllerBoundaryConfigurations() external {
        PegResponsiveIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.doublingDistance = 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxOracleAge = 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.doublingDistance = type(uint256).max;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = type(uint48).max;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig = irmConfig;
        boundaryConfig.maxOracleAge = type(uint48).max;
        _deployAndAssertConfig(boundaryConfig);
    }

    function test_DoesNotRequireRelationshipBetweenRecoveryDelayAndMaxOracleAge() external {
        PegResponsiveIrmConfig memory boundaryConfig = irmConfig;
        boundaryConfig.recoveryDelay = 2;
        boundaryConfig.maxOracleAge = 1;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 2;
        _deployAndAssertConfig(boundaryConfig);

        boundaryConfig.maxOracleAge = 3;
        _deployAndAssertConfig(boundaryConfig);
    }

    function test_AcceptsOracleWithoutCode() external {
        address noCodeOracle = address(0xBEEF);
        assertEq(noCodeOracle.code.length, 0);

        PegResponsiveIrmHarness deployedIrm = _deployIrm(irmConfig, noCodeOracle, OWNER);
        assertEq(address(deployedIrm.oracle()), noCodeOracle);
    }

    function test_DoesNotSampleOracleDuringConstruction() external {
        rawOracle.setRawReturnData(hex"01");

        PegResponsiveIrmHarness deployedIrm = _deployIrm(irmConfig, address(rawOracle), OWNER);
        assertEq(address(deployedIrm.oracle()), address(rawOracle));
    }

    function test_WhenAllInputsAreValid_StoresStateAndEmitsExactOrderedEvents() external {
        vm.recordLogs();
        PegResponsiveIrmHarness deployedIrm = _deployIrm(irmConfig, address(oracle), OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        irm = deployedIrm;
        _assertIrmConfig(irmConfig);
        assertEq(address(deployedIrm.oracle()), address(oracle));
        assertEq(deployedIrm.market(), address(0));
        assertEq(deployedIrm.owner(), OWNER);
        assertEq(deployedIrm.pendingOwner(), address(0));

        IRState memory initialState =
            IRState({borrowRate: irmConfig.baseRate, lastUpdate: 0, recoveryStartedAt: 0, stressMode: false});
        _assertIRState(initialState);

        assertEq(logs.length, 4);
        _assertEvent(logs[0], address(deployedIrm), Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));

        _assertEvent(logs[1], address(deployedIrm), IPegResponsiveIrmEvents.SetPegOracle.selector);
        assertEq(logs[1].topics.length, 3);
        assertEq(logs[1].topics[1], bytes32(0));
        assertEq(logs[1].topics[2], bytes32(uint256(uint160(address(oracle)))));

        _assertEvent(logs[2], address(deployedIrm), IPegResponsiveIrmEvents.SetIrmConfig.selector);
        assertEq(logs[2].data, abi.encode(irmConfig));

        _assertEvent(logs[3], address(deployedIrm), IPegResponsiveIrmEvents.IRStateUpdated.selector);
        assertEq(logs[3].data, abi.encode(initialState));
    }

    function _expectDeployConfigRevert(PegResponsiveIrmConfig memory invalidConfig, bytes4 selector) private {
        vm.expectRevert(selector);
        _deployIrm(invalidConfig);
    }

    function _deployAndAssertConfig(PegResponsiveIrmConfig memory expectedConfig) private {
        irm = _deployIrm(expectedConfig);
        _assertIrmConfig(expectedConfig);
    }

    function _assertEvent(Vm.Log memory log, address expectedEmitter, bytes32 expectedSelector) private pure {
        assertEq(log.emitter, expectedEmitter);
        assertGt(log.topics.length, 0);
        assertEq(log.topics[0], expectedSelector);
    }
}
