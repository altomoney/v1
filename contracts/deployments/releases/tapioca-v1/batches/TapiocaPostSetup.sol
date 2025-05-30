// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {UsdoReport, LendingReport} from "../../../interfaces/IAltoReport.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Usdo} from "@alto/tokens/Usdo.sol";
import {MultiTokenSender} from "@alto/deployments/contracts/testnet/MultiTokenSender.sol";
import {TapiocaMulticallTestnet} from "@alto/deployments/contracts/TapiocaMulticall/TapiocaMulticallTestnet.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";

/// @title TapiocaPostSetup
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TapiocaPostSetup is Ownable {
    address public constant BACKEND_TESTNET_ADDRESS = 0x81E1c5EbA8c723e167E1C046AAF217B8eb7b8AC2;
    uint128 public constant MULTI_TOKEN_SENDER_MINT_TOKENS = type(uint128).max;

    constructor() Ownable(msg.sender) {}

    function postSetup(
        address multicall,
        address usdo,
        address borrowMarket,
        address mintMarket,
        address multiTokenSender,
        address altoLeverage,
        address leverageSwapper
    ) external onlyOwner {
        Usdo(payable(usdo)).setMinterStatus(address(mintMarket), true);
        Usdo(payable(usdo)).setMinterStatus(address(this), true);
        Usdo(payable(usdo)).setBurnerStatus(address(mintMarket), true);

        MultiTokenSender(multiTokenSender).updateWhitelist(BACKEND_TESTNET_ADDRESS, true);

        // Add extra admins to the multicall contract
        TapiocaMulticallTestnet(payable(multicall)).setOwner(0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367, true);
        TapiocaMulticallTestnet(payable(multicall)).setOwner(0x4778c2AA94a8D05D63e4C07eb68021528985304C, true);

        Usdo(payable(usdo)).mint(multiTokenSender, MULTI_TOKEN_SENDER_MINT_TOKENS);
        Usdo(payable(usdo)).mint(leverageSwapper, MULTI_TOKEN_SENDER_MINT_TOKENS);
        AltoLeverage(payable(altoLeverage)).setMarket(address(borrowMarket), true);
        AltoLeverage(payable(altoLeverage)).setMarket(address(mintMarket), true);
        IMarket(borrowMarket).setAuthorizedCallback(address(altoLeverage), true);
        IMarket(mintMarket).setAuthorizedCallback(address(altoLeverage), true);

        Usdo(payable(usdo)).setMinterStatus(address(this), false);
        // Transfer ownership to the delegate
        Usdo(payable(usdo)).setDelegate(multicall);
        Usdo(payable(usdo)).transferOwnership(multicall);
        MultiTokenSender(multiTokenSender).transferOwnership(multicall);
        MultiTokenSender(borrowMarket).transferOwnership(multicall);
        MultiTokenSender(mintMarket).transferOwnership(multicall);
        AltoLeverage(payable(altoLeverage)).transferOwnership(multicall);
    }
}
