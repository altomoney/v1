// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

struct StandardUsmUpgradeBatchParams {
    address[] usmProxies;
}

struct StandardUsmUpgradeBatchReport {
    address[] usmProxies;
    address[] newImplementations;
}

/// @title StandardUsmUpgradeBatch
/// @notice Deploys one `DUSDUsm` implementation per standard USM proxy, using each proxy's
///         immutable `STABLE_TOKEN` and `UNDERLYING_ASSET`.
contract StandardUsmUpgradeBatch {
    StandardUsmUpgradeBatchReport internal _report;

    error EmptyUsmSet();

    constructor(StandardUsmUpgradeBatchParams memory _params) {
        uint256 length = _params.usmProxies.length;
        if (length == 0) revert EmptyUsmSet();

        address[] memory implementations = new address[](length);

        for (uint256 i; i < length; ++i) {
            address usmProxy = _params.usmProxies[i];
            address stableToken = IUsm(usmProxy).STABLE_TOKEN();
            address underlyingAsset = IUsm(usmProxy).UNDERLYING_ASSET();
            implementations[i] = address(new DUSDUsm(stableToken, underlyingAsset));
        }

        _report = StandardUsmUpgradeBatchReport({
            usmProxies: _params.usmProxies,
            newImplementations: implementations
        });
    }

    function getReport() external view returns (StandardUsmUpgradeBatchReport memory) {
        return _report;
    }
}
