// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    AltoBorrowMarketUpgradedOriginalBaseMarket
} from "@alto-test/lending/proxy/contracts/AltoBorrowMarketUpgradedOriginalBaseMarket.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
/// @dev Mainnet borrow markets are at OZ init version 1; fork upgrades use version 3.
contract AltoBorrowMarketUpgradedOriginalBaseMarketFork is AltoBorrowMarketUpgradedOriginalBaseMarket {
    /// @dev Reinitializer for version 2 upgrade on forked mainnet borrow markets.
    function initializeV2() public override reinitializer(2) {}
}
