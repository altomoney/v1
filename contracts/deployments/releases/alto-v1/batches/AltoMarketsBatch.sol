// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {LendingProcedure} from "../../../procedures/LendingProcedure.sol";
import {LendingReport} from "../../../interfaces/IAltoReport.sol";

/// @title AltoMarketsBatch
/// @notice Deploy Alto markets
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract AltoMarketsBatch is LendingProcedure {
    LendingReport internal _lendingReport;

    constructor(
        address usdo,
        address delegate,
        address collateralTokenBorrowMarket,
        address collateralTokenMintMarket,
        address borrowIrm,
        address borrowOracle,
        address mintIrm,
        address mintOracle
    ) {
        _lendingReport = _deployLending(
            delegate,
            collateralTokenBorrowMarket,
            collateralTokenMintMarket,
            usdo,
            borrowIrm,
            borrowOracle,
            mintIrm,
            mintOracle
        );
    }

    function getLendingReport() external view returns (LendingReport memory) {
        return _lendingReport;
    }
}
