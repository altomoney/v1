// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "./AltoBaseMarket.sol";
import {LiquidationConfiguration, RiskParams} from "./interfaces/IMarket.sol";

/// @title Alto Borrow Market
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An Isolated Borrow Market
contract AltoBorrowMarket is AltoBaseMarket {
    /// upgrade gap
    uint256[50] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        RiskParams memory _params,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _params,
            _liquidationConfiguration
        );
    }
}
