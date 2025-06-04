// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/IAltoReport.sol";
import {AltoRelease} from "deployments/releases/tapioca-v1/AltoRelease.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";

contract AltoReleaseTest is Test {
    address owner;

    function setUp() public {
        owner = makeAddr("owner");
    }

    function test_deployAltoV1_default() public {
        AltoReport memory emptyReport;
        TapiocaInput memory input;
        input.owner = owner;
        input.isTestnet = true;
        input.lzChainId = 0;
        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXProxy = address(1);
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));
        input.bbMarketBorrowCap = 3_000_000e18;

        AltoRelease.deployAltoV1(input, emptyReport);
    }
}
