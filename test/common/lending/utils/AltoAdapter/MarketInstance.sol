// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {LiquidationConfiguration, RiskParams} from "@alto/lending/interfaces/IMarket.sol";

contract MarketInstance is AltoBaseMarket {
    function initialize(
        RiskParams memory _params,
     
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _params,
            _liquidationConfiguration
        );
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
