// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SigUtils, Permit} from "@alto-test/helpers/SigUtils.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Permit_Test is SDUSDCommon {
    uint256 internal constant HOLDER_KEY = 0xA11CE;
    address internal holder;

    function setUp() public override {
        super.setUp();
        holder = vm.addr(HOLDER_KEY);
    }

    function test_DomainUsesTokenNameVersionOneChainAndProxy() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = vault.eip712Domain();

        assertEq(fields, hex"0f");
        assertEq(name, "Staked DUSD");
        assertEq(name, vault.name());
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(vault));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
        assertEq(vault.DOMAIN_SEPARATOR(), _domain(address(vault), block.chainid));
        assertEq(vault.nonces(holder), 0);
    }

    function testFuzz_PermitAllowsRelayerToApproveAndSpenderToRedeem(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000 ether));
        uint256 shares = _depositFor(holder, amount);
        Permit memory approval = _approval(shares);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);

        vm.prank(RECEIVER);
        vault.permit(holder, SPENDER, shares, approval.deadline, v, r, s);

        assertEq(vault.allowance(holder, SPENDER), shares);
        assertEq(vault.nonces(holder), 1);

        vm.prank(SPENDER);
        uint256 assets = vault.redeem(shares, RECEIVER, holder);

        assertEq(assets, amount);
        assertEq(dusd.balanceOf(RECEIVER), amount);
        assertEq(vault.balanceOf(holder), 0);
        assertEq(vault.allowance(holder, SPENDER), 0);
    }

    function test_PermitAllowsShareTransferAndCannotBeReplayed() public {
        uint256 shares = _depositFor(holder, 10 ether);
        Permit memory approval = _approval(shares);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);
        vault.permit(holder, SPENDER, shares, approval.deadline, v, r, s);

        vm.prank(SPENDER);
        vault.transferFrom(holder, RECEIVER, shares);

        vm.expectRevert();
        vault.permit(holder, SPENDER, shares, approval.deadline, v, r, s);
        assertEq(vault.nonces(holder), 1);
        assertEq(vault.allowance(holder, SPENDER), 0);
        assertEq(vault.balanceOf(RECEIVER), shares);
    }

    function test_RevertWhen_SignatureExpired() public {
        Permit memory approval = _approval(1 ether);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);
        vm.warp(approval.deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, approval.deadline)
        );
        vault.permit(holder, SPENDER, approval.value, approval.deadline, v, r, s);
        _assertUnused(vault);
    }

    function test_PermitIsValidAtDeadline() public {
        Permit memory approval = _approval(1 ether);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);
        vm.warp(approval.deadline);

        vault.permit(holder, SPENDER, approval.value, approval.deadline, v, r, s);
        assertEq(vault.nonces(holder), 1);
        assertEq(vault.allowance(holder, SPENDER), approval.value);
    }

    function test_RevertWhen_SignerIsNotOwner() public {
        Permit memory approval = _approval(1 ether);
        uint256 wrongKey = 0xB0B;
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, wrongKey);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, vm.addr(wrongKey), holder)
        );
        vault.permit(holder, SPENDER, approval.value, approval.deadline, v, r, s);
        _assertUnused(vault);
    }

    function test_RevertWhen_ApprovalAmountIsChanged() public {
        Permit memory approval = _approval(1 ether);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);

        vm.expectRevert();
        vault.permit(holder, SPENDER, approval.value + 1, approval.deadline, v, r, s);
        _assertUnused(vault);
    }

    function test_RevertWhen_SignatureIsForAnotherProxy() public {
        Permit memory approval = _approval(1 ether);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);
        SDUSD otherVault = _deployVault(SEED_SHARES, REWARD_DURATION);

        assertNotEq(vault.DOMAIN_SEPARATOR(), otherVault.DOMAIN_SEPARATOR());
        vm.expectRevert();
        otherVault.permit(holder, SPENDER, approval.value, approval.deadline, v, r, s);
        _assertUnused(otherVault);
    }

    function test_RevertWhen_SignatureIsForAnotherChain() public {
        Permit memory approval = _approval(1 ether);
        (uint8 v, bytes32 r, bytes32 s) = _sign(vault.DOMAIN_SEPARATOR(), approval, HOLDER_KEY);
        vm.chainId(block.chainid + 1);

        assertEq(vault.DOMAIN_SEPARATOR(), _domain(address(vault), block.chainid));
        vm.expectRevert();
        vault.permit(holder, SPENDER, approval.value, approval.deadline, v, r, s);
        _assertUnused(vault);
    }

    function _approval(uint256 value) internal view returns (Permit memory) {
        return Permit({owner: holder, spender: SPENDER, value: value, nonce: 0, deadline: block.timestamp + 1 hours});
    }

    function _sign(bytes32 domain, Permit memory approval, uint256 key)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return vm.sign(key, SigUtils.toTypedDataHash(domain, approval));
    }

    function _domain(address proxy, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Staked DUSD"),
                keccak256("1"),
                chainId,
                proxy
            )
        );
    }

    function _assertUnused(SDUSD token) internal view {
        assertEq(token.nonces(holder), 0);
        assertEq(token.allowance(holder, SPENDER), 0);
    }
}
