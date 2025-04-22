// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {ISingularity} from "../interfaces/bar/ISingularity.sol";
import {IERC4626} from "../interfaces/common/IERC4626.sol";
import {ISGLInterestHelper} from "../interfaces/bar/ISGLInterestHelper.sol";
import {IMarket, Module} from "../interfaces/bar/IMarket.sol";
/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

error ModuleNotSet();

library SingularityLib {

    function getInterestRate(
        ISingularity _market,
        ISingularity.AccrueInfo memory __accrueInfo,
        Rebase memory __totalAsset,
        Rebase memory __totalBorrow
    )
        external
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
        return ISGLInterestHelper(
            _market.interestHelper()
        ).getInterestRate(
            ISGLInterestHelper.InterestRateCall(
                IERC4626(address(this)),
                __accrueInfo,
                __totalAsset,
                __totalBorrow,
                _market._protocolFee(),
                _market.interestElasticity(),
                _market.minimumTargetUtilization(),
                _market.maximumTargetUtilization(),
                _market.minimumInterestPerSecond(),
                _market.maximumInterestPerSecond(),
                _market.startingInterestPerSecond()
            )
        );
    }

    function extractModule(ISingularity _market, Module _module) external view returns (address) {
        address module;
        if (_module == Module.Base) {
            return address(_market);
        } else if (_module == Module.Borrow) {
            module = address(_market.borrowModule());
        } else if (_module == Module.Collateral) {
            module = address(_market.collateralModule());
        } else if (_module == Module.Liquidation) {
            module = address(_market.liquidationModule());
        } else if (_module == Module.Leverage) {
            module = address(_market.leverageModule());
        }
        if (module == address(0)) revert ModuleNotSet();

        return module;
    }
}
