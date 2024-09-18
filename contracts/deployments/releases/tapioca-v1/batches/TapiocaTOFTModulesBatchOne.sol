pragma solidity ^0.8.22;

import {TOFTModulesReport} from "../../../interfaces/ITapiocaReport.sol";
import {TapiocaZProcedures} from "../../../procedures/TapiocaZProcedures.sol";

/// @title TapiocaTOFTModulesBatchOne
/// @notice Deploy TOFT modules contracts, first part
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaTOFTModulesBatchOne is TapiocaZProcedures {
    TOFTModulesReport internal _toftReport;

    constructor(address endpoint, uint256 hostEid, address delegate) {
        _toftReport = _deployTOFTModulesOne(endpoint, hostEid, delegate);
    }

    function getTOFTModulesFirstReport() external view returns (TOFTModulesReport memory) {
        return _toftReport;
    }
}
