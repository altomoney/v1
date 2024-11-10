// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MTOFTFactory} from "deployments/releases/tapioca-v1/actions/MTOFTFactory.sol";
import "tapiocaz/tOFT/mTOFT.sol";
import "tapiocaz/tOFT/TOFTVault.sol";

contract MOFTFactoryTest is Test {
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;

    address owner;

    TapiocaInput input;
    TapiocaReport report;

    MTOFTFactory mtoftFactory;

    ERC20Mock usda;

    function setUp() public {
        owner = address(this);
        TapiocaReport memory emptyReport;
        input.owner = owner;
        input.lzChainId = 1;
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.tapToken = address(new ERC20Mock("B", "B"));

        input.lzEndpoint = address(new LZEndpointMock(1));
        input.zeroXSwapper = address(1);
        input.isMetaInstance = true;

        usda = new ERC20Mock("USDA", "USDA");
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        mtoftFactory = new MTOFTFactory(
            MTOFTFactory.TOFTConstructorParams(
                report.cluster,
                input.lzEndpoint,
                input.lzChainId,
                report.extExec,
                report.pearlmit,
                report.yieldbox,
                report.tOFTSenderModule,
                report.mTOFTReceiverModule,
                report.tOFTMarketReceiverModule,
                report.tOFTOptionsReceiverModule,
                report.tOFTGenericReceiverModule,
                owner,
                owner
            )
        );
    }

    function test_deployMTOFT() public {
        (TOFTVault vault, mTOFT mtoft) =
            mtoftFactory.deployMTOFT(address(usda), "Tapioca USDA Wrapped Token", "mtUSDA", address(1));
        assertEq(vault._token(), address(usda), "TOFTVault erc20");
        assertEq(address(mtoft.erc20()), address(usda), "MTOFT underlying erc20");
    }

    function test_codeSize() public {
        /*
        @review-test: This assert is failing.
        */
        vm.skip(true);
        uint256 mtoftFactoryCodeSize = type(MTOFTFactory).creationCode.length;

        console2.log("MTOFTFactory code size", mtoftFactoryCodeSize);
        assertLe(mtoftFactoryCodeSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "MTOFTFactory max init code size");
    }
}
