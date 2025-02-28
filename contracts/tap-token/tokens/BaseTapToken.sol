// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {BaseTapiocaOmnichainEngine} from "tap-utils/tapiocaOmnichainEngine/BaseTapiocaOmnichainEngine.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {BaseTapTokenMsgType} from "./BaseTapTokenMsgType.sol";
import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

abstract contract BaseTapToken is BaseTapiocaOmnichainEngine, BaseTapTokenMsgType {
    uint16 internal constant PT_LOCK_TWTAP = 870;
    uint16 internal constant PT_UNLOCK_TWTAP = 871;
    uint16 internal constant PT_CLAIM_REWARDS = 872;

    ITWTAPv2 public twTap;

    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint,
        address _delegate,
        address _extExec,
        ICluster _cluster
    ) BaseTapiocaOmnichainEngine(_name, _symbol, _endpoint, _delegate, _extExec, _cluster) {}

    error twTapNotSet();

    modifier twTapExists() {
        if (address(twTap) == address(0)) revert twTapNotSet();
        _;
    }

    /**
     * @notice set the twTAP address, can be done only once.
     */
    function setTwTAP(address _twTap) external virtual {}
}
