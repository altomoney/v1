// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {PausableMock} from "@alto-test/lending/btt/Pausable/PausableMock.sol";

contract MockSafeOwnerManager {
    mapping(address owner => bool) public isOwner;

    function setOwner(address owner, bool status) external {
        isOwner[owner] = status;
    }
}

contract MockEmergencyUsm {
    address public freezer;
    bool private _isFrozen;

    function setFreezer(address newFreezer) external {
        freezer = newFreezer;
    }

    function setSwapFreeze(bool enable) external {
        require(msg.sender == freezer, "NOT_FREEZER");
        require(enable != _isFrozen, "STATE_NOT_CHANGED");
        _isFrozen = enable;
    }

    function getIsFrozen() external view returns (bool) {
        return _isFrozen;
    }
}

contract EmergencyControllerV2 is EmergencyController {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract EmergencyControllerTest is Test {
    address internal responder = makeAddr("responder");
    address internal removedResponder = makeAddr("removedResponder");
    address internal outsider = makeAddr("outsider");
    address internal governance = makeAddr("governance");

    MockSafeOwnerManager internal safe;
    MarketRegistry internal marketRegistry;
    UsmRegistry internal usmRegistry;
    PausableMock internal mintMarket;
    PausableMock internal borrowMarket;
    PausableMock internal dusd;
    PausableMock internal rewardsDistributor;
    MockEmergencyUsm internal usm;
    EmergencyController internal controller;
    address internal proxy;

    function setUp() public {
        safe = new MockSafeOwnerManager();
        safe.setOwner(responder, true);
        safe.setOwner(removedResponder, true);

        marketRegistry = new MarketRegistry(address(this));
        usmRegistry = new UsmRegistry(address(this));

        mintMarket = new PausableMock(address(this));
        borrowMarket = new PausableMock(address(this));
        dusd = new PausableMock(address(this));
        rewardsDistributor = new PausableMock(address(this));
        usm = new MockEmergencyUsm();

        marketRegistry.addMintMarket(address(mintMarket));
        marketRegistry.addBorrowMarket(address(borrowMarket));
        usmRegistry.addUsm(address(usm));

        EmergencyController implementation = _newImplementation();
        proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                EmergencyController.initialize,
                (
                    governance,
                    address(safe),
                    address(marketRegistry),
                    address(usmRegistry),
                    address(dusd),
                    address(rewardsDistributor)
                )
            )
        );
        controller = EmergencyController(proxy);

        mintMarket.setPauser(address(controller), PAUSE_TYPE, true);
        mintMarket.setPauser(address(controller), FROZEN_TYPE, true);
        borrowMarket.setPauser(address(controller), PAUSE_TYPE, true);
        borrowMarket.setPauser(address(controller), FROZEN_TYPE, true);
        dusd.setPauser(address(controller), PAUSE_TYPE, true);
        rewardsDistributor.setPauser(address(controller), PAUSE_TYPE, true);
        usm.setFreezer(address(controller));
    }

    function test_UsesLiveSafeOwnership() public {
        vm.prank(responder);
        controller.pauseMarket(address(mintMarket));

        safe.setOwner(removedResponder, false);

        vm.prank(removedResponder);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.Unauthorized.selector, removedResponder));
        controller.freezeMarket(address(mintMarket));
    }

    function test_RejectsNonSafeOwner() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.Unauthorized.selector, outsider));
        controller.pauseDusd();
    }

    function test_PausesAndFreezesRegisteredMarketIdempotently() public {
        vm.startPrank(responder);
        controller.pauseMarket(address(mintMarket));
        controller.pauseMarket(address(mintMarket));
        controller.freezeMarket(address(mintMarket));
        controller.freezeMarket(address(mintMarket));
        vm.stopPrank();

        assertTrue(mintMarket.paused(PAUSE_TYPE));
        assertTrue(mintMarket.paused(FROZEN_TYPE));
    }

    function test_RejectsUnregisteredMarket() public {
        PausableMock unregistered = new PausableMock(address(this));

        vm.prank(responder);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.UnregisteredMarket.selector, address(unregistered)));
        controller.pauseMarket(address(unregistered));
    }

    function test_FreezesRegisteredUsmsIdempotently() public {
        vm.startPrank(responder);
        controller.freezeUsm(address(usm));
        controller.freezeUsm(address(usm));
        vm.stopPrank();

        assertTrue(usm.getIsFrozen());
    }

    function test_RejectsUnregisteredUsm() public {
        MockEmergencyUsm unregistered = new MockEmergencyUsm();

        vm.prank(responder);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.UnregisteredUsm.selector, address(unregistered)));
        controller.freezeUsm(address(unregistered));
    }

    function test_PausesSingletonsIdempotently() public {
        vm.startPrank(responder);
        controller.pauseDusd();
        controller.pauseDusd();
        controller.pauseUniversalRewardsDistributor();
        controller.pauseUniversalRewardsDistributor();
        vm.stopPrank();

        assertTrue(dusd.paused(PAUSE_TYPE));
        assertTrue(rewardsDistributor.paused(PAUSE_TYPE));
    }

    function test_GovernanceCanSetDependencies() public {
        MockSafeOwnerManager newSafe = new MockSafeOwnerManager();
        MarketRegistry newMarketRegistry = new MarketRegistry(address(this));
        UsmRegistry newUsmRegistry = new UsmRegistry(address(this));
        PausableMock newDusd = new PausableMock(address(this));
        PausableMock newRewardsDistributor = new PausableMock(address(this));

        vm.startPrank(governance);

        vm.expectEmit(true, true, false, false, address(controller));
        emit EmergencyController.PauserSafeSet(address(safe), address(newSafe));
        controller.setPauserSafe(address(newSafe));

        vm.expectEmit(true, true, false, false, address(controller));
        emit EmergencyController.MarketRegistrySet(address(marketRegistry), address(newMarketRegistry));
        controller.setMarketRegistry(address(newMarketRegistry));

        vm.expectEmit(true, true, false, false, address(controller));
        emit EmergencyController.UsmRegistrySet(address(usmRegistry), address(newUsmRegistry));
        controller.setUsmRegistry(address(newUsmRegistry));

        vm.expectEmit(true, true, false, false, address(controller));
        emit EmergencyController.DusdSet(address(dusd), address(newDusd));
        controller.setDusd(address(newDusd));

        vm.expectEmit(true, true, false, false, address(controller));
        emit EmergencyController.UniversalRewardsDistributorSet(
            address(rewardsDistributor), address(newRewardsDistributor)
        );
        controller.setUniversalRewardsDistributor(address(newRewardsDistributor));

        vm.stopPrank();

        assertEq(address(controller.pauserSafe()), address(newSafe));
        assertEq(address(controller.marketRegistry()), address(newMarketRegistry));
        assertEq(address(controller.usmRegistry()), address(newUsmRegistry));
        assertEq(address(controller.dusd()), address(newDusd));
        assertEq(address(controller.universalRewardsDistributor()), address(newRewardsDistributor));
    }

    function test_OnlyGovernanceCanSetDependencies() public {
        vm.startPrank(responder);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        controller.setPauserSafe(outsider);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        controller.setMarketRegistry(outsider);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        controller.setUsmRegistry(outsider);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        controller.setDusd(outsider);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        controller.setUniversalRewardsDistributor(outsider);

        vm.stopPrank();
    }

    function test_SettersRejectZeroAddress() public {
        vm.startPrank(governance);

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        controller.setPauserSafe(address(0));

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        controller.setMarketRegistry(address(0));

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        controller.setUsmRegistry(address(0));

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        controller.setDusd(address(0));

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        controller.setUniversalRewardsDistributor(address(0));

        vm.stopPrank();
    }

    function test_ProxyUpgradeIsRestrictedToGovernance() public {
        EmergencyControllerV2 implementation = new EmergencyControllerV2();

        vm.prank(responder);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, responder));
        UUPSUpgradeable(proxy).upgradeToAndCall(address(implementation), "");

        vm.prank(governance);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(implementation), "");

        assertEq(EmergencyControllerV2(proxy).version(), 2);
        assertEq(address(EmergencyControllerV2(proxy).pauserSafe()), address(safe));
    }

    function test_ProxyCannotBeReinitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        controller.initialize(
            outsider,
            address(safe),
            address(marketRegistry),
            address(usmRegistry),
            address(dusd),
            address(rewardsDistributor)
        );
    }

    function test_InitializerRejectsZeroAddress() public {
        EmergencyController implementation = _newImplementation();

        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                EmergencyController.initialize,
                (
                    governance,
                    address(0),
                    address(marketRegistry),
                    address(usmRegistry),
                    address(dusd),
                    address(rewardsDistributor)
                )
            )
        );
    }

    function test_ProxyConfiguration() public view {
        assertEq(address(controller.pauserSafe()), address(safe));
        assertEq(address(controller.marketRegistry()), address(marketRegistry));
        assertEq(address(controller.usmRegistry()), address(usmRegistry));
        assertEq(address(controller.dusd()), address(dusd));
        assertEq(address(controller.universalRewardsDistributor()), address(rewardsDistributor));
        assertEq(controller.owner(), governance);
    }

    function _newImplementation() internal returns (EmergencyController) {
        return new EmergencyController();
    }
}
