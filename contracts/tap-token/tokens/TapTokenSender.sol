// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// LZ
import {
    MessagingReceipt, OFTReceipt, SendParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
// Tapioca
import {TapiocaOmnichainSender} from "tap-utils/tapiocaOmnichainEngine/TapiocaOmnichainSender.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {BaseTapToken} from "./BaseTapToken.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract TapTokenSender is BaseTapToken, TapiocaOmnichainSender {
    /**
     * @dev Used as a module for `TapToken`. Only delegate calls with `TapToken` state are used.
     * Set the Cluster to address(0) because it is not used in this contract. TODO ?
     */
    constructor(string memory _name, string memory _symbol, address _endpoint, address _delegate, address _extExec)
        BaseTapToken(_name, _symbol, _endpoint, _delegate, _extExec, ICluster(address(0)))
    {}
}
