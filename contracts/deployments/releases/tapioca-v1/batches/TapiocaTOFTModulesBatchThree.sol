pragma solidity ^0.8.22;

import {TOFTModulesReport} from "../../../interfaces/ITapiocaReport.sol";
import {TapiocaZProcedures} from "../../../procedures/TapiocaZProcedures.sol";

/// @title TapiocaTOFTModulesBatchTwo
/// @notice Deploy TOFT modules contracts, third part
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts

contract TapiocaTOFTModulesBatchThree is TapiocaZProcedures {
    TOFTModulesReport internal _toftReport;

    constructor(TOFTModulesReport memory secondReport) {
        _toftReport = _deployTOFTModulesThree(secondReport);
    }

    function getTOFTModulesFinalReport() external view returns (TOFTModulesReport memory) {
        return _toftReport;
    }
}
