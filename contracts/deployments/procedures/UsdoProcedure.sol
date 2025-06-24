// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {USDO} from "@alto/tokens/USDO.sol";
import {UsdoReport} from "../interfaces/IAltoReport.sol";

abstract contract UsdoProcedure {
    function _deployUsdo(address endpoint, address delegate) internal returns (UsdoReport memory report) {
        report.usdo = (address(new USDO(endpoint, address(this))));
        //report.usdoFlashloanHelper = address(new USDOFlashloanHelper(IUSDO(report.usdo), delegate));

        // USDO(payable(report.usdo)).setFlashloanHelper(report.usdoFlashloanHelper);
        // USDO(payable(report.usdo)).setMinterStatus(report.usdoFlashloanHelper, true);
        // USDO(payable(report.usdo)).setBurnerStatus(report.usdoFlashloanHelper, true);

        USDO(payable(report.usdo)).setDelegate(delegate);
        USDO(payable(report.usdo)).transferOwnership(delegate);
        return report;
    }
}
