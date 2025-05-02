// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Magnetar} from "tapioca-periph/Magnetar/Magnetar.sol";
import {MagnetarCollateralModule} from "tapioca-periph/Magnetar/modules/MagnetarCollateralModule.sol";
import {MagnetarOptionModule} from "tapioca-periph/Magnetar/modules/MagnetarOptionModule.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {MagnetarLeverageModule} from "tapioca-periph/Magnetar/modules/MagnetarLeverageModule.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";
import {MagnetarReport, MagnetarDepsReport} from "../interfaces/ITapiocaReport.sol";
import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";

abstract contract MagnetarProcedure {
    function _deployMagnetarDeps() internal returns (MagnetarDepsReport memory deps) {
        deps.magnetarHelper = address(new MagnetarHelper());
        deps.magnetarCollateralModule = address(new MagnetarCollateralModule(deps.magnetarHelper));
        deps.magnetarMintModule = address(new MagnetarMintModule(deps.magnetarHelper));
        deps.magnetarOptionModule = address(new MagnetarOptionModule(deps.magnetarHelper));
        deps.magnetarLeverageModule = address(new MagnetarLeverageModule(deps.magnetarHelper));
    }

    function _deployMagnetar(
        address owner,
        address cluster,
        address zeroXSwapper,
        address wrappedNativeToken,
        MagnetarDepsReport memory deps
    ) internal returns (MagnetarReport memory report) {
        report.magnetar = address(
            new Magnetar(
                ICluster(cluster),
                owner,
                payable(deps.magnetarCollateralModule),
                payable(deps.magnetarMintModule),
                payable(deps.magnetarOptionModule),
                payable(deps.magnetarLeverageModule),
                deps.magnetarHelper
            )
        );
        report.simpleLeverageExecutor =
            address(new SimpleLeverageExecutor(IZeroXSwapper(zeroXSwapper), ICluster(cluster), wrappedNativeToken));
    }
}
