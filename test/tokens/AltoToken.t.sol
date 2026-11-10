// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Signature} from "@alto/utils/interfaces/IAuth.sol";
import {AltoToken} from "@alto/tokens/AltoToken.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TestHelpers} from "@alto-test/helpers/TestHelpers.sol";

contract AltoTokenTest is TestHelpers, TestHelperOz5 {
    AltoToken altoToken;

    address internal immutable USER = makeAddr("User");

    function setUp() public override {
        setUpEndpoints(1, LibraryType.UltraLightNode);

        altoToken = new AltoToken(endpoints[1], address(this));
        vm.label(address(altoToken), "altoToken");
    }

    function test_erc20_permit(uint256 privateKey, uint32 deadline, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        Signature memory signature = _erc20PermitSignature(altoToken, privateKey, USER, amount, 0, deadline);

        altoToken.permit(user, USER, amount, deadline, signature.v, signature.r, signature.s);
        assertEq(altoToken.allowance(user, USER), amount);
        assertEq(altoToken.nonces(user), 1);
    }
}
