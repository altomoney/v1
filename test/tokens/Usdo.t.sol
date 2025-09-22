// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Signature} from "@alto/utils/interfaces/IAuth.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {TestHelpers} from "@alto-test/helpers/TestHelpers.sol";

contract DusdTest is TestHelpers, TestHelperOz5 {
    DUSD dusd;

    address internal immutable USER = makeAddr("User");

    function setUp() public override {
        setUpEndpoints(1, LibraryType.UltraLightNode);

        dusd = new DUSD(endpoints[1], address(this));
        vm.label(address(dusd), "dusd");
    }

    function test_erc20_permit(uint256 privateKey, uint32 deadline, uint256 amount) public {
        address user;
        privateKey = _boundPrivateKey(privateKey);
        user = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));

        Signature memory signature = _erc20PermitSignature(dusd, privateKey, USER, amount, 0, deadline);

        dusd.permit(user, USER, amount, deadline, signature.v, signature.r, signature.s);
        assertEq(dusd.allowance(user, USER), amount);
        assertEq(dusd.nonces(user), 1);
    }
}
