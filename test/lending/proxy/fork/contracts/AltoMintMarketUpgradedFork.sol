// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketUpgraded} from "../../contracts/AltoMintMarketUpgraded.sol";

/// @custom:oz-upgrades-from AltoMintMarket
/// @dev Mainnet mint markets are already at OZ init version 2.
contract AltoMintMarketUpgradedFork is AltoMintMarketUpgraded {
    /// @dev Reinitializer for version 3 upgrade on forked mainnet mint markets.
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        override
        reinitializer(3)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }
}
