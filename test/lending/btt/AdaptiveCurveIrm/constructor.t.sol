// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {AdaptiveCurveIrmCommon} from "./AdaptiveCurveIrmCommon.t.sol";

contract AdaptiveCurveIrmConstructorTest is AdaptiveCurveIrmCommon {
    function test_RevertWhen_OwnerIsZero_BeforeParameterValidation() public {
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory invalidConfig = _invalidCurveSteepnessConfig();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new AdaptiveCurveIrm(invalidConfig, address(0));
    }

    function test_RevertWhen_AnyConfigurationFieldIsInvalid() public {
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases = _invalidConfigs();
        for (uint256 i; i < cases.length; ++i) {
            vm.expectRevert(IIrm.IrmInvalidParams.selector);
            new AdaptiveCurveIrm(cases[i], OWNER);
        }
    }

    function test_WhenConfigurationIsValid_StoresAllFieldsAndEmitsOnlyOwnership() public {
        _deployAndAssert(config);
    }

    function test_WhenConfigurationIsAtInclusiveBoundaries_AcceptsEveryBoundary() public {
        AdaptiveCurveIrm.AdaptiveCurveIrmConfig[] memory cases = _boundaryConfigs();
        for (uint256 i; i < cases.length; ++i) {
            _deployAndAssert(cases[i]);
        }
    }

    function _deployAndAssert(AdaptiveCurveIrm.AdaptiveCurveIrmConfig memory candidate) internal {
        vm.recordLogs();
        irm = new AdaptiveCurveIrm(candidate, OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(irm.owner(), OWNER);
        assertEq(irm.pendingOwner(), address(0));
        assertEq(irm.market(), address(0));
        _assertState(0, 0);
        _assertConfig(candidate);
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(irm));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], Ownable.OwnershipTransferred.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
        assertEq(logs[0].data.length, 0);
    }
}
