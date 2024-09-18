// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Magnetar} from "tapioca-periph/Magnetar/Magnetar.sol";
import {MagnetarCollateralModule} from "tapioca-periph/Magnetar/modules/MagnetarCollateralModule.sol";
import {MagnetarOptionModule} from "tapioca-periph/Magnetar/modules/MagnetarOptionModule.sol";
import {MagnetarMintModule} from "tapioca-periph/Magnetar/modules/MagnetarMintModule.sol";
import {MagnetarYieldBoxModule} from "tapioca-periph/Magnetar/modules/MagnetarYieldBoxModule.sol";
import {MagnetarHelper} from "tapioca-periph/Magnetar/MagnetarHelper.sol";
import {MagnetarReport, MagnetarDepsReport} from "../interfaces/ITapiocaReport.sol";
import {SimpleLeverageExecutor} from "tapioca-bar/markets/leverage/SimpleLeverageExecutor.sol";
import {TOFTHelper} from "tapiocaz/tOFT/extensions/TOFTHelper.sol";
import {IPearlmit} from "tap-utils/pearlmit/PearlmitHandler.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {IZeroXSwapper} from "tap-utils/interfaces/periph/IZeroXSwapper.sol";

abstract contract MagnetarProcedure {
    function _deployMagnetarDeps(address pearlmit, address toeHelper)
        internal
        returns (MagnetarDepsReport memory deps)
    {
        deps.magnetarCollateralModule = address(new MagnetarCollateralModule(IPearlmit(pearlmit), toeHelper));
        deps.magnetarMintModule = address(new MagnetarMintModule(IPearlmit(pearlmit), toeHelper));
        deps.magnetarOptionModule = address(new MagnetarOptionModule(IPearlmit(pearlmit), toeHelper));
        deps.magnetarYieldboxModule = address(new MagnetarYieldBoxModule(IPearlmit(pearlmit), toeHelper));
    }

    function _deployMagnetar(
        address owner,
        address cluster,
        address pearlmit,
        address toeHelper,
        address zeroXSwapper,
        address wrappedNativeToken,
        MagnetarDepsReport memory deps
    ) internal returns (MagnetarReport memory report) {
        report.magnetarHelper = address(new MagnetarHelper());
        report.magnetar = address(
            new Magnetar(
                ICluster(cluster),
                owner,
                payable(deps.magnetarCollateralModule),
                payable(deps.magnetarMintModule),
                payable(deps.magnetarOptionModule),
                payable(deps.magnetarYieldboxModule),
                IPearlmit(pearlmit),
                toeHelper,
                IMagnetarHelper(report.magnetarHelper)
            )
        );
        report.simpleLeverageExecutor = address(
            new SimpleLeverageExecutor(
                IZeroXSwapper(zeroXSwapper), ICluster(cluster), wrappedNativeToken, IPearlmit(pearlmit)
            )
        );
    }
}
