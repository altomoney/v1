// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
// import TapiocaReport
import "deployments/interfaces/ITapiocaReport.sol";
// import TapiocaRelease
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";

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
        input.wrappedNativeToken = address(0);

        TapiocaRelease.deployTapiocaV1(input, emptyReport);
    }
}
