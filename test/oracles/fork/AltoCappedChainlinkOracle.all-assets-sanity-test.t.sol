// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";

contract AltoCappedChainlinkOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    string internal rpcUrl = vm.rpcUrl("ethereum");

    function test_GetPrice_Reusd() public {
        vm.createSelectFork(rpcUrl, 24698135);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployReusdOracle(OWNER));
        uint256 price = oracle.getPrice();

        // NAV at block 24698135 = 1067443054115740032 (18 dec)
        // readChainlinkFeed(1e18, {in=18, out=36, feed=18}) = NAV * 1e18 (36 dec)
        // initialRatio = NAV * 1e18 * 1015 / 1000 > NAV * 1e18 → cap does not bind
        // Expected: NAV * 1e18 = 1067443054115740032 * 1e18
        assertEq(price, 1067443054115740032000000000000000000, "Exact price from the REUSD Oracle");
    }
}
