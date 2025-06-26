// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {Vm} from "forge-std/Vm.sol";

library MarketDeployer {
    function deployBorrowMarket(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) external returns (address) {
        Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoBorrowMarket.sol:AltoBorrowMarket",
                abi.encodeCall(
                    AltoBorrowMarket.initialize,
                    (
                        _borrowToken,
                        _collateralToken,
                        _irm,
                        _owner,
                        _oracle,
                        _maxLtv,
                        _borrowOpeningFee,
                        _feeRecipient,
                        _liquidationConfiguration
                    )
                )
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoBorrowMarket()),
                abi.encodeCall(
                    AltoBorrowMarket.initialize,
                    (
                        _borrowToken,
                        _collateralToken,
                        _irm,
                        _owner,
                        _oracle,
                        _maxLtv,
                        _borrowOpeningFee,
                        _feeRecipient,
                        _liquidationConfiguration
                    )
                )
            );
        }
    }

    function deployMintMarket(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _debtCeiling,
        address _feeRecipient,
        uint256 _borrowOpeningFee,
        LiquidationConfiguration memory _liquidationConfiguration
    ) external returns (address) {
        Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            return Upgrades.deployUUPSProxy(
                "AltoMintMarket.sol:AltoMintMarket",
                abi.encodeCall(
                    AltoMintMarket.initialize,
                    (
                        _borrowToken,
                        _collateralToken,
                        _irm,
                        _owner,
                        _oracle,
                        _maxLtv,
                        _debtCeiling,
                        _feeRecipient,
                        _borrowOpeningFee,
                        _liquidationConfiguration
                    )
                )
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new AltoMintMarket()),
                abi.encodeCall(
                    AltoMintMarket.initialize,
                    (
                        _borrowToken,
                        _collateralToken,
                        _irm,
                        _owner,
                        _oracle,
                        _maxLtv,
                        _debtCeiling,
                        _feeRecipient,
                        _borrowOpeningFee,
                        _liquidationConfiguration
                    )
                )
            );
        }
    }
}
