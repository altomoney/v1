// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {AltoInput, AltoReport} from "deployments/interfaces/IAltoReport.sol";
import {AltoRelease} from "deployments/releases/alto-v1/AltoRelease.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";

import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract AltoReleaseTest is Test, TestHelperOz5 {
    address owner;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);
        owner = makeAddr("owner");
    }

    function test_deployAltoV1_default() public {
        AltoReport memory emptyReport;
        AltoInput memory input;
        input.owner = owner;
        input.isTestnet = true;
        input.lzChainId = 0;
        input.lzEndpoint = address(endpoints[1]);
        input.wrappedNativeToken = address(new ERC20Mock("A", "A"));
        input.altoToken = address(new ERC20Mock("B", "B"));
        input.bbMarketBorrowCap = 3_000_000e18;

        input.collateralTokenBorrowMarket = address(new ERC20Mock("C", "C"));
        input.collateralTokenMintMarket = address(new ERC20Mock("D", "D"));

        input.borrowOracle = address(new OracleMock());
        input.mintOracle = address(new OracleMock());

        OracleMock(input.borrowOracle).setPrice(1 * ORACLE_PRICE_PRECISION);
        OracleMock(input.mintOracle).setPrice(1800 * ORACLE_PRICE_PRECISION);

        AltoRelease.deployAltoV1(input, emptyReport);
    }
}
