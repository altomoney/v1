// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AdvancedPermissionsUsm} from "./AdvancedPermissionsUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {DirectionAccess} from "./interfaces/IAdvancedPermissionsUsm.sol";

/**
 * @title DUSDAdvancedPermissionsUsm
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Universal Stability Module with independent buy and sell access control for DUSD.
 */
contract DUSDAdvancedPermissionsUsm is AdvancedPermissionsUsm {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address dusd, address underlyingAsset) AdvancedPermissionsUsm(dusd, underlyingAsset) {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address stableTokenTreasury,
        uint128 exposureCap,
        address priceStrategy,
        DirectionAccess buyAccess,
        DirectionAccess sellAccess
    ) external initializer {
        __AdvancedPermissionsUsm_init(admin, stableTokenTreasury, exposureCap, priceStrategy, buyAccess, sellAccess);
    }

    function _getCurrentlyMintedStableTokenByUsm() internal view override returns (uint256) {
        (uint256 minted,) = IDUSD(STABLE_TOKEN).minterConfig(address(this));
        return minted;
    }

    function _mintStableToken(address to, uint256 amount) internal override {
        IDUSD(STABLE_TOKEN).mint(to, amount);
    }

    function _burnStableToken(address from, uint256 amount) internal override {
        IDUSD(STABLE_TOKEN).burn(from, amount);
    }
}
