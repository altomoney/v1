// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca
import {
    ExitPositionAndRemoveCollateralData,
    ICommonExternalContracts,
    LockData,
    IRemoveAndRepay
} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {ITapiocaOptionBroker} from "tap-token/interfaces/ITapiocaOptionBroker.sol";
import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
 * @title MagnetarOptionModule
 * @author TapiocaDAO
 * @notice Magnetar options related operations
 */
contract MagnetarOptionModule is MagnetarBaseModule {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error Magnetar_ComposeMsgNotAllowed();

    constructor(address _toeHelper, address _magnetarHelper) MagnetarBaseModule(_toeHelper, _magnetarHelper) {}

    /**
     * @notice helper to perform tOLP.lock(...) and tOB.participate(...)
     * @param data.user the user to perform the operation for
     * @param data.singularity the SGL address
     * @param data.fraction the amount to lock
     * @param data.lockData the data needed to lock on tOB
     * @param data.participateData the data needed to participate on tOLP
     */
    function lock(LockData memory data) public payable {
        /**
         * @dev validate data
         */
        _validateLock(data);

        /**
         * @dev if `lockData.lock`:
         *          - transfer `fraction` from data.user to `address(this)
         *          - deposits `fraction` to YB for `address(this)`
         *          - performs tOLP.lock
         */
        if (data.lockData.lock) {
            _lock(data);
        }
    }

    function _lock(LockData memory data) private {
        address usdo = ITapiocaOptionBroker(data.lockData.target).getUSDO();
        _extractTokens(data.user, usdo, data.lockData.usdoAmount);
        IERC20(usdo).approve(data.lockData.target, data.lockData.usdoAmount);
        ITapiocaOptionBroker(data.lockData.target).lock(
            data.lockData.to, data.lockData.bucketId, data.lockData.usdoAmount, data.lockData.sglMarket
        );
        IERC20(usdo).approve(data.lockData.target, 0);
    }

    /**
     * @notice helper to exit from  tOB, unlock from tOLP, remove from SGL, repay on BB, remove collateral from BB and withdraw
     * @dev all steps are optional:
     *         - if `removeAndRepayData.exitData.exit` is false, the exit operation is skipped
     *         - if `removeAndRepayData.unlockData.unlock` is false, the unlock operation is skipped
     *         - if `removeAndRepayData.removeAssetFromSGL` is false, the removeAsset operation is skipped
     *         - if `!removeAndRepayData.assetWithdrawData.withdraw && removeAndRepayData.repayAssetOnBB`, the repay operation is performed
     *         - if `removeAndRepayData.removeCollateralFromBB` is false, the rmeove collateral is skipped
     *     - the helper can either stop at the remove asset from SGL step or it can continue until is removes & withdraws collateral from BB
     *         - removed asset can be withdrawn by providing `removeAndRepayData.assetWithdrawData`
     *     - BB collateral can be removed by providing `removeAndRepayData.collateralWithdrawData`
     */
    function exitPositionAndRemoveCollateral(ExitPositionAndRemoveCollateralData memory data) public payable {
        /**
         * @dev validate data
         */
        _validateExitPositionAndRemoveCollateral(data);

        /**
         * @dev performs a tOLP.unlock operation
         */
        if (data.removeAndRepayData.unlockData.unlock) {
            _unlock(data);
        }

        /**
         * @dev if `data.removeAndRepayData.removeAssetFromSGL` performs the follow operations:
         *          - removeAsset from SGL
         *          - if `data.removeAndRepayData.assetWithdrawData.withdraw` withdraws by using the `withdrawTo` operation
         */
        if (data.removeAndRepayData.removeAssetFromSGL) {
            ISingularity _singularity = ISingularity(data.externalData.singularity);

            // remove asset from SGL
            _singularityRemoveAsset(
                _singularity,
                data.removeAndRepayData.removeAmount,
                data.user,
                data.removeAndRepayData.assetWithdrawData.withdraw ? address(this) : data.user
            );

            //withdraw
            if (data.removeAndRepayData.assetWithdrawData.withdraw) {
                _withdrawHere(data.removeAndRepayData.assetWithdrawData, _singularity);
            }
        }

        /**
         * @dev performs a BigBang repay operation
         */
        if (!data.removeAndRepayData.assetWithdrawData.withdraw && data.removeAndRepayData.repayAssetOnBB) {
            _marketRepay(
                IMarket(data.externalData.bigBang),
                data.externalData.marketHelper,
                data.removeAndRepayData.repayAmount,
                data.user,
                data.user
            );
        }

        /**
         * @dev performs a BigBang removeCollateral operation and withdrawal if requested
         */
        if (data.removeAndRepayData.removeCollateralFromBB) {
            IMarket _bigBang = IMarket(data.externalData.bigBang);

            // remove collateral
            _marketRemoveCollateral(
                _bigBang,
                data.externalData.marketHelper,
                _bigBang.convertToShares(data.removeAndRepayData.collateralAmount),
                data.user,
                data.removeAndRepayData.collateralWithdrawData.withdraw ? address(this) : data.user
            );

            //withdraw
            if (data.removeAndRepayData.collateralWithdrawData.withdraw) {
                _withdrawHere(data.removeAndRepayData.collateralWithdrawData, _bigBang);
            }
        }
    }

    function _validateLock(LockData memory data) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkWhitelisted(data.magnetar);
        if (data.lockData.lock) {
            _checkWhitelisted(data.lockData.target);
            _checkWhitelisted(data.lockData.sglMarket);
            if (data.lockData.usdoAmount == 0) revert Magnetar_ActionParamsMismatch();
            if (data.lockData.to == address(0)) revert Magnetar_ActionParamsMismatch();
            if (data.lockData.to == address(this)) revert Magnetar_ActionParamsMismatch();
        }
    }

    function _validateExitPositionAndRemoveCollateral(ExitPositionAndRemoveCollateralData memory data) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkExternalData(data.externalData);
        _checkRemoveAndRepayData(data.removeAndRepayData);
    }

    function _checkExternalData(ICommonExternalContracts memory data) private view {
        _checkWhitelisted(data.marketHelper);
        _checkWhitelisted(data.magnetar);
        _checkWhitelisted(data.bigBang);
        _checkWhitelisted(data.singularity);
    }

    function _checkRemoveAndRepayData(IRemoveAndRepay memory data) private view {
        _checkWhitelisted(data.unlockData.target);
    }

    function _unlock(ExitPositionAndRemoveCollateralData memory data) private {
        // will be sent to `data.user` or `address(this)`
        address usdo = ITapiocaOptionBroker(data.removeAndRepayData.unlockData.target).getUSDO();
        uint256 usdoBefore = IERC20(usdo).balanceOf(address(this));
        ITapiocaOptionBroker(data.removeAndRepayData.unlockData.target).unlock(
            // from, # wip support unlock delegation at tob
            data.removeAndRepayData.unlockData.bucketId,
            data.removeAndRepayData.unlockData.to
        );
        uint256 usdoAfter = IERC20(usdo).balanceOf(address(this));
        if (usdoAfter - usdoBefore < data.removeAndRepayData.unlockData.amount) revert Magnetar_ActionParamsMismatch();
    }
}
