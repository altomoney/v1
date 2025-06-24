// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
contract AltoBorrowMarketUpgradedOriginalBaseMarket is AltoBaseMarket {
    uint128 public addedProperty1;

    address public addedProperty2;

    uint128 public addedProperty3;

    /// upgrade gap
    uint256[50] private __gap_borrow;

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
    function initializeV2() public reinitializer(2) {}

    function setAddedProperty1(uint128 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(address value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(uint128 value) external {
        addedProperty3 = value;
    }
}
