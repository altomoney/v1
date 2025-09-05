// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import {DeployAltoTestnet, AltoTestnetParams, AltoTestnetInput} from "@alto/deployments/testnet/DeployAltoTestnet.sol";

contract AltoReleaseTest is Test, TestHelperOz5 {
    AltoTestnetParams params;
    AltoTestnetInput input;
    address deployer = address(makeAddr("owner"));

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        params = AltoTestnetParams({
            owner: address(this),
            skipLendingDeployment: false,
            lzEndpoint: address(endpoints[1]),
            wrappedNativeToken: makeAddr("weth"),
            universalRewardsDistributor: makeAddr("universalRewardsDistributor")
        });
    }

    function test_deployAltoTestnet() public {
        params.owner = address(this);
        console.log("msg.sender11", address(this));
        input = DeployAltoTestnet.deploy(params, input);
    }
}
