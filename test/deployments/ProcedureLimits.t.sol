// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {TapiocaMagnetarBatchOne} from "deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchTwo.sol";
import {TapiocaUtilitiesBatch} from "deployments/releases/tapioca-v1/batches/TapiocaUtilitiesBatch.sol";
import {TapiocaYieldboxBatch} from "deployments/releases/tapioca-v1/batches/TapiocaYieldboxBatch.sol";
import "deployments/interfaces/ITapiocaReport.sol";

contract ProcedureLimits is Test {
    address owner;
    address zeroXSwapper;
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;

    function setUp() public {
        owner = makeAddr("owner");
        zeroXSwapper = makeAddr("zeroXSwapper");
    }

    function test_new_TapiocaMagnetarBatchOne() public {
        new TapiocaMagnetarBatchOne(address(0), address(0));
    }

    function test_new_TapiocaMagnetarBatchTwo() public {
        MagnetarDepsReport memory emptyReport;
        new TapiocaMagnetarBatchTwo(owner, address(0), address(0), address(0), emptyReport);
    }

    function test_new_UtilityBatch_isTestnet_false() public {
        new TapiocaUtilitiesBatch(owner, zeroXSwapper, 0, false);
    }

    function test_new_UtilityBatch_isTestnet_true() public {
        new TapiocaUtilitiesBatch(owner, zeroXSwapper, 0, true);
    }

    function test_new_YieldboxBatch() public {
        new TapiocaYieldboxBatch(owner, address(0), address(0));
    }

    function test_codesizes() public {
        uint256 magnetarBatchOneCreationSize = type(TapiocaMagnetarBatchOne).creationCode.length;
        uint256 magnetarBatchTwoCreationSize = type(TapiocaMagnetarBatchTwo).creationCode.length;
        uint256 utilitiesBatchCreationSize = type(TapiocaUtilitiesBatch).creationCode.length;
        uint256 yieldboxBatchCreationSize = type(TapiocaYieldboxBatch).creationCode.length;

        uint256 totalCreationSize = magnetarBatchOneCreationSize + magnetarBatchTwoCreationSize
            + utilitiesBatchCreationSize + yieldboxBatchCreationSize;

        console2.log("TapiocaUtilitiesBatch", utilitiesBatchCreationSize);
        console2.log("TapiocaYieldboxBatch", yieldboxBatchCreationSize);
        console2.log("TapiocaMagnetarBatchOne", magnetarBatchOneCreationSize);
        console2.log("TapiocaMagnetarBatchTwo", magnetarBatchTwoCreationSize);

        // Max code size for constuctor pattern is 2x code size (48kb) multiplied by number of constructor batches (4) used to deploy Tapioca contracts
        assertLe(
            totalCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE * 4, "Total creation code size exceeds number of batches"
        );
        console2.log("Total / Used / Available init code size");
        console2.log(
            (MAX_INIT_CONSTRUCTOR_CODE_SIZE * 4),
            totalCreationSize,
            (MAX_INIT_CONSTRUCTOR_CODE_SIZE * 4) - totalCreationSize
        );

        assertLe(
            magnetarBatchOneCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaMagnetarBatchOne max init code size"
        );

        assertLe(
            magnetarBatchTwoCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaMagnetarBatchTwo max init code size"
        );

        assertLe(utilitiesBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUtilitiesBatch max init code size");

        assertLe(yieldboxBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaYieldBoxBatch max init code size");
    }
}
