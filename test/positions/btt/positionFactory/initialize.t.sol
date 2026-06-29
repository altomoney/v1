// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {PositionFactoryCommon} from "./PositionFactoryCommon.t.sol";
import {PositionFactory} from "@alto/positions/PositionFactory.sol";
import {IPositionFactoryErrors, IPositionFactoryEvents} from "@alto/positions/interfaces/IPositionFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";

contract PositionFactory_Initialize_Test is PositionFactoryCommon {
    function setUp() public override {
        registry = new MarketRegistry(OWNER);
    }

    function test_RevertWhen_AdminIsZeroAddress() public {
        PositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectRevert(IPositionFactoryErrors.PositionFactoryZeroAddress.selector);
        uninitializedFactory.initialize(address(0), address(registry));
    }

    function test_RevertWhen_MarketRegistryIsZeroAddress() public {
        PositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectRevert(IPositionFactoryErrors.PositionFactoryZeroAddress.selector);
        uninitializedFactory.initialize(OWNER, address(0));
    }

    function test_Initialize_WhenAdminAndMarketRegistryAreValid() public {
        PositionFactory uninitializedFactory = _deployUninitializedFactory();

        vm.expectEmit(true, false, false, true);
        emit IPositionFactoryEvents.MarketRegistrySet(address(registry));

        uninitializedFactory.initialize(OWNER, address(registry));

        assertEq(uninitializedFactory.marketRegistry(), address(registry));
        assertEq(uninitializedFactory.owner(), OWNER);
    }

    function test_RevertWhen_ReInitializing() public {
        PositionFactory initializedFactory = _deployInitializedFactory();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        initializedFactory.initialize(OWNER, address(registry));
    }
}
