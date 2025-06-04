// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Signature} from "@alto/utils/interfaces/common/IAuth.sol";
import {Cluster} from "@alto/utils/Cluster/Cluster.sol";
import {TapToken} from "@alto/tokens/TapToken.sol";
import {ITapToken} from "@alto/tokens/interfaces/ITapToken.sol";
import "forge-std/Test.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TestHelpers} from "@alto-test/helpers/TestHelpers.sol";

contract AltoTokenTest is TestHelpers, TestHelperOz5 {
    TapToken tapToken;
    Cluster cluster = new Cluster(1, address(this));

    address internal immutable USER = makeAddr("User");

    function setUp() public override {
        setUpEndpoints(1, LibraryType.UltraLightNode);

        tapToken = new TapToken(
            ITapToken.TapTokenConstructorData({
                epochDuration: 1,
                endpoint: address(endpoints[1]),
                contributors: address(1),
                earlySupporters: address(2),
                supporters: address(3),
                lTap: address(4),
                dao: address(5),
                airdrop: address(6),
                owner: address(this),
                cluster: address(cluster)
            })
        );
        vm.label(address(tapToken), "tapToken");
    }

    function test_constructor() public {
        assertEq(address(tapToken.cluster()), address(cluster));
    }

    function test_erc20_permit(uint256 privateKey, uint32 deadline, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        Signature memory signature = _erc20PermitSignature(tapToken, privateKey, USER, amount, 0, deadline);

        tapToken.permit(user, USER, amount, deadline, signature.v, signature.r, signature.s);
        assertEq(tapToken.allowance(user, USER), amount);
        assertEq(tapToken.nonces(user), 1);
    }
}
