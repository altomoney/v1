// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";

contract AltoERC4626RatioChainlinkOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    string internal rpcUrl = vm.rpcUrl("ethereum");

    function test_GetPrice_Meth() public {
        vm.createSelectFork(rpcUrl, 23690069);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployMethOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(4190534376269485162203987750990000000000, price, "Invalid price from the METH Oracle");
    }

    function test_GetPrice_Reth() public {
        vm.createSelectFork(rpcUrl, 23532976);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployRethOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(5147929304649297245370612844000000000000, price, "Invalid price from the RETH Oracle");
    }

    function test_GetPrice_Susde() public {
        vm.createSelectFork(rpcUrl, 23490557);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deploySusdeOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(1201561419605420001251389840000000000, price, "Invalid price from the SUSDE Oracle");
    }

    function test_GetPrice_WstEth() public {
        vm.createSelectFork(rpcUrl, 23483134);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deployWstEthOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(5227741891879173215020051770310000000000, price, "Invalid price from the WSTETH Oracle");
    }

    function test_GetPrice_SyrupUsdc() public {
        vm.createSelectFork(rpcUrl, 24197555);

        ILendingOracle oracle = ILendingOracle(EthereumMainnetOracleDeployer.deploySyrupUsdcOracle(OWNER));
        uint256 price = oracle.getPrice();

        assertEq(price, 1145608214400000000000000000000000000000000000000, "Invalid price from the SyrupUSDC Oracle");
    }
}

