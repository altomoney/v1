// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetPauser_Test is ProtocolFeeCollectorCommon {
    address internal NEW_PAUSER = makeAddr("NewPauser");
    bytes32 internal constant OTHER_PAUSE_TYPE = keccak256("OTHER_PAUSE_TYPE");

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setPauser(NEW_PAUSER, PAUSE_TYPE, true);
    }

    function test_EnablesPauserForSpecifiedPauseTypeAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.PauserUpdated(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        vm.prank(ADMIN);
        collector.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        assertTrue(collector.pausers(NEW_PAUSER, OTHER_PAUSE_TYPE));
    }

    function test_DisablesPauserForSpecifiedPauseTypeAndEmitsEvent() public {
        vm.prank(ADMIN);
        collector.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.PauserUpdated(NEW_PAUSER, OTHER_PAUSE_TYPE, false);

        vm.prank(ADMIN);
        collector.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, false);

        assertFalse(collector.pausers(NEW_PAUSER, OTHER_PAUSE_TYPE));
    }

    function test_AllowsZeroAddressPauserAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.PauserUpdated(address(0), OTHER_PAUSE_TYPE, true);

        vm.prank(ADMIN);
        collector.setPauser(address(0), OTHER_PAUSE_TYPE, true);

        assertTrue(collector.pausers(address(0), OTHER_PAUSE_TYPE));
    }

    function test_AllowsSamePauserStatusAndEmitsEvent() public {
        vm.prank(ADMIN);
        collector.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        vm.expectEmit(true, true, false, true, address(collector));
        emit IPausable.PauserUpdated(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        vm.prank(ADMIN);
        collector.setPauser(NEW_PAUSER, OTHER_PAUSE_TYPE, true);

        assertTrue(collector.pausers(NEW_PAUSER, OTHER_PAUSE_TYPE));
    }
}
