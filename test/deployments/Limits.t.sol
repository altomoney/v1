// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "deployments/interfaces/IAltoReport.sol";
import {TapiocaUsdoBatch} from "deployments/releases/tapioca-v1/batches/TapiocaUsdoBatch.sol";
import {TapiocaUtilitiesBatch} from "deployments/releases/tapioca-v1/batches/TapiocaUtilitiesBatch.sol";
import {TapiocaPostSetup} from "deployments/releases/tapioca-v1/batches/TapiocaPostSetup.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract LimitsTest is Test, TestHelperOz5 {
    address owner;
    address zeroXSwapper;
    address endpointMock;
    address delegate;
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;

    address erc20Mock1;
    address erc20Mock2;
    address erc20Mock3;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        owner = makeAddr("owner");
        zeroXSwapper = makeAddr("zeroXSwapper");
        endpointMock = address(endpoints[1]);
        delegate = owner;

        erc20Mock1 = address(new ERC20Mock("A", "A"));
        erc20Mock2 = address(new ERC20Mock("B", "B"));
        erc20Mock3 = address(new ERC20Mock("C", "C"));
    }

    function test_codesizes() public pure {
        uint256 utilitiesBatchCreationSize = type(TapiocaUtilitiesBatch).creationCode.length;
        uint256 usdoBatchCreationSize = type(TapiocaUsdoBatch).creationCode.length;
        uint256 postSetupBatchCreationSize = type(TapiocaPostSetup).creationCode.length;
        console2.log("TapiocaUtilitiesBatch", utilitiesBatchCreationSize);
        console2.log("TapiocaUsdoBatch", usdoBatchCreationSize);
        console2.log("TapiocaPostSetup", postSetupBatchCreationSize);
        assertLe(utilitiesBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUtilitiesBatch max init code size");
        assertLe(usdoBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUsdoBatch max init code size");
        assertLe(postSetupBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaPostSetup max init code size");
    }
}
