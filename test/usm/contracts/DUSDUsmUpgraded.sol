// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {UsmUpgraded} from "./UsmUpgraded.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";

/// @custom:oz-upgrades-from DUSDUsm
contract DUSDUsmUpgraded is UsmUpgraded {
    /// upgrade gap
    uint256[50] private __gap_dusdusm_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address dusd, address underlyingAsset) UsmUpgraded(dusd, underlyingAsset) {
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

    /// @dev Override to make initializeV2 accessible
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3) public override {
        super.initializeV2(_addedProperty1, _addedProperty2, _addedProperty3);
    }
}

