// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Tapioca
import {BuyCollateralData} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {SellCollateralData} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {IMarketHelper} from "tap-utils/interfaces/bar/IMarketHelper.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {SafeApprove} from "tap-utils/libraries/SafeApprove.sol";
import {MagnetarBaseModule} from "./MagnetarBaseModule.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title MagnetarLeverageModule
 * @author TapiocaDAO
 * @notice Magnetar leverage related operations
 */
contract MagnetarLeverageModule is MagnetarBaseModule {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    constructor( address _magnetarHelper) MagnetarBaseModule(_magnetarHelper) {}

    function buyCollateral(BuyCollateralData memory data) public payable {
        /**
         * @dev validate data
         */
        _validateBuyCollateral(data);

        _marketBuyCollateral(
            IMarket(data.market),
            data.marketHelper,
            data.user,
            data.user,
            data.borrowAmount,
            data.collateralAmount,
            data.data
        );
    }

    function sellCollateral(SellCollateralData memory data) public payable {
        /**
         * @dev validate data
         */
        _validateSellCollateral(data);

        _marketSellCollateral(IMarket(data.market), data.marketHelper, data.user, data.collateralShares, data.data);
    }

    /// =====================
    /// Private
    /// =====================

    function _validateBuyCollateral(BuyCollateralData memory data) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkExternalData(data.market, data.marketHelper);
    }

    function _validateSellCollateral(SellCollateralData memory data) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkExternalData(data.market, data.marketHelper);
    }

    function _checkExternalData(address market, address marketHelper) private view {
        _checkWhitelisted(market);
        _checkWhitelisted(marketHelper);
    }
}
