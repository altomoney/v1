// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LendingReport} from "../interfaces/IAltoReport.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {LiquidationConfiguration, RiskParams} from "@alto/lending/interfaces/IMarket.sol";
import {MarketDeployer} from "@alto/utils/MarketDeployer.sol";

abstract contract LendingProcedure {
    function _deployBorrowMarket(
        RiskParams memory params,
        LiquidationConfiguration memory liquidationConfiguration,
        bool shouldUseSafeProxy
    ) internal returns (address) {
        
        return MarketDeployer.deployBorrowMarket(
            params,
            liquidationConfiguration,
            shouldUseSafeProxy
        );
    }

    function _deployMintMarket(RiskParams memory params, LiquidationConfiguration memory liquidationConfiguration, bool shouldUseSafeProxy)
        internal
        returns (address)
    {
       

        return MarketDeployer.deployMintMarket(
            params,
            liquidationConfiguration,
            shouldUseSafeProxy
        );
    }
}
