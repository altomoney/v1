// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {TapiocaMagnetarBatchOne} from "deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchOne.sol";
import {TapiocaMagnetarBatchTwo} from "deployments/releases/tapioca-v1/batches/TapiocaMagnetarBatchTwo.sol";
import {TapiocaUtilitiesBatch} from "deployments/releases/tapioca-v1/batches/TapiocaUtilitiesBatch.sol";
import {TapiocaYieldboxBatch} from "deployments/releases/tapioca-v1/batches/TapiocaYieldboxBatch.sol";
import {TapiocaUsdoBatchOne} from "deployments/releases/tapioca-v1/batches/TapiocaUsdoBatchOne.sol";
import {TapiocaUsdoBatchTwo} from "deployments/releases/tapioca-v1/batches/TapiocaUsdoBatchTwo.sol";
import {TapiocaUsdoBatchThree} from "deployments/releases/tapioca-v1/batches/TapiocaUsdoBatchThree.sol";
import {TapiocaSingularityBatch1} from "deployments/releases/tapioca-v1/batches/TapiocaSingularityBatch1.sol";
import {TapiocaSingularityBatch2} from "deployments/releases/tapioca-v1/batches/TapiocaSingularityBatch2.sol";
import {TapiocaSingularityBatch3} from "deployments/releases/tapioca-v1/batches/TapiocaSingularityBatch3.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";

contract ProcedureLimits is Test {
    address owner;
    address zeroXSwapper;
    address endpointMock;
    address delegate;
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;
    UsdoModulesReport usdoModulesReport;
    UsdoMarketModulesReport usdoMarketModulesReport;

    function setUp() public {
        owner = makeAddr("owner");
        zeroXSwapper = makeAddr("zeroXSwapper");
        endpointMock = address(new LZEndpointMock(1));
        delegate = address(new TapiocaOmnichainExtExec());

        usdoModulesReport = (
            new TapiocaUsdoBatchOne(endpointMock, delegate, address(0), address(0), address(0), address(0))
        ).getUsdoModulesReport();
        usdoMarketModulesReport = (
            new TapiocaUsdoBatchTwo(endpointMock, delegate, address(0), address(0), address(0), address(0))
        ).getUsdoMarketModulesReport();
    }

    function test_new_TapiocaMagnetarBatchOne() public {
        new TapiocaMagnetarBatchOne(address(0), address(0));
    }

    function test_new_TapiocaMagnetarBatchTwo() public {
        MagnetarDepsReport memory emptyReport;
        new TapiocaMagnetarBatchTwo(owner, address(1), address(2), address(3), address(4), address(5), emptyReport);
    }

    function test_new_UtilityBatch_isTestnet_false() public {
        new TapiocaUtilitiesBatch(owner, zeroXSwapper, address(1), 0, false);
    }

    function test_new_UtilityBatch_isTestnet_true() public {
        new TapiocaUtilitiesBatch(owner, zeroXSwapper, address(1), 0, true);
    }

    function test_new_YieldboxBatch() public {
        new TapiocaYieldboxBatch(owner, address(1), address(2));
    }

    function test_new_TapiocaUsdoBatchOne() public {
        new TapiocaUsdoBatchOne(endpointMock, delegate, address(1), address(2), address(3), address(4));
    }

    function test_new_TapiocaUsdoBatchTwo() public {
        new TapiocaUsdoBatchTwo(endpointMock, delegate, address(1), address(2), address(3), address(4));
    }

    function test_new_TapiocaUsdoBatchThree() public {
        new TapiocaUsdoBatchThree(
            endpointMock,
            delegate,
            address(1),
            address(2),
            address(3),
            address(4),
            usdoModulesReport.usdoSenderModule,
            usdoModulesReport.usdoReceiverModule,
            usdoMarketModulesReport.marketReceiverModule,
            usdoMarketModulesReport.optionReceiverModule
        );
    }

    function test_new_SingularityBatch() public {
        new TapiocaSingularityBatch1();
    }

    function test_codesizes() public pure {
        uint256 magnetarBatchOneCreationSize = type(TapiocaMagnetarBatchOne).creationCode.length;
        uint256 magnetarBatchTwoCreationSize = type(TapiocaMagnetarBatchTwo).creationCode.length;
        uint256 utilitiesBatchCreationSize = type(TapiocaUtilitiesBatch).creationCode.length;
        uint256 yieldboxBatchCreationSize = type(TapiocaYieldboxBatch).creationCode.length;
        uint256 usdoBatchCreationSize = type(TapiocaUsdoBatchOne).creationCode.length;
        uint256 usdoBatchTwoCreationSize = type(TapiocaUsdoBatchTwo).creationCode.length;
        uint256 usdoBatchThreeCreationSize = type(TapiocaUsdoBatchThree).creationCode.length;
        uint256 singularityBatch1CreationSize = type(TapiocaSingularityBatch1).creationCode.length;
        uint256 singularityBatch2CreationSize = type(TapiocaSingularityBatch2).creationCode.length;
        uint256 singularityBatch3CreationSize = type(TapiocaSingularityBatch3).creationCode.length;

        console2.log("TapiocaUtilitiesBatch", utilitiesBatchCreationSize);
        console2.log("TapiocaYieldboxBatch", yieldboxBatchCreationSize);
        console2.log("TapiocaMagnetarBatchOne", magnetarBatchOneCreationSize);
        console2.log("TapiocaMagnetarBatchTwo", magnetarBatchTwoCreationSize);
        console2.log("TapiocaUsdoBatchOne", usdoBatchCreationSize);
        console2.log("TapiocaUsdoBatchTwo", usdoBatchTwoCreationSize);
        console2.log("TapiocaUsdoBatchThree", usdoBatchThreeCreationSize);
        console2.log("TapiocaSigularityBatch1", singularityBatch1CreationSize);
        console2.log("TapiocaSigularityBatch2", singularityBatch2CreationSize);
        console2.log("TapiocaSigularityBatch3", singularityBatch3CreationSize);

        assertLe(
            magnetarBatchOneCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaMagnetarBatchOne max init code size"
        );

        assertLe(
            magnetarBatchTwoCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaMagnetarBatchTwo max init code size"
        );

        assertLe(utilitiesBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUtilitiesBatch max init code size");

        assertLe(yieldboxBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaYieldBoxBatch max init code size");

        assertLe(usdoBatchCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUsdoBatchOne max init code size");

        assertLe(usdoBatchTwoCreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TapiocaUsdoBatchTwo max init code size");

        assertLe(singularityBatch1CreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "singularityBatch1 max init code size");
        assertLe(singularityBatch2CreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "singularityBatch2 max init code size");
        assertLe(singularityBatch3CreationSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "singularityBatch3 max init code size");
    }
}
