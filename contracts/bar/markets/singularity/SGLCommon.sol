// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IERC4626} from "../../../utils/interfaces/common/IERC4626.sol";
import {SGLStorage} from "./SGLStorage.sol";
import {SingularityLib} from "../../../utils/markets/SingularityLib.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

abstract contract SGLCommon is SGLStorage {
    using RebaseLibrary for Rebase;
    using SingularityLib for ISingularity;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error MinLimit();
    error AccruePaused();

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    function getInterestDetails()
        external
        view
        returns (ISingularity.AccrueInfo memory _accrueInfo, uint256 utilization)
    {
        (_accrueInfo,,,,, utilization) = _getInterestRate();
    }

    // ************************** //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _getInterestRate()
        internal
        view
        returns (
            ISingularity.AccrueInfo memory _accrueInfo,
            Rebase memory _totalBorrow,
            Rebase memory _totalAsset,
            uint256 extraAmount,
            uint256 feeFraction,
            uint256 utilization
        )
    {
        return ISingularity(address(this)).getInterestRate(
            accrueInfo,
            totalAsset,
            totalBorrow
        );
    }

    function _accrueView() internal view override returns (Rebase memory _totalBorrow) {
        (, _totalBorrow,,,,) = _getInterestRate();
    }

    function _accrue() internal override {
        (
            ISingularity.AccrueInfo memory _accrueInfo,
            Rebase memory _totalBorrow,
            Rebase memory _totalAsset,
            uint256 extraAmount,
            uint256 feeFraction,
            uint256 utilization
        ) = _getInterestRate();

        emit LogAccrue(extraAmount, feeFraction, _accrueInfo.interestPerSecond, utilization);
        accrueInfo = _accrueInfo;
        totalBorrow = _totalBorrow;
        totalAsset = _totalAsset;
    }
}
