// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarketUpgraded} from "./AltoBaseMarketUpgraded.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
contract AltoBorrowMarketUpgraded is AltoBaseMarketUpgraded {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        );
    }

    /// @dev Reinitializer for version 2 upgrade - initializes new storage variables
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        reinitializer(2)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }

    function setAddedProperty1(uint256 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(uint256 value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(address value) external {
        addedProperty3 = value;
    }
}
