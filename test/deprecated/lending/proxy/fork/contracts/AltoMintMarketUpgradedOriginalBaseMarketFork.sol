// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {
    AltoMintMarketUpgradedOriginalBaseMarket
} from "@alto-test/lending/proxy/contracts/AltoMintMarketUpgradedOriginalBaseMarket.sol";

/// @custom:oz-upgrades-from AltoMintMarket
/// @dev Mainnet mint markets are already at OZ init version 2.
contract AltoMintMarketUpgradedOriginalBaseMarketFork is AltoMintMarketUpgradedOriginalBaseMarket {
    /// @dev Reinitializer for version 3 upgrade on forked mainnet mint markets.
    function initializeV2() public override reinitializer(3) {}
}
