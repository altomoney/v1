// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Test} from "forge-std/Test.sol";
import {IMarket} from "../../../../contracts/utils/interfaces/bar/IMarket.sol";
import {MarketERC4626} from "../../../../contracts/bar/markets/MarketERC4626.sol";

abstract contract Market4626PermitUtils is Test {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("PermitBorrow(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_BORROW =
        0xe9685ff6d48c617fe4f692c50e602cce27cbad0290beb93cfa77eac43968d58c;
    // keccak256("PermitCollateral(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_COLLATERAL =
        0xfeec9fa3489db68a4f9d4df8b97195b797a67db501fb9d6e83f40d93c523d6d2;
    // keccak256("PermitLiquidity(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_LIQUIDITY =
        0x05ec39b1dbfea40ef9a702d0520c523a29ab686fe4626bd51466caaff3a1d483;

    // function setUp() external virtual override {}

    function _getActionId(MarketERC4626.PermitActions _action) internal returns (bytes32) {
        bytes32 actionId;
        if (_action == MarketERC4626.PermitActions.VAULT_ERC4626_TRANSFER) {
            actionId = _PERMIT_TYPEHASH;
        } else if (_action == MarketERC4626.PermitActions.LIQUIDITY) {
            actionId = _PERMIT_TYPEHASH_LIQUIDITY;
        } else if (_action == MarketERC4626.PermitActions.COLLATERAL) {
            actionId = _PERMIT_TYPEHASH_COLLATERAL;
        } else if (_action == MarketERC4626.PermitActions.BORROW) {
            actionId = _PERMIT_TYPEHASH_BORROW;
        }
        return actionId;
    }

    function _signMarketPermitAction(
        address _market,
        uint160 _userPk,
        address _spender,
        MarketERC4626.PermitActions _action,
        uint256 _value,
        uint256 _deadline,
        uint256 _nonce
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 actionId = _getActionId(_action);
        address _user = vm.addr(_userPk);
        bytes32 structHash = keccak256(abi.encode(actionId, _user, _spender, _value, _nonce, _deadline));
        bytes32 digest = ECDSA.toTypedDataHash(IMarket(_market).DOMAIN_SEPARATOR(), structHash);
        (v, r, s) = vm.sign(_userPk, digest);
    }
}
