// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {USDO} from "@alto/tokens/USDO.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract BurnUSDO is Script {
    function run() public {
        vm.startBroadcast();

        address owner = msg.sender;
        address usdo = 0xab8c06599C80e581dfD0d85a7dBF38820A6A3F5F;

        USDO(usdo).setBurnerStatus(owner, true);
        USDO(usdo).burn(owner, type(uint128).max);
        USDO(usdo).setBurnerStatus(owner, false);

        vm.stopBroadcast();
    }
}

contract SetWethOracle is Script {
    function run() public {
        vm.startBroadcast();

        address oracle = 0xe85B26e9A8D65d0f6d9cF26BC280dDF5a44F34b0;

        OracleMock(oracle).setPrice(4000 * ORACLE_PRICE_PRECISION);

        vm.stopBroadcast();
    }
}
