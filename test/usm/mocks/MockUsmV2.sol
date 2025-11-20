// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Usm} from "@alto/usm/Usm.sol";

/**
 * @dev Mock contract to test USM upgrades, not to be used in production.
 */
contract MockUsmV2 is Usm {
    /**
     * @dev Constructor
     * @param stableToken The address of the stable token contract
     * @param underlyingAsset The address of the collateral asset
     */
    constructor(address stableToken, address underlyingAsset) Usm(stableToken, underlyingAsset) {
        // Intentionally left blank
    }

    function test_coverage_ignore() public virtual {
        // Intentionally left blank.
        // Excludes contract from coverage.
    }

    function initialize() external reinitializer(2) {
        // Intentionally left blank
    }

    function USM_REVISION() public pure virtual override returns (uint256) {
        return 2;
    }

    function _burnStableToken(address from, uint256 amount) internal override {
        revert("NOT_IMPLEMENTED");
    }

    function _mintStableToken(address to, uint256 amount) internal override {
        revert("NOT_IMPLEMENTED");
    }

    function _getCurrentlyMintedStableTokenByUsm() internal view override returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }
}
