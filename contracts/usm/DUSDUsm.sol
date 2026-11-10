// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Usm} from "./Usm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";

/// @author GPM
/// @author Adapted from Aave (https://github.com/aave/gho-core/)
contract DUSDUsm is Usm {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address dusd, address underlyingAsset) Usm(dusd, underlyingAsset) {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address stableTokenTreasury,
        uint128 exposureCap,
        address priceStrategy,
        AccessMode accessMode
    ) external initializer {
        __Usm_init(admin, stableTokenTreasury, exposureCap, priceStrategy, accessMode);
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
