// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Penrose} from "tapioca-bar/Penrose.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {UsdoReport} from "../interfaces/IAltoReport.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {USDOFlashloanHelper} from "tapioca-bar/usdo/USDOFlashloanHelper.sol";
import {IUsdo} from "tapioca-bar/usdo/IUsdo.sol";
import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {BBLeverage} from "tapioca-bar/markets/bigBang/BBLeverage.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";
import {BBDebtRateHelper} from "tapioca-bar/markets/bigBang/BBDebtRateHelper.sol";
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";

abstract contract UsdoProcedure {
    function _deployUsdo(address endpoint, address delegate) internal returns (UsdoReport memory report) {
        report.usdo = (address(new Usdo(endpoint, address(this), address(1))));
        report.usdoFlashloanHelper = address(new USDOFlashloanHelper(IUsdo(report.usdo), delegate));

        Usdo(payable(report.usdo)).setFlashloanHelper(report.usdoFlashloanHelper);
        Usdo(payable(report.usdo)).setMinterStatus(report.usdoFlashloanHelper, true);
        Usdo(payable(report.usdo)).setBurnerStatus(report.usdoFlashloanHelper, true);

        Usdo(payable(report.usdo)).setDelegate(delegate);
        Usdo(payable(report.usdo)).transferOwnership(delegate);
        return report;
    }
}
