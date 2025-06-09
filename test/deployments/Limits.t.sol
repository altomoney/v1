// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "deployments/interfaces/IAltoReport.sol";
import {AltoUsdoBatch} from "deployments/releases/alto-v1/batches/AltoUsdoBatch.sol";
import {AltoUtilitiesBatch} from "deployments/releases/alto-v1/batches/AltoUtilitiesBatch.sol";
import {AltoPostSetup} from "deployments/releases/alto-v1/batches/AltoPostSetup.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
//import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract LimitsTest is Test {
    address owner;
    address leverageSwapper;
    address endpointMock;
    address delegate;
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;

    address erc20Mock1;
    address erc20Mock2;
    address erc20Mock3;

    function setUp() public {
        //super.setUp();
        //setUpEndpoints(1, LibraryType.UltraLightNode);

        owner = makeAddr("owner");
        leverageSwapper = makeAddr("leverageSwapper");
        //endpointMock = address(endpoints[1]);
        delegate = owner;

        erc20Mock1 = address(new ERC20Mock("A", "A"));
        erc20Mock2 = address(new ERC20Mock("B", "B"));
        erc20Mock3 = address(new ERC20Mock("C", "C"));
    }

    function test_codesizes() public pure {
        uint256 utilitiesBatchCreationSize = type(AltoUtilitiesBatch).creationCode.length;
        uint256 usdoBatchCreationSize = type(AltoUsdoBatch).creationCode.length;
        uint256 postSetupBatchCreationSize = type(AltoPostSetup).creationCode.length;
        console2.log("AltoUtilitiesBatch", utilitiesBatchCreationSize);
        console2.log("AltoUsdoBatch", usdoBatchCreationSize);
        console2.log("AltoPostSetup", postSetupBatchCreationSize);
        assertLe(utilitiesBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "AltoUtilitiesBatch max init code size");
        assertLe(usdoBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "AltoUsdoBatch max init code size");
        assertLe(postSetupBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "AltoPostSetup max init code size");
    }
}
