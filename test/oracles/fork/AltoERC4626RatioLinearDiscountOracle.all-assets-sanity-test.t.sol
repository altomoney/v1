// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";

contract AltoERC4626RatioLinearDiscountOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    string internal rpcUrl = vm.rpcUrl("ethereum");

    function test_GetPrice_PtReusd() public {
        vm.createSelectFork(rpcUrl, 24728045);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployPtReusdOracle(OWNER));
        uint256 price = oracle.getPrice();

        // share price is 1068153578616009984
        // block.timestamp is 1774363139
        // expiry is 1782345600
        // price is 1068153578616009984 * (1e18 - 0.08 ether * (1782345600 - 1774363139) / 365.2425 days)

        assertEq(price, 1046538070798112403939756339800990208, "Invalid price from the PT-REUSD Oracle");
    }
}
