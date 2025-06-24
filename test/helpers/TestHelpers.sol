// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Signature} from "@alto/utils/interfaces/IAuth.sol";
import {SigUtils, Permit} from "@alto-test/helpers/SigUtils.sol";

uint256 constant SIGNATURE_DEADLINE = type(uint32).max;

contract TestHelpers is Test {
    function _boundPrivateKey(uint256 privateKey) internal returns (uint256) {
        privateKey = bound(privateKey, 1, type(uint160).max);

        address user = vm.addr(privateKey);
        vm.label(user, "address of generated private key");

        return privateKey;
    }

    function _erc20PermitSignature(
        IERC20Permit token,
        uint256 privateKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (Signature memory signature_) {
        address user = vm.addr(privateKey);

        Permit memory permit = Permit({owner: user, spender: spender, value: value, nonce: nonce, deadline: deadline});

        bytes32 digest = SigUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), permit);

        Signature memory signature;
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);

        return signature;
    }
}
