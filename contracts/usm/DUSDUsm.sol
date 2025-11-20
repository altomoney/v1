// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Usm} from "./Usm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

contract DUSDUsm is Usm {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address dusd, address underlyingAsset) Usm(dusd, underlyingAsset) {
        _disableInitializers();
    }

    /// upgrade gap
    uint256[50] private __gap_dusdusm;

    function initialize(address admin, address stableTokenTreasury, uint128 exposureCap, address priceStrategy)
        external
        initializer
    {
        __Usm_init(admin, stableTokenTreasury, exposureCap, priceStrategy);
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
