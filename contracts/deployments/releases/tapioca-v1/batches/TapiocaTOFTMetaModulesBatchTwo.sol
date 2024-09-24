pragma solidity ^0.8.22;

import {TOFTModulesReport} from "../../../interfaces/ITapiocaReport.sol";
import {TapiocaZProcedures} from "../../../procedures/TapiocaZProcedures.sol";

/// @title TapiocaMTOFTModulesBatchTwo
/// @notice Deploy mTOFT modules contracts, second part
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts

contract TapiocaTOFTMetaModulesBatchTwo is TapiocaZProcedures {
    TOFTModulesReport internal _toftReport;

    constructor(TOFTModulesReport memory firstReport) {
        _toftReport = _deployTOFTMetaModulesTwo(firstReport);
    }

    function getTOFTModulesSecondReport() external view returns (TOFTModulesReport memory) {
        return _toftReport;
    }
}
