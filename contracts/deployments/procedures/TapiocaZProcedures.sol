// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TOFTModulesReport} from "../interfaces/ITapiocaReport.sol";
import {TOFTVault} from "tapiocaz/tOFT/TOFTVault.sol";
import {TOFTSender} from "tapiocaz/tOFT/modules/TOFTSender.sol";
import {TOFTReceiver} from "tapiocaz/tOFT/modules/TOFTReceiver.sol";
import {mTOFTReceiver} from "tapiocaz/tOFT/modules/mTOFTReceiver.sol";
import {TOFTMarketReceiverModule} from "tapiocaz/tOFT/modules/TOFTMarketReceiverModule.sol";
import {TOFTOptionsReceiverModule} from "tapiocaz/tOFT/modules/TOFTOptionsReceiverModule.sol";
import {TOFTGenericReceiverModule} from "tapiocaz/tOFT/modules/TOFTGenericReceiverModule.sol";
import {TOFTHelper} from "tapiocaz/tOFT/extensions/TOFTHelper.sol";
import "tap-utils/interfaces/oft/ITOFT.sol";

/// @dev TOFTInitStruct contains dummy params due the contracts implementations/modules are called via delegatecall, only needed production values for endpoint, hostEid, and delegate
abstract contract TapiocaZProcedures {
    function _deployTOFTModulesOne(address endpoint, uint256 hostEid, address delegate)
        internal
        returns (TOFTModulesReport memory report)
    {
        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: endpoint,
            delegate: delegate,
            
            cluster: address(1),
            erc20: address(1),
            vault: address(new TOFTVault(address(1))),
            hostEid: hostEid,
            extExec: address(1)
                    });

        report.tOFTSenderModule = address(new TOFTSender(toftModulesInitStruct));
        report.toftHelper = address(new TOFTHelper());

        return report;
    }

    function _deployTOFTModulesTwo(TOFTModulesReport memory report) internal returns (TOFTModulesReport memory) {
        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: address(TOFTSender(report.tOFTSenderModule).endpoint()),
            delegate: TOFTSender(report.tOFTSenderModule).owner(),
            
            cluster: address(1),
            erc20: TOFTSender(report.tOFTSenderModule).erc20(),
            vault: address(TOFTSender(report.tOFTSenderModule).vault()),
            hostEid: TOFTSender(report.tOFTSenderModule).hostEid(),
            extExec: address(1)
            
        });

        report.tOFTReceiverModule = address(new TOFTReceiver(toftModulesInitStruct));
        report.tOFTMarketReceiverModule = address(new TOFTMarketReceiverModule(toftModulesInitStruct));

        return report;
    }

    function _deployTOFTMetaModulesTwo(TOFTModulesReport memory report) internal returns (TOFTModulesReport memory) {
        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: address(TOFTSender(report.tOFTSenderModule).endpoint()),
            delegate: TOFTSender(report.tOFTSenderModule).owner(),
            
            cluster: address(1),
            erc20: TOFTSender(report.tOFTSenderModule).erc20(),
            vault: address(TOFTSender(report.tOFTSenderModule).vault()),
            hostEid: TOFTSender(report.tOFTSenderModule).hostEid(),
            extExec: address(1)
            
        });

        report.mTOFTReceiverModule = address(new mTOFTReceiver(toftModulesInitStruct));
        report.tOFTMarketReceiverModule = address(new TOFTMarketReceiverModule(toftModulesInitStruct));

        return report;
    }

    function _deployTOFTModulesThree(TOFTModulesReport memory report) internal returns (TOFTModulesReport memory) {
        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: address(TOFTSender(report.tOFTSenderModule).endpoint()),
            delegate: TOFTSender(report.tOFTSenderModule).owner(),
            
            cluster: address(1),
            erc20: TOFTSender(report.tOFTSenderModule).erc20(),
            vault: address(TOFTSender(report.tOFTSenderModule).vault()),
            hostEid: TOFTSender(report.tOFTSenderModule).hostEid(),
            extExec: address(1)
            
        });

        report.tOFTGenericReceiverModule = address(new TOFTGenericReceiverModule(toftModulesInitStruct));
        report.tOFTOptionsReceiverModule = address(new TOFTOptionsReceiverModule(toftModulesInitStruct));

        return report;
    }
}
