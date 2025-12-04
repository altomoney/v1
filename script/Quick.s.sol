// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";

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

        address multicall = 0x132ad32a41a49883eAF7697b8F77be76b2599720;
        address oracle = 0xDDA135163cD9aA0D44E0D6a57C00Ce3875158549;

        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
        calls[0] = AltoMulticallTestnet.Call({
            target: oracle,
            callData: abi.encodeWithSelector(
                OracleTestnet.setPrice.selector, 1.2 ether * LENDING_ORACLE_PRICE_PRECISION / 1 ether
            ),
            allowFailure: false
        });

        AltoMulticallTestnet(payable(multicall)).multicall(calls);

        vm.stopBroadcast();
    }
}

contract SetFeeStrategy is Script {
    function run() public {
        vm.startBroadcast();

        address multicall = 0x132ad32a41a49883eAF7697b8F77be76b2599720;
        address dusdUsm = 0xF3BA776C8a8F2f53803EAd17De373ae05319713d;
        address fixedFeeStrategy = 0x0812Fae840786ed577Bc610784AfF0D02edCb540;

        AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
        calls[0] = AltoMulticallTestnet.Call({
            target: dusdUsm,
            callData: abi.encodeWithSelector(IUsm.updateFeeStrategy.selector, fixedFeeStrategy),
            allowFailure: false
        });

        AltoMulticallTestnet(payable(multicall)).multicall(calls);

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

contract SetApproveOnAdapter is Script {
    function run() public {
        vm.startBroadcast();

        address multicall = 0x132ad32a41a49883eAF7697b8F77be76b2599720;
        address dusdUsm = 0xF3BA776C8a8F2f53803EAd17De373ae05319713d;
        address altoAdapter = 0xB76561B20d4a71F853aF0F4D9366F4478d3b3436;

        // AltoMulticallTestnet.Call[] memory calls = new AltoMulticallTestnet.Call[](1);
        // calls[0] = AltoMulticallTestnet.Call({
        //     target: altoAdapter,
        //     callData: abi.encodeWithSelector(AltoAdapter(payable(altoAdapter)).approveContract.selector, dusdUsm),
        //     allowFailure: false
        // });

        // AltoMulticallTestnet(payable(multicall)).multicall(calls);

        AltoAdapter(payable(altoAdapter)).approveContract(dusdUsm);

        vm.stopBroadcast();
    }
}
