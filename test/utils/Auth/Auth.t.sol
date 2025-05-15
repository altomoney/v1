// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AuthInstance} from "./AuthInstance.sol";
import {IAuth, Authorization, Signature} from "@alto-monorepo/utils/interfaces/common/IAuth.sol";
import {SigUtils} from "../../helpers/SigUtils.sol";

contract AuthTest is Test {
    AuthInstance public auth;
    bytes32 public AUTHORIZATION_TYPEHASH;

    uint256 privateKey = 0x1234567890abcdef;
    address public alice = vm.addr(privateKey);
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        auth = new AuthInstance();
        AUTHORIZATION_TYPEHASH = auth.authorizationTypeHash();
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

        vm.expectRevert(IAuth.AuthAuthorizationAlreadySet.selector);

        vm.prank(alice);
        auth.setAuthorization(bob, true);

        vm.prank(bob);
        auth.setValue(alice, 1);
        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);
    }

    function test_isSenderAuthorized_onBehalf_signed() public {
        Authorization memory authorization = Authorization({
            owner: alice,
            spender: bob,
            isAuthorizedStatus: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.domainSeparator(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectEmit(true, true, true, true);
        emit IAuth.SetAuthorization(charlie, alice, bob, true);

        vm.prank(charlie);
        auth.setAuthorizationWithSignature(authorization, sig);

        vm.prank(bob);
        auth.setValue(alice, 1);

        assertEq(auth.values(alice), 1);
        assertEq(auth.isAuthorized(alice, bob), true);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidNonce() public {
        Authorization memory authorization = Authorization({
            owner: alice,
            spender: bob,
            isAuthorizedStatus: true,
            nonce: 10,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.domainSeparator(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(IAuth.AuthInvalidNonce.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSignature(authorization, sig);

        assertEq(auth.isAuthorized(alice, bob), false);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidDeadline() public {
        Authorization memory authorization = Authorization({
            owner: alice,
            spender: bob,
            isAuthorizedStatus: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;

        vm.warp(block.timestamp + 1 days + 1);
        bytes32 digest = getTypedDataHash(auth.domainSeparator(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        vm.expectRevert(IAuth.AuthSignatureExpired.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSignature(authorization, sig);

        assertEq(auth.isAuthorized(alice, bob), false);
    }

    function test_isSenderAuthorized_onBehalf_signed_revert_invalidSignature() public {
        Authorization memory authorization = Authorization({
            owner: alice,
            spender: bob,
            isAuthorizedStatus: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        Signature memory sig;
        bytes32 digest = getTypedDataHash(auth.domainSeparator(), authorization);
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        sig.v = 30;
        vm.expectRevert(IAuth.AuthInvalidSignature.selector);

        vm.prank(charlie);
        auth.setAuthorizationWithSignature(authorization, sig);

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

        vm.expectRevert(AuthInstance.Unauthorized.selector);

        vm.prank(bob);
        auth.setValue(alice, 2);

        assertEq(auth.values(alice), 1);
    }

    function test_isSenderAuthorized_revert() public {
        vm.expectRevert(AuthInstance.Unauthorized.selector);

        vm.prank(bob);
        auth.setValue(alice, 1);
    }

    /// @dev Computes the hash of the EIP-712 encoded data.
    function getTypedDataHash(bytes32 domainSeparator, Authorization memory authorization)
        public
        view
        returns (bytes32)
    {
        return SigUtils.toTypedDataHash(AUTHORIZATION_TYPEHASH, domainSeparator, authorization);
    }
}
