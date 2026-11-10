// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract Constants {
    // default admin role
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    // admin role for USM
    bytes32 public constant USM_CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 public constant USM_TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");
    bytes32 public constant USM_SWAP_FREEZER_ROLE = keccak256("SWAP_FREEZER_ROLE");
    bytes32 public constant USM_LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    bytes32 public constant USM_SWAPPER_ROLE = keccak256("SWAPPER_ROLE");

    // signature typehash for USM
    bytes32 public constant USM_BUY_ASSET_WITH_SIG_TYPEHASH = keccak256(
        "BuyAssetWithSig(address originator,uint256 minAmount,address receiver,uint256 nonce,uint256 deadline)"
    );
    bytes32 public constant USM_SELL_ASSET_WITH_SIG_TYPEHASH = keccak256(
        "SellAssetWithSig(address originator,uint256 maxAmount,address receiver,uint256 nonce,uint256 deadline)"
    );

    // defaults used in test environment
    uint128 constant DEFAULT_CAPACITY = 100_000_000e18;
    uint256 constant DEFAULT_FIXED_PRICE = 1e18;
    uint256 constant DEFAULT_USM_BUY_FEE = 0.1e4; // 10%
    uint256 constant DEFAULT_USM_SELL_FEE = 0.1e4; // 10%
    uint128 constant DEFAULT_USM_USDC_EXPOSURE = 100_000_000e6; // 6 decimals for USDC
    uint128 constant DEFAULT_USM_USDC_AMOUNT = 100e6; // 6 decimals for USDC
    uint128 constant DEFAULT_USM_DUSD_AMOUNT = 100e18;

    // sample users used across unit tests
    address constant ALICE = address(0x1111);
    address constant BOB = address(0x1112);
    address constant CHARLES = address(0x1113);

    address constant FAUCET = address(0x10001);
    address constant TREASURY = address(0x10002);

    address constant SHORT_EXECUTOR = address(0x10003);
    address constant FEE_RECIPIENT = address(0x10004);
}
