// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration, RiskParams} from "@alto/lending/interfaces/IMarket.sol";
import {Vm} from "forge-std/Vm.sol";

library MarketDeployer {
    function deployBorrowMarket(
        RiskParams memory _params,
        LiquidationConfiguration memory _liquidationConfiguration,
        bool _shouldUseSafeProxy
    ) internal returns (address) {
        if (_shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoBorrowMarket.sol:AltoBorrowMarket",
                abi.encodeCall(
                    AltoBorrowMarket.initialize,
                    (_params, _liquidationConfiguration)
                )
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoBorrowMarket()),
                abi.encodeCall(
                    AltoBorrowMarket.initialize,
                    (_params, _liquidationConfiguration)
                )
            );
        }
    }

    function deployMintMarket(
        RiskParams memory _params,
        LiquidationConfiguration memory _liquidationConfiguration,
        bool _shouldUseSafeProxy
    ) internal returns (address) {
        if (_shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoMintMarket.sol:AltoMintMarket",
                abi.encodeCall(
                    AltoMintMarket.initialize,
                    (_params, _liquidationConfiguration)
                )
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoMintMarket()),
                abi.encodeCall(
                    AltoMintMarket.initialize,
                    (_params, _liquidationConfiguration)
                )
            );
        }
    }
}
