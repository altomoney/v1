// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {ITap} from "src/tap-utils/interfaces/oft/ITap.sol";

import {ERC721Mock} from "./ERC721Mock.sol";

contract TapiocaOptionsBrokerMock {
    address public tapOFT;
    address public oTAP;
    address public tOLP;

    error TransferFailed();

    constructor(address _otap, address _tapOft) {
        tapOFT = _tapOft;
        oTAP = _otap;
    }

    function setTOLP(address _a) external {
        tOLP = _a;
    }

    function getOTCDealDetails(uint256, address, uint256)
        external
        view
        returns (uint256 eligibleTapAmount, uint256 paymentTokenAmount, uint256 tapAmount)
    {
        return (1 ether, 1 ether, 1 ether);
    }

    function exerciseOption(uint256 _bucketId, address _paymentToken, uint256 _tapAmount) external {
        ITap(tapOFT).extractTAP(msg.sender, 1 ether);
    }

    function participate(uint256 _tOLPTokenID) external returns (uint256 oTAPTokenID) {
        ERC721Mock(oTAP).mint(msg.sender, 1);
        return 1;
    }
}
