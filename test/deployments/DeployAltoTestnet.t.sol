// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import {DeployAltoTestnet, AltoTestnetParams, AltoTestnetInput} from "@alto/deployments/testnet/DeployAltoTestnet.sol";
import {AltoMulticallTestnet} from "@alto/deployments/testnet/contracts/AltoMulticallTestnet.sol";

contract AltoReleaseTest is Test, TestHelperOz5 {
    AltoTestnetParams params;
    AltoTestnetInput input;
    AltoMulticallTestnet altoMulticall;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        altoMulticall = new AltoMulticallTestnet();

        params = AltoTestnetParams({
            owner: address(this),
            altoMulticall: address(altoMulticall),
            skipLendingDeployment: false,
            lzEndpoint: address(endpoints[1]),
            wrappedNativeToken: makeAddr("weth"),
            universalRewardsDistributor: address(0)
        });
    }

    function test_deployAltoTestnet() public {
        params.owner = address(this);
        input = DeployAltoTestnet.deploy(params, input);
    }
}
