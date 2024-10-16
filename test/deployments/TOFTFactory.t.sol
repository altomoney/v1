// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "deployments/interfaces/ITapiocaReport.sol";
import {TapiocaRelease} from "deployments/releases/tapioca-v1/TapiocaRelease.sol";
import {LZEndpointMock} from "tapioca-mocks/LZEndpointMock.sol";
import {ERC20Mock} from "../bar/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TOFTFactory} from "deployments/releases/tapioca-v1/actions/TOFTFactory.sol";
import "tapiocaz/tOFT/TOFT.sol";
import "tapiocaz/tOFT/TOFTVault.sol";

contract TOFTFactoryTest is Test {
    uint256 constant MAX_INIT_CONSTRUCTOR_CODE_SIZE = 49152;

    address owner;

    TapiocaInput input;
    TapiocaReport report;

    TOFTFactory toftFactory;

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
        usda = new ERC20Mock("USDA", "USDA");
        report = TapiocaRelease.deployTapiocaV1(input, emptyReport);

        toftFactory = new TOFTFactory(
            TOFTFactory.TOFTConstructorParams(
                report.cluster,
                input.lzEndpoint,
                input.lzChainId,
                report.extExec,
                report.pearlmit,
                report.yieldbox,
                report.tOFTSenderModule,
                report.tOFTReceiverModule,
                report.tOFTMarketReceiverModule,
                report.tOFTOptionsReceiverModule,
                report.tOFTGenericReceiverModule,
                owner,
                owner
            )
        );
    }

    function test_deployTOFT() public {
        (TOFTVault vault, TOFT toft) = toftFactory.deployTOFT(address(usda), "Tapioca USDA Wrapped Token", "tUSDA");
        assertEq(vault._token(), address(usda), "TOFTVault erc20");
        assertEq(address(toft.erc20()), address(usda), "TOFT underlying erc20");
    }

    function test_codeSize() public {
        uint256 toftFactoryCodeSize = type(TOFTFactory).creationCode.length;

        console2.log("TOFTFactory code size", toftFactoryCodeSize);
        assertLe(toftFactoryCodeSize, MAX_INIT_CONSTRUCTOR_CODE_SIZE, "TOFTFactory max init code size");
    }
}
