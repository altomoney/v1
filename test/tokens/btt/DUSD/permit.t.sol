// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {TestHelpers} from "@alto-test/helpers/TestHelpers.sol";
import {Signature} from "@alto/utils/interfaces/IAuth.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract DUSDPermit is TestHelpers, DUSDCommon {
    address internal immutable SPENDER = makeAddr("spender");
    uint256 internal constant PERMIT_VALUE = 100e18;

    function test_RevertWhen_DeadlineHasPassed(uint256 privateKey) external {
        privateKey = _boundPrivateKey(privateKey);
        address owner = vm.addr(privateKey);
        uint256 deadline = block.timestamp - 1;
        Signature memory signature = _erc20PermitSignature(dusd, privateKey, SPENDER, PERMIT_VALUE, 0, deadline);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        dusd.permit(owner, SPENDER, PERMIT_VALUE, deadline, signature.v, signature.r, signature.s);
    }

    function test_RevertWhen_SignatureWasNotProducedByOwner(uint256 privateKey, uint256 otherPrivateKey) external {
        privateKey = _boundPrivateKey(privateKey);
        otherPrivateKey = _boundPrivateKey(otherPrivateKey);
        vm.assume(privateKey != otherPrivateKey);
        address owner = vm.addr(privateKey);
        uint256 deadline = block.timestamp + 1 days;
        Signature memory signature = _erc20PermitSignature(dusd, otherPrivateKey, SPENDER, PERMIT_VALUE, 0, deadline);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        dusd.permit(owner, SPENDER, PERMIT_VALUE, deadline, signature.v, signature.r, signature.s);
    }

    function test_WhenSignatureIsValid(uint256 privateKey, uint256 value, uint32 deadline) external {
        privateKey = _boundPrivateKey(privateKey);
        address owner = vm.addr(privateKey);
        deadline = uint32(bound(deadline, block.timestamp + 1, type(uint32).max));
        Signature memory signature = _erc20PermitSignature(dusd, privateKey, SPENDER, value, 0, deadline);

        dusd.permit(owner, SPENDER, value, deadline, signature.v, signature.r, signature.s);

        assertEq(dusd.allowance(owner, SPENDER), value);
        assertEq(dusd.nonces(owner), 1);
    }
}
