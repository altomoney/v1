// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IMagnetarModuleExtender} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {TapiocaOmnichainEngineHelper} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {MagnetarModule} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {RevertMsgDecoder} from "tap-utils/libraries/RevertMsgDecoder.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title MagnetarStorage
 * @author TapiocaDAO
 * @notice Storage contract for Magnetar & modules
 */
abstract contract MagnetarStorage {
    ICluster internal cluster;
    IMagnetarHelper public helper;
    TapiocaOmnichainEngineHelper public toeHelper;

    mapping(MagnetarModule moduleId => address moduleAddress) internal modules;

    IMagnetarModuleExtender public magnetarModuleExtender; // For future implementations

    error Magnetar_NotAuthorized(address caller, address expectedCaller); // msg.send is neither the owner nor whitelisted by Cluster
    error Magnetar_ModuleNotFound(MagnetarModule module); // Module not found
    error Magnetar_UnknownReason(); // Revert reason not recognized
    error Magnetar_TargetNotWhitelisted(address addy); // cluster.isWhitelisted(lzChainId, _addr) => false

    constructor(address _toeHelper, address _magnetarHelper) {
        toeHelper = TapiocaOmnichainEngineHelper(_toeHelper);
        helper = IMagnetarHelper(_magnetarHelper);
    }

    receive() external payable virtual {}

    function _executeModule(MagnetarModule _module, bytes memory _data) internal returns (bytes memory returnData) {
        bool success = true;
        address module = modules[_module];
        if (module == address(0)) revert Magnetar_ModuleNotFound(_module);

        (success, returnData) = module.delegatecall(_data);
        if (!success) {
            revert(RevertMsgDecoder._getRevertMsg(returnData));
        }
    }

    /**
     * @dev Check if the sender is authorized to call the contract.
     * sender is authorized if:
     *      - is the owner
     *      - is whitelisted by the cluster
     */
    function _checkSender(address _from) internal view {
        if (_from != msg.sender && !cluster.isWhitelisted(0, msg.sender)) {
            revert Magnetar_NotAuthorized(msg.sender, _from);
        }
    }

    function _checkWhitelisted(address addy) internal view {
        if (addy != address(0)) {
            if (!cluster.isWhitelisted(0, addy)) {
                revert Magnetar_TargetNotWhitelisted(addy);
            }
        }
    }
}
