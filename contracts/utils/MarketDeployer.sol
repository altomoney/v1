// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {BorrowMarketInitParams, MintMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {Vm} from "forge-std/Vm.sol";

library MarketDeployer {
    function deployBorrowMarket(BorrowMarketInitParams memory _borrowMarketInitParams) external returns (address) {
        Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoBorrowMarket.sol:AltoBorrowMarket",
                abi.encodeCall(AltoBorrowMarket.initialize, (_borrowMarketInitParams))
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoBorrowMarket()), abi.encodeCall(AltoBorrowMarket.initialize, (_borrowMarketInitParams))
            );
        }
    }

    function deployMintMarket(MintMarketInitParams memory _mintMarketInitParams) external returns (address) {
        Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoMintMarket.sol:AltoMintMarket", abi.encodeCall(AltoMintMarket.initialize, (_mintMarketInitParams))
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initialize, (_mintMarketInitParams))
            );
        }
    }
}
