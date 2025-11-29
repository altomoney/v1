// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {Vm} from "forge-std/Vm.sol";

struct DusdUsmInitParams {
    address admin;
    address stableTokenTreasury;
    uint128 exposureCap;
    address priceStrategy;
}

library UsmDeployer {
    function deployDusdUsm(address dusd, address underlyingAsset, DusdUsmInitParams memory _initParams)
        external
        returns (address)
    {
        Vm vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        bool shouldUseSafeProxy = vm.envOr("VERIFY_PROXY", false);

        if (shouldUseSafeProxy) {
            Options memory opts;
            opts.constructorData = abi.encode(dusd, underlyingAsset);
            return Upgrades.deployUUPSProxy(
                "DUSDUsm.sol:DUSDUsm",
                abi.encodeCall(
                    DUSDUsm.initialize,
                    (
                        _initParams.admin,
                        _initParams.stableTokenTreasury,
                        _initParams.exposureCap,
                        _initParams.priceStrategy
                    )
                ),
                opts
            );
        } else {
            return UnsafeUpgrades.deployUUPSProxy(
                address(new DUSDUsm(dusd, underlyingAsset)),
                abi.encodeCall(
                    DUSDUsm.initialize,
                    (
                        _initParams.admin,
                        _initParams.stableTokenTreasury,
                        _initParams.exposureCap,
                        _initParams.priceStrategy
                    )
                )
            );
        }
    }
}

