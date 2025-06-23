// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

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
    }
}
