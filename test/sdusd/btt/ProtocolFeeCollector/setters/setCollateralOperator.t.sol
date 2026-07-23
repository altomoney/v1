// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetCollateralOperator_Test is ProtocolFeeCollectorCommon {
    address internal NEW_OPERATOR = makeAddr("NewCollateralOperator");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setCollateralOperator(NEW_OPERATOR, true);
    }

    function test_RevertWhen_OperatorIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setCollateralOperator(address(0), true);
    }

    function test_RevertWhen_OperatorAlreadyHasRequestedStatus() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setCollateralOperator(COLLATERAL_OPERATOR, true);
    }

    function test_EnablesNewCollateralOperatorAndEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.CollateralOperatorSet(NEW_OPERATOR, true);

        vm.prank(ADMIN);
        collector.setCollateralOperator(NEW_OPERATOR, true);

        assertTrue(collector.isCollateralOperator(NEW_OPERATOR));
    }

    function test_DisablesExistingCollateralOperatorAndEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.CollateralOperatorSet(COLLATERAL_OPERATOR, false);

        vm.prank(ADMIN);
        collector.setCollateralOperator(COLLATERAL_OPERATOR, false);

        assertFalse(collector.isCollateralOperator(COLLATERAL_OPERATOR));
    }
}
