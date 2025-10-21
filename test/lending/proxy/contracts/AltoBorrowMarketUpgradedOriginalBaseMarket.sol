// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
contract AltoBorrowMarketUpgradedOriginalBaseMarket is AltoBorrowMarket {
    uint128 public addedProperty1;

    address public addedProperty2;

    uint128 public addedProperty3;

    /// upgrade gap (previous slot has 16 bytes left)
    uint256[47] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
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
