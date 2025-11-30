// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import {DeployAltoTestnet, AltoTestnetParams, AltoTestnetInput} from "@alto/deployments/testnet/DeployAltoTestnet.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";
import {console} from "forge-std/console.sol";

contract AltoReleaseTest is Test, TestHelperOz5 {
    AltoTestnetParams params;
    AltoTestnetInput input;
    AltoMulticallTestnet altoMulticall;

    function setUp() public override {
        string memory rpcUrl = vm.rpcUrl("sepolia");
        vm.createSelectFork(rpcUrl);

        params = AltoTestnetParams({
            skipLendingDeployment: false,
            lzEndpoint: address(0x6EDCE65403992e310A62460808c4b910D972f10f),
            wrappedNativeToken: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            uniswapV3NonFungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            deployer: address(this)
        });
    }

    function test_deployAltoTestnet() public {
        params.deployer = address(this);
        input = DeployAltoTestnet.deploy(params, input);
    }
}
