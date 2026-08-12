// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";

/// @notice ERC20 reward with a Yearn-style token() getter that must not be treated as a Convex stash wrapper.
contract MockTokenizedVaultReward is ERC20MockMintable {
    address public token;

    constructor(address token_) ERC20MockMintable("Tokenized vault reward", "VAULT") {
        token = token_;
    }
}
