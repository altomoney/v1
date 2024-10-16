// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";

contract TapiocaReleaseTest is Test {
    address owner;

    function setUp() public {
        owner = makeAddr("owner");
    }

    function test_deployTapiocaV1_default() public {
        TapiocaReport memory emptyReport;
        TapiocaInput memory input;
        input.owner = owner;
        input.lzChainId = 0;
        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));

        TapiocaRelease.deployTapiocaV1(input, emptyReport);
    }
}
