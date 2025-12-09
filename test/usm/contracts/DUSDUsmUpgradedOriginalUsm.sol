// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Usm} from "@alto/usm/Usm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";

/// @custom:oz-upgrades-from DUSDUsm
contract DUSDUsmUpgradedOriginalUsm is Usm {
    uint128 public addedProperty1;
    address public addedProperty2;
    uint128 public addedProperty3;

    /// upgrade gap
    uint256[47] private __gap_dusdusm_upgraded;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address dusd, address underlyingAsset) Usm(dusd, underlyingAsset) {
        _disableInitializers();
    }

    function USM_REVISION() public pure override returns (uint256) {
        return 2;
    }

    function initialize(
        address admin,
        address stableTokenTreasury,
        uint128 exposureCap,
        address priceStrategy,
        AccessMode accessMode,
        address feeRecipient
    ) external initializer {
        __Usm_init(admin, stableTokenTreasury, exposureCap, priceStrategy, accessMode, feeRecipient);
    }

    /// @dev Reinitializer for version 2 upgrade - initializes new storage variables
    function initializeV2() public reinitializer(2) {}

    function setAddedProperty1(uint128 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(address value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(uint128 value) external {
        addedProperty3 = value;
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

