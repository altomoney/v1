// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Usdo} from "tapioca-bar/usdo/Usdo.sol";
import {UsdoReport} from "../interfaces/IAltoReport.sol";
import {USDOFlashloanHelper} from "tapioca-bar/usdo/USDOFlashloanHelper.sol";
import {IUsdo} from "tapioca-bar/usdo/IUsdo.sol";

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
