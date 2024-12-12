// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {BarProcedure} from "../../../procedures/BarProcedure.sol";
import {UsdoReport} from "../../../interfaces/ITapiocaReport.sol";

/// @title TapiocaUsdoBatchOne
/// @notice Deploy USDO contracts and modules
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaUsdoBatchThree is BarProcedure {
    UsdoReport internal _usdoReport;

    constructor(
        address endpoint,
        address delegate,
        address cluster,
        address extExec,
        address usdoSenderModule,
        address usdoReceiverModule,
        address usdoMarketReceiverModule,
        address usdoOptionReceiverModule
    ) {
        _usdoReport = _deployUsdo(
            endpoint,
            delegate,
            cluster,
            extExec,
            usdoSenderModule,
            usdoReceiverModule,
            usdoMarketReceiverModule,
            usdoOptionReceiverModule
        );
    }

    function getUsdoReport() external view returns (UsdoReport memory) {
        return _usdoReport;
    }
}
