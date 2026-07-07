// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBorrowMarketUpgraded} from "@alto-test/lending/proxy/contracts/AltoBorrowMarketUpgraded.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
/// @dev Mainnet borrow markets are at OZ init version 1; fork upgrades use version 3.
contract AltoBorrowMarketUpgradedFork is AltoBorrowMarketUpgraded {
    /// @dev Reinitializer for version 2 upgrade on forked mainnet borrow markets.
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        override
        reinitializer(2)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }
}
