// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {TOFTModulesReport} from "../interfaces/ITapiocaReport.sol";
import {TOFTVault} from "tapiocaz/tOFT/TOFTVault.sol";
import {TOFTSender} from "tapiocaz/tOFT/modules/TOFTSender.sol";
import {TOFTReceiver} from "tapiocaz/tOFT/modules/TOFTReceiver.sol";
import {TOFTMarketReceiverModule} from "tapiocaz/tOFT/modules/TOFTMarketReceiverModule.sol";
import {TOFTOptionsReceiverModule} from "tapiocaz/tOFT/modules/TOFTOptionsReceiverModule.sol";
import {TOFTGenericReceiverModule} from "tapiocaz/tOFT/modules/TOFTGenericReceiverModule.sol";
import {TOFTHelper} from "tapiocaz/tOFT/extensions/TOFTHelper.sol";
import {ERC20Mock} from "yieldbox/mocks/ERC20Mock.sol";
import "tap-utils/interfaces/oft/ITOFT.sol";

/// @dev TOFTInitStruct contains dummy params due the contracts implementations/modules are called via delegatecall, only needed production values for endpoint, hostEid, and delegate
abstract contract TapiocaZProcedures {
    function _deployTOFTModulesOne(address endpoint, uint256 hostEid, address delegate)
        internal
        returns (TOFTModulesReport memory report)
    {
        address dummyErc20 = address(new ERC20Mock(0));

        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: endpoint,
            delegate: delegate,
            yieldBox: address(1),
            cluster: address(1),
            erc20: dummyErc20,
            vault: address(new TOFTVault(dummyErc20)),
            hostEid: hostEid,
            extExec: address(1),
            pearlmit: IPearlmit(address(1))
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
            yieldBox: address(1),
            cluster: address(1),
            erc20: TOFTSender(report.tOFTSenderModule).erc20(),
            vault: address(TOFTSender(report.tOFTSenderModule).vault()),
            hostEid: TOFTSender(report.tOFTSenderModule).hostEid(),
            extExec: address(1),
            pearlmit: IPearlmit(address(1))
        });

        report.tOFTMarketReceiverModule = address(new TOFTMarketReceiverModule(toftModulesInitStruct));
        report.tOFTReceiverModule = address(new TOFTReceiver(toftModulesInitStruct));

        return report;
    }

    function _deployTOFTModulesThree(TOFTModulesReport memory report) internal returns (TOFTModulesReport memory) {
        TOFTInitStruct memory toftModulesInitStruct = TOFTInitStruct({
            name: "TOFT_MODULE",
            symbol: "TOFT_MODULE",
            endpoint: address(TOFTSender(report.tOFTSenderModule).endpoint()),
            delegate: TOFTSender(report.tOFTSenderModule).owner(),
            yieldBox: address(1),
            cluster: address(1),
            erc20: TOFTSender(report.tOFTSenderModule).erc20(),
            vault: address(TOFTSender(report.tOFTSenderModule).vault()),
            hostEid: TOFTSender(report.tOFTSenderModule).hostEid(),
            extExec: address(1),
            pearlmit: IPearlmit(address(1))
        });

        report.tOFTGenericReceiverModule = address(new TOFTGenericReceiverModule(toftModulesInitStruct));
        report.tOFTOptionsReceiverModule = address(new TOFTOptionsReceiverModule(toftModulesInitStruct));

        return report;
    }
}
