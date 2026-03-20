// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";

contract AltoChainlinkERC4626RatioMultiplierOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    string internal rpcUrl = vm.rpcUrl("ethereum");

    function test_GetPrice_Reusd() public {
        vm.createSelectFork(rpcUrl, 24698135);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployReusdOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(price, 1067443054115740032000000000000000000, "Invalid price from the REUSD Oracle");
    }
}
