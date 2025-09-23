// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";

contract BurnDUSD is Script {
    function run() public {
        vm.startBroadcast();

        address owner = msg.sender;
        address dusd = 0xab8c06599C80e581dfD0d85a7dBF38820A6A3F5F;

        DUSD(dusd).setBurnerStatus(owner, true);
        DUSD(dusd).burn(owner, type(uint128).max);
        DUSD(dusd).setBurnerStatus(owner, false);

        vm.stopBroadcast();
    }
}

contract SetWethOracle is Script {
    function run() public {
        vm.startBroadcast();

        address oracle = 0xe85B26e9A8D65d0f6d9cF26BC280dDF5a44F34b0;

        OracleTestnet(oracle).setPrice(4000 * ORACLE_PRICE_PRECISION);

        vm.stopBroadcast();
    }
}

contract SetMulticallOwner is Script {
    function run() public {
        vm.startBroadcast();

        address multicall = 0xA522acEfC269B871E25831E9fCa388266Ed8e449;

        AltoMulticallTestnet(payable(multicall)).setOwner(0xd7F6Fa30BC8c0E5003689C332bd2b9400Ed87367, true);

        vm.stopBroadcast();
    }
}
