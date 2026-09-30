// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Pausable} from "@alto/utils/Pausable.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

interface ILegacyEmergencyPauseTargets {
    function dusd() external view returns (address);
    function universalRewardsDistributor() external view returns (address);
}

interface IEmergencyPauserSafe {
    function getOwners() external view returns (address[] memory);
}

contract EmergencyControllerUpgradeForkTest is Test {
    uint256 internal constant FORK_BLOCK = 26089493;
    address internal constant CONTROLLER = 0x3c822f14a90955bf35278b42BA509FeEcAD3a305;
    address internal constant LEGACY_IMPLEMENTATION = 0xFE329F88663b9B8833b180A139315C131A033167;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    EmergencyController internal controller;
    address internal governance;
    address internal pendingGovernance;
    address internal responder;
    address internal dusd;
    address internal rewardsDistributor;
    bytes32[5] internal legacySlots;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        assertEq(address(uint160(uint256(vm.load(CONTROLLER, IMPLEMENTATION_SLOT)))), LEGACY_IMPLEMENTATION);

        controller = EmergencyController(CONTROLLER);
        governance = controller.owner();
        pendingGovernance = controller.pendingOwner();
        dusd = ILegacyEmergencyPauseTargets(CONTROLLER).dusd();
        rewardsDistributor = ILegacyEmergencyPauseTargets(CONTROLLER).universalRewardsDistributor();
        responder = IEmergencyPauserSafe(address(controller.pauserSafe())).getOwners()[0];
        for (uint256 i; i < legacySlots.length; ++i) {
            legacySlots[i] = vm.load(CONTROLLER, bytes32(i));
        }
    }

    function test_MainnetUpgradePreservesStorageAndPausePermissions() public {
        _upgrade();

        assertEq(controller.owner(), governance);
        assertEq(controller.pendingOwner(), pendingGovernance);
        for (uint256 i; i < legacySlots.length; ++i) {
            assertEq(vm.load(CONTROLLER, bytes32(i)), legacySlots[i]);
        }
        assertTrue(controller.pauseWhitelist(dusd));
        assertTrue(controller.pauseWhitelist(rewardsDistributor));
        assertFalse(controller.frozenWhitelist(dusd));
        assertFalse(controller.frozenWhitelist(rewardsDistributor));
        assertTrue(Pausable(dusd).pausers(CONTROLLER, PAUSE_TYPE));
        assertTrue(Pausable(rewardsDistributor).pausers(CONTROLLER, PAUSE_TYPE));

        vm.startPrank(responder);
        controller.pause(dusd);
        controller.pause(dusd);
        controller.pause(rewardsDistributor);
        controller.pause(rewardsDistributor);
        vm.stopPrank();
        assertTrue(IPausable(dusd).paused(PAUSE_TYPE));
        assertTrue(IPausable(rewardsDistributor).paused(PAUSE_TYPE));

        vm.prank(governance);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        controller.initializeV2();
    }

    function test_MainnetWhitelistRevocationBlocksLegacyPauseTargets() public {
        _upgrade();
        vm.startPrank(governance);
        controller.setPauseWhitelist(dusd, false);
        controller.setPauseWhitelist(rewardsDistributor, false);
        vm.stopPrank();

        vm.startPrank(responder);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.UnsupportedTarget.selector, dusd, PAUSE_TYPE));
        controller.pause(dusd);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyController.UnsupportedTarget.selector, rewardsDistributor, PAUSE_TYPE)
        );
        controller.pause(rewardsDistributor);
        vm.stopPrank();
    }

    function _upgrade() internal {
        EmergencyController implementation = new EmergencyController();
        vm.prank(governance);
        UUPSUpgradeable(CONTROLLER)
            .upgradeToAndCall(address(implementation), abi.encodeCall(EmergencyController.initializeV2, ()));
    }
}
