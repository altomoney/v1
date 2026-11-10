// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {LiquidationPeriphery} from "@alto/lending/liquidation/LiquidationPeriphery.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";

struct LiquidationPeripheryBatchParams {
    address owner;
    address borrowToken;
    address usmRegistry;
    address treasury;
    address[] markets;
}

struct LiquidationPeripheryBatchReport {
    address liquidationPeriphery;
}

/// @notice Deploys LiquidationPeriphery and registers all markets in a single transaction
contract LiquidationPeripheryBatch {
    LiquidationPeripheryBatchReport public report;

    constructor(LiquidationPeripheryBatchParams memory _params) {
        uint256 count = _params.markets.length;

        address periphery = address(
            new LiquidationPeriphery(address(this), _params.borrowToken, _params.usmRegistry, _params.treasury)
        );

        for (uint256 i = 0; i < count; i++) {
            address market = _params.markets[i];
            LiquidationPeriphery(periphery).setSupportedMarket(market, true);
        }

        AltoOwnable2Step(periphery).transferOwnershipSkip2Step(_params.owner);

        report = LiquidationPeripheryBatchReport({liquidationPeriphery: periphery});
    }

    function getReport() external view returns (LiquidationPeripheryBatchReport memory) {
        return report;
    }
}
