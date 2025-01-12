// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca
import {ITapiocaOptionBroker} from "tap-utils/interfaces/tap-token/ITapiocaOptionBroker.sol";
import {MintFromBBAndLendOnSGLData} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {ITapiocaOption} from "tap-utils/interfaces/tap-token/ITapiocaOption.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {ITOFT} from "tap-utils/interfaces/oft/ITOFT.sol";
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
 * @title MagnetarMintModule
 * @author TapiocaDAO
 * @notice Magnetar BigBang related operations
 */
contract MagnetarMintModule is MagnetarBaseModule {
    using SafeCast for uint256;

    error MagnetarMintModule_LockTransferFailed();
    error MagnetarMintModule_ParticipateTransferFailed();

    constructor(address _toeHelper) MagnetarBaseModule(_toeHelper) {}
    /// =====================
    /// Public
    /// =====================
    /**
     * @notice helper to deposit mint from BB, lend on SGL, lock on tOLP and participate on tOB on the current chain
     * @dev all steps are optional:
     *         - if `mintData.mint` is false, the mint operation on BB is skipped
     *             - add BB collateral to YB, add collateral on BB and borrow from BB are part of the mint operation
     *         - if `depositData.deposit` is false, the asset deposit to YB is skipped
     *         - if `lendAmount == 0` the addAsset operation on SGL is skipped
     *             - if `mintData.mint` is true, `lendAmount` will be automatically filled with the minted value
     *         - if `lockData.lock` is false, the tOLP lock operation is skipped
     *         - if `participateData.participate` is false, the tOB participate operation is skipped
     *
     * @param data.user the user to perform the operation for
     * @param data.lendAmount the amount to lend on SGL
     * @param data.mintData the data needed to mint on BB
     * @param data.depositData the data needed for asset deposit
     * @param data.lockData the data needed to lock on TapiocaOptionLiquidityProvision
     * @param data.participateData the data needed to perform a participate operation on TapiocaOptionsBroker
     * @param data.externalContracts the contracts' addresses used in all the operations performed by the helper
     */

    function mintBBLendSGLLockTOLP(MintFromBBAndLendOnSGLData memory data) public payable {
        /**
         * @dev validate data
         */
        _validatemintBBLendSGLLockTOLPData(data);

        /**
         * @dev if `mint` was requested the following actions are performed:
         *      - extracts & deposits collateral to YB
         *      - performs bigBang_.addCollateral
         *      - performs bigBang_.borrow
         */
        if (data.mintData.mint && data.externalContracts.bigBang != address(0)) {
            _depositAddCollateralAndMintFromBigBang(data);
        }

        /**
         * @dev if `depositData.deposit`:
         *          - deposit SGL asset to YB for `data.user`
         */
        if (data.depositData.deposit) {
            IMarket _singularity = IMarket(data.externalContracts.singularity);

            address assetAddress = _singularity.collateral();

            data.depositData.amount = _extractTokens(data.user, assetAddress, data.depositData.amount);
            _depositToMarket(_singularity, data.user, data.depositData.amount);
        }

        /**
         * @dev if `lendAmount` > 0:
         *          - add asset to SGL
         */
        uint256 fraction;
        if (data.lendAmount > 0) {
            fraction = _singularityAddAsset(
                ISingularity(data.externalContracts.singularity), data.lendAmount, data.user, data.user
            );
        }

        /**
         * @dev if `lockData.lock`:
         *          - transfer `fraction` from data.user to `address(this)
         *          - deposits `fraction` to YB for `address(this)`
         *          - performs tOLP.lock
         */
        uint256 tOLPTokenId;
        if (data.lockData.lock) {
            tOLPTokenId = _lock(data, fraction, data.participateData.participate);
        }

        /**
         * @dev if `participateData.participate`:
         *          - verify tOLPTokenId
         *          - performs tOB.participate
         *          - transfer `oTAPTokenId` to data.user
         */
        if (data.participateData.participate) {
            _participate(data, tOLPTokenId, data.lockData.lock);
        }
    }

    /// =====================
    /// Private
    /// =====================
    function _validatemintBBLendSGLLockTOLPData(MintFromBBAndLendOnSGLData memory data) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkWhitelisted(data.externalContracts.magnetar);
        _checkWhitelisted(data.externalContracts.singularity);
        _checkWhitelisted(data.externalContracts.bigBang);
        _checkWhitelisted(data.externalContracts.marketHelper);
        _checkWhitelisted(data.lockData.target);
        _checkWhitelisted(data.lockData.tAsset);
        _checkWhitelisted(data.participateData.target);
    }

    function _depositAddCollateralAndMintFromBigBang(MintFromBBAndLendOnSGLData memory data) private {
        IMarket _bigBang = IMarket(data.externalContracts.bigBang);
        uint256 _share = _bigBang.convertToShares(data.mintData.collateralDepositData.amount);

        /**
         * @dev try deposit
         */
        if (data.mintData.collateralDepositData.deposit) {
            address bbCollateralAddress = _bigBang.collateral();
            data.mintData.collateralDepositData.amount =
                _extractTokens(data.user, bbCollateralAddress, data.mintData.collateralDepositData.amount);
            _depositToMarket(_bigBang, data.user, data.mintData.collateralDepositData.amount);
        }

        /**
         * @dev try to add collateral
         *      `data.mintData.collateralDepositData.deposit` might be false and deposit is skipped, but
         *          `data.mintData.collateralDepositData.amount` can be > 0, which assumes that an `.addCollateral` operation is performed
         */
        if (data.mintData.collateralDepositData.amount > 0) {
            _marketAddCollateral(_bigBang, data.externalContracts.marketHelper, _share, data.user, data.user);
        }

        /**
         * @dev try borrow from BigBang
         */
        if (data.mintData.mintAmount > 0) {
            _share = _bigBang.convertToShares(data.mintData.mintAmount);
            _marketBorrow(_bigBang, data.externalContracts.marketHelper, data.mintData.mintAmount, data.user, data.user);
        }
    }

    struct LockParams {
        IMarket singularity;
        uint256 tOLPSglAssetId;
        uint256 fraction;
        bool participate;
    }

    function _lock(MintFromBBAndLendOnSGLData memory data, uint256 fraction, bool participate)
        private
        returns (uint256 tOLPTokenId)
    {
        /*
        LockParams memory params;
        params.singularity = IMarket(data.externalContracts.singularity);
        params.participate = participate;

        // use requested value
        if (data.lockData.fraction > 0) {
            fraction = data.lockData.fraction;
        } else {
            revert Magnetar_ActionParamsMismatch();
        }
        // retrieve and deposit SGLAssetId registered in tOLP
        (params.tOLPSglAssetId,,,) =
            ITapiocaOptionLiquidityProvision(data.lockData.target).activeSingularities(data.lockData.tAsset);

        // Extract SGL tokens
        fraction = _extractTokens(data.user, data.externalContracts.singularity, fraction);

        // Wrap SGL tokens into tSgl
        IERC20(address(params.singularity)).approve(address(pearl mit), fraction);
        pear lmit.approve(
            20, address(params.singularity), 0, data.lockData.tAsset, fraction.toUint200(), block.timestamp.toUint48()
        );

        params.fraction = fraction;

        return _wrapAndLock(data, params);
        */
    }

    function _wrapAndLock(MintFromBBAndLendOnSGLData memory data, LockParams memory params)
        private
        returns (uint256 tOLPTokenId)
    {
        /*
        uint256 wrapped = ITOFT(data.lockData.tAsset).wrap(address(this), address(this), params.fraction);
        ITapiocaOptionLiquidityProvision tOLP = ITapiocaOptionLiquidityProvision(data.lockData.target);

        // deposit YB and revoke approval
        IERC20(address(params.singularity)).approve(address(pearl mit), 0);
        data.lockData.amount = obtainedShares.toUint128();
        return tOLP.lock(
            params.participate ? address(this) : data.user,
            data.lockData.tAsset,
            data.lockData.lockDuration,
            data.lockData.amount,
            msg.sender
        );
        */
    }

    function _participate(MintFromBBAndLendOnSGLData memory data, uint256 tOLPTokenId, bool lock) private {
        // validate token ids
        /*
        if (tOLPTokenId == 0 && data.participateData.tOLPTokenId == 0) revert Magnetar_ActionParamsMismatch();
        if (
            data.participateData.tOLPTokenId != tOLPTokenId && tOLPTokenId != 0 && data.participateData.tOLPTokenId != 0
        ) {
            revert Magnetar_tOLPTokenMismatch();
        }

        if (data.participateData.tOLPTokenId != 0) tOLPTokenId = data.participateData.tOLPTokenId;

        // transfer NFT here
        if (!lock) {
            bool isErr = pearl mit.transferFromERC721(data.user, address(this), data.lockData.target, tOLPTokenId);
            if (isErr) revert Magnetar_ExtractTokenFail();
        }

        pear lmit.approve(
            721, data.lockData.target, tOLPTokenId, data.participateData.target, 1, block.timestamp.toUint48()
        );
        IERC721(data.lockData.target).approve(address(pear lmit), tOLPTokenId);
        uint256 oTAPTokenId = ITapiocaOptionBroker(data.participateData.target).participate(tOLPTokenId, 0);

        address oTapAddress = ITapiocaOptionBroker(data.participateData.target).oTAP();
        IERC721(oTapAddress).safeTransferFrom(address(this), data.user, oTAPTokenId);
        }
        */
    }
}
