// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_SetMarketRegistry_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER));
        collector.setMarketRegistry(address(1));
    }

    function test_RevertWhen_NewMarketRegistryIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorZeroAddress.selector);
        collector.setMarketRegistry(address(0));
    }

    function test_RevertWhen_NewMarketRegistryEqualsCurrentRegistry() public {
        vm.prank(ADMIN);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorNoStateChange.selector);
        collector.setMarketRegistry(address(marketRegistry));
    }

    function test_UpdatesMarketRegistryAndEmitsEvent() public {
        MarketRegistry newRegistry = new MarketRegistry(ADMIN);

        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.MarketRegistryUpdated(address(marketRegistry), address(newRegistry));

        vm.prank(ADMIN);
        collector.setMarketRegistry(address(newRegistry));

        assertEq(address(collector.marketRegistry()), address(newRegistry));
    }
}
