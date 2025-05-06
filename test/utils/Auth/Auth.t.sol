// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AuthInstance} from "./AuthInstance.sol";
import {IAuth, Authorization, Signature} from "tap-utils/interfaces/common/IAuth.sol";
import {ErrorsLib} from "tap-lending/libraries/ErrorsLib.sol";
import {AUTHORIZATION_TYPEHASH} from "tap-utils/utils/Constants.sol";

contract AuthTest is Test {
    AuthInstance public auth;

    uint256 privateKey = 0x1234567890abcdef;
    address public alice = vm.addr(privateKey);
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        auth = new AuthInstance();
    }

    function test_isSenderAuthorized_self() public {
        vm.prank(alice);
        auth.setValue(alice, 1);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, alice), false);
    }

    function test_isSenderAuthorized_onBehalf() public {
        vm.expectEmit(true, true, true, true);
        emit IAuth.SetAuthorization(alice, alice, bob, true);

        vm.prank(alice);
        auth.setAuthorization(bob, true);

        vm.prank(bob);
        auth.setValue(alice, 1);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);
    }

    function test_isSenderAuthorized_onBehalf_revert_alreadySet() public {
        vm.prank(alice);
        auth.setAuthorization(bob, true);

        vm.expectRevert(IAuth.ALREADY_SET.selector);

        vm.prank(alice);
        auth.setAuthorization(bob, true);

        vm.prank(bob);
        auth.setValue(alice, 1);
        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);
    }

    function test_isSenderAuthorized_onBehalf_signed() public {
        Authorization memory authorization = Authorization({
            authorizer: alice,
            authorized: bob,
            isAuthorized: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit IAuth.SetAuthorization(charlie, alice, bob, true);

        vm.prank(charlie);
        auth.setAuthorizationWithSig(authorization, sig);

        vm.prank(bob);
        auth.setValue(alice, 1);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidNonce() public {
        Authorization memory authorization = Authorization({
            authorizer: alice,
            authorized: bob,
            isAuthorized: true,
            nonce: 10,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(IAuth.INVALID_NONCE.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSig(authorization, sig);

        assertEq(auth.isAuthorized(alice, bob), false);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidDeadline() public {
        Authorization memory authorization = Authorization({
            authorizer: alice,
            authorized: bob,
            isAuthorized: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;

        vm.warp(block.timestamp + 1 days + 1);
        bytes32 digest = getTypedDataHash(auth.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(IAuth.SIGNATURE_EXPIRED.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSig(authorization, sig);

        assertEq(auth.isAuthorized(alice, bob), false);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidSignature() public {
        Authorization memory authorization = Authorization({
            authorizer: alice,
            authorized: bob,
            isAuthorized: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.DOMAIN_SEPARATOR(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        sig.v = 30;
        vm.expectRevert(IAuth.INVALID_SIGNATURE.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSig(authorization, sig);

        assertEq(auth.isAuthorized(alice, bob), false);
    }

    function test_isSenderAuthorized_disable() public {
        vm.expectEmit(true, true, true, true);
        emit IAuth.SetAuthorization(alice, alice, bob, true);

        vm.prank(alice);
        auth.setAuthorization(bob, true);

        vm.prank(bob);
        auth.setValue(alice, 1);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);

        vm.expectEmit(true, true, true, true);
        emit IAuth.SetAuthorization(alice, alice, bob, false);

        vm.prank(alice);
        auth.setAuthorization(bob, false);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), false);

        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));

        vm.prank(bob);
        auth.setValue(alice, 2);

        assertEq(auth.values(alice), 1);
    }

    function test_isSenderAuthorized_revert() public {
        vm.expectRevert(bytes(ErrorsLib.UNAUTHORIZED));

        vm.prank(bob);
        auth.setValue(alice, 1);
    }

    /// @dev Computes the hash of the EIP-712 encoded data.
    function getTypedDataHash(bytes32 domainSeparator, Authorization memory authorization)
        public
        view
        returns (bytes32)
    {
        return keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct(authorization)));
    }

    function hashStruct(Authorization memory authorization) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                AUTHORIZATION_TYPEHASH,
                authorization.authorizer,
                authorization.authorized,
                authorization.isAuthorized,
                authorization.nonce,
                authorization.deadline
            )
        );
    }
}
