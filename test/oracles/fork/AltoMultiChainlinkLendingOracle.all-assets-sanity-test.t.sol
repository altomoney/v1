// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoMultiChainlinkLendingOracle} from "@alto/oracles/AltoMultiChainlinkLendingOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";

contract AltoMultiChainlinkLendingOracleGetPriceForkTest is Test {
    address internal OWNER = makeAddr("Alto-multisig");

    function test_GetPrice_CbBtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689559);

        AltoMultiChainlinkLendingOracle oracle =
            AltoMultiChainlinkLendingOracle(EthereumMainnetOracleDeployer.deployCbbtcOracle(OWNER));

        (AggregatorV3Interface feed,,,, uint8 outDecimals,) = oracle.chainlinkNodes(0);

        (, int256 chainlinkAnswer,,,) = feed.latestRoundData();
        uint256 chainlinkDecimals = feed.decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            uint256(chainlinkAnswer) * (10 ** (outDecimals - chainlinkDecimals)),
            "Incorrect price returned for CbBTC"
        );
    }

    function test_GetPrice_Tbtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23489205);

        AltoMultiChainlinkLendingOracle oracle =
            AltoMultiChainlinkLendingOracle(EthereumMainnetOracleDeployer.deployTbtcOracle(OWNER));

        (AggregatorV3Interface feed,,,, uint8 outDecimals,) = oracle.chainlinkNodes(0);

        (, int256 chainlinkAnswer,,,) = feed.latestRoundData();
        uint256 chainlinkDecimals = feed.decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            uint256(chainlinkAnswer) * (10 ** (outDecimals - chainlinkDecimals)),
            "Incorrect price returned for TBTC"
        );
    }

    function test_GetPrice_WBtc() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23689416);

        AltoMultiChainlinkLendingOracle oracle =
            AltoMultiChainlinkLendingOracle(EthereumMainnetOracleDeployer.deployWbtcOracle(OWNER));

        (AggregatorV3Interface feed,,, uint8 inDecimals, uint8 outDecimals,) = oracle.chainlinkNodes(1);

        (, int256 chainlinkAnswer,,,) = feed.latestRoundData();

        uint256 price = oracle.getPrice();
        assertApproxEqRel(
            price,
            uint256(chainlinkAnswer) * (10 ** (outDecimals - inDecimals)),
            1e15,
            "Incorrect price returned for WBTC"
        );
    }

    function test_GetPrice_Weth() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 23474424);

        AltoMultiChainlinkLendingOracle oracle =
            AltoMultiChainlinkLendingOracle(EthereumMainnetOracleDeployer.deployWethOracle(OWNER));

        (AggregatorV3Interface feed,,,, uint8 outDecimals,) = oracle.chainlinkNodes(0);

        (, int256 chainlinkAnswer,,,) = feed.latestRoundData();
        uint256 chainlinkDecimals = feed.decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            uint256(chainlinkAnswer) * (10 ** (outDecimals - chainlinkDecimals)),
            "Incorrect price returned for WETH"
        );
    }

    function test_GetPrice_Paxg() public {
        // Fork and setup
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl, 24197555);

        AltoMultiChainlinkLendingOracle oracle =
            AltoMultiChainlinkLendingOracle(EthereumMainnetOracleDeployer.deployPaxgOracle(OWNER));

        (AggregatorV3Interface feed,,,, uint8 outDecimals,) = oracle.chainlinkNodes(0);

        (, int256 chainlinkAnswer,,,) = feed.latestRoundData();
        uint256 chainlinkDecimals = feed.decimals();

        uint256 price = oracle.getPrice();
        assertEq(
            price,
            uint256(chainlinkAnswer) * (10 ** (outDecimals - chainlinkDecimals)),
            "Incorrect price returned for PAXG"
        );
    }
}

