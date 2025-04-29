// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca
import {MagnetarAction, MagnetarModule, MagnetarCall} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {ITapiocaOmnichainEngine, LZSendParam} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {IMagnetarModuleExtender} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {IMagnetarHelper} from "tap-utils/interfaces/periph/IMagnetarHelper.sol";
import {ITapiocaOptionBroker} from "tap-token/interfaces/ITapiocaOptionBroker.sol";
import {IERC721Permit} from "tap-utils/interfaces/common/IERC721Permit.sol";
import {RevertMsgDecoder} from "tap-utils/libraries/RevertMsgDecoder.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";

import {IPermitAll} from "tap-utils/interfaces/common/IPermitAll.sol";
import {IWeth9} from "tap-utils/interfaces/external/weth/IWeth9.sol";
import {IMagnetar, IExerciseOptionsData} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

import {ITWTAPv2} from "tap-token/interfaces/ITWTAPv2.sol";
import {IPermit} from "tap-utils/interfaces/common/IPermit.sol";
import {SafeApprove} from "tap-utils/libraries/SafeApprove.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {ITOFT} from "tap-utils/interfaces/oft/ITOFT.sol";
import {BaseMagnetar} from "./BaseMagnetar.sol";
import {TapToken} from "../../tap-token/tokens/TapToken.sol";
/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title Magnetar
 * @author TapiocaDAO
 * @notice Magnetar helper contract
 * TODO: Do we need inherit ERC1155Holder?
 */
contract Magnetar is BaseMagnetar {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    error Magnetar_ValueMismatch(uint256 expected, uint256 received); // Value mismatch in the total value asked and the msg.value in burst
    error Magnetar_ActionNotValid(uint8 action, bytes actionCalldata); // Burst did not find what to execute
    error Magnetar_MarketOperationNotAllowed();

    constructor(
        ICluster _cluster,
        address _owner,
        address payable _collateralModule,
        address payable _mintModule,
        address payable _optionModule,
        address payable _leverageModule,
        address _magnetarHelper
    ) BaseMagnetar(_cluster,  _owner, _magnetarHelper) {
        modules[MagnetarModule.CollateralModule] = _collateralModule;
        modules[MagnetarModule.MintModule] = _mintModule;
        modules[MagnetarModule.OptionModule] = _optionModule;
        modules[MagnetarModule.LeverageModule] = _leverageModule;
    }

    /// =====================
    /// Public
    /// =====================
    /**
     * @notice Batch multiple calls together
     * @param calls The list of actions to perform
     */
    function burst(MagnetarCall[] calldata calls) external payable whenNotPaused {
        // @dev: make sure the current magnetar is whitelisted
        _checkWhitelisted(address(this));

        uint256 valAccumulator;

        uint256 length = calls.length;

        for (uint256 i; i < length; i++) {
            MagnetarCall calldata _action = calls[i];

            valAccumulator += _action.value;

            /// @dev Permit on an SGL/BB market
            if (_action.id == uint8(MagnetarAction.Permit)) {
                _processPermitOperation(_action.target, _action.call);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.TapLock)) {
                _processTapLockOperation(_action.target, _action.call, _action.value);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.TapUnlock)) {
                _processTapUnlockOperation(_action.target, _action.call, _action.value);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.TapBatchClaimRewards)) {
                _processTapBatchClaimRewardsOperation(_action.target, _action.call, _action.value);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.TapExtendLock)) {
                _processTapExtendLockOperation(_action.target, _action.call, _action.value);
                continue;
            }

            /// @dev Market singular operations
            if (_action.id == uint8(MagnetarAction.Market)) {
                _processMarketOperation(_action.target, _action.call, _action.value);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.ExerciseOption)) {
                _processExerciseOption(_action.target, _action.call, _action.value);
                continue;
            }

            /// @dev Modules will not return result data.
            if (_action.id == uint8(MagnetarAction.CollateralModule)) {
                _executeModule(MagnetarModule.CollateralModule, _action.call);
                continue;
            }

            /// @dev Modules will not return result data.
            if (_action.id == uint8(MagnetarAction.LeverageModule)) {
                _executeModule(MagnetarModule.LeverageModule, _action.call);
                continue;
            }

            /// @dev Modules will not return result data.
            if (_action.id == uint8(MagnetarAction.MintModule)) {
                _executeModule(MagnetarModule.MintModule, _action.call);
                continue;
            }

            /// @dev Modules will not return result data.
            if (_action.id == uint8(MagnetarAction.OptionModule)) {
                _executeModule(MagnetarModule.OptionModule, _action.call);
                continue;
            }

            if (_action.id == uint8(MagnetarAction.WethWrap)) {
                _processWethWrap(_action.target, _action.call, _action.value);
                continue;
            }

            // If no valid action was found, use the Magnetar module extender. Only if the action is valid.
            if (address(magnetarModuleExtender) != address(0) && magnetarModuleExtender.isValidActionId(_action.id)) {
                bytes memory callData = abi.encodeWithSelector(IMagnetarModuleExtender.handleAction.selector, _action);
                (bool success, bytes memory returnData) = address(magnetarModuleExtender).delegatecall(callData);
                if (!success) {
                    revert(RevertMsgDecoder._getRevertMsg(returnData));
                }
            } else {
                // If no valid action was found, revert
                revert Magnetar_ActionNotValid(_action.id, _action.call);
            }
        }

        if (msg.value != valAccumulator) revert Magnetar_ValueMismatch(msg.value, valAccumulator);
    }

    function _processTapExtendLockOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue)
        private
    {
        /**
         * @dev Executes the following:
         *      twTap.reuseParticipation(....)
         */
        bool selectorValidated = _validateTapExtendLockOperation(_target, _actionCalldata, _actionValue);
        if (selectorValidated) {
            _executeCall(_target, _actionCalldata, _actionValue);
            return;
        }
        revert Magnetar_ActionNotValid(uint8(MagnetarAction.TapExtendLock), _actionCalldata);
    }

    function _validateTapExtendLockOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue)
        private
        view
        returns (bool selectorValidated)
    {
        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        if (funcSig == ITWTAPv2.reuseParticipation.selector) {
            selectorValidated = true;
        }
    }

    function _processTapBatchClaimRewardsOperation(
        address _target,
        bytes calldata _actionCalldata,
        uint256 _actionValue
    ) private {
        /**
         * @dev Executes the following:
         *      twTap.batchClaimRewards(....)
         */
        bool selectorValidated = _validateTapBatchClaimRewardsOperation(_target, _actionCalldata, _actionValue);
        if (selectorValidated) {
            _executeCall(_target, _actionCalldata, _actionValue);
            return;
        }
        revert Magnetar_ActionNotValid(uint8(MagnetarAction.TapBatchClaimRewards), _actionCalldata);
    }

    function _validateTapBatchClaimRewardsOperation(
        address _target,
        bytes calldata _actionCalldata,
        uint256 _actionValue
    ) private view returns (bool selectorValidated) {
        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        if (funcSig == ITWTAPv2.batchClaimRewards.selector) {
            /// @dev Owner param check. See Warning above.
            _checkSender(abi.decode(_actionCalldata[4:36], (address)));
            selectorValidated = true;
        }

        return selectorValidated;
    }

    /// =====================
    /// Private
    /// =====================
    /**
     * @dev Process a permit operation, will only execute if the selector is allowed.
     * @dev !!! WARNING !!! Make sure to check the Owner param and check that function definition didn't change.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     */
    function _processPermitOperation(address _target, bytes calldata _actionCalldata) private {
        /**
         * @dev Executes the following:
         *      permit(address owner...)
         *      revoke(address owner...)
         *      permitAll(address from,..)
         *      revokeAll(address from,..)
         *      permitAction(uint8 action,address owner,...)
         */
        bool selectorValidated = _validatePermitOperation(_target, _actionCalldata);
        /// @dev no need to check the owner for the rest; it's using `msg.sender`
        if (selectorValidated) {
            // No need to send value on permit
            _executeCall(_target, _actionCalldata, 0);
            return;
        }
        revert Magnetar_ActionNotValid(uint8(MagnetarAction.Permit), _actionCalldata);
    }

    function _validatePermitOperation(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        selectorValidated = false;

        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        if (
            funcSig == IPermitAll.permitAll.selector || funcSig == IPermitAll.revokeAll.selector
                || funcSig == IPermit.permit.selector || funcSig == IPermit.revoke.selector
        ) {
            selectorValidated = true;
            /// @dev Owner param check. See Warning above.
            _checkSender(abi.decode(_actionCalldata[4:36], (address)));
        }

        // permitAction(uint8 action,address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r, bytes32 s);
        if (funcSig == IMarket.permitAction.selector) {
            selectorValidated = true;
            address _owner = abi.decode(_actionCalldata[36:68], (address));
            /// @dev Owner param check. See Warning above.
            _checkSender(_owner);
        }

        if (funcSig == IERC721Permit.permit.selector) {
            // check if `spender` is whitelisted
            _checkWhitelisted(abi.decode(_actionCalldata[4:36], (address)));

            // check if sender is owner of `tokenId`
            uint256 tokenId = abi.decode(_actionCalldata[36:68], (uint256));

            selectorValidated = IERC721(_target).ownerOf(tokenId) == msg.sender;
        }
    }

    /**
     * @dev Process a TOFT operation, will only execute if the selector is allowed.
     * @dev !!! WARNING !!! Make sure to check the Owner param and check that function definition didn't change.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processOFTOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue) private {
        /**
         * @dev Executes the following:
         *      wrap(address from,...)
         *      unwrap(address from,...)
         *      sendPacketFrom(...)
         */
        bool selectorValidated = _validateOFTOperation(_target, _actionCalldata);
        if (selectorValidated) {
            bytes4 funcSig = bytes4(_actionCalldata[:4]);
            if (funcSig == ITOFT.unwrap.selector) {
                (, uint256 _amount) = abi.decode(_actionCalldata[4:], (address, uint256));
                IERC20(_target).safeTransferFrom(msg.sender, address(this), _amount); //unwrap happens on `msg.sender`
            }
            if (funcSig == ITapiocaOmnichainEngine.sendPacketFrom.selector) {
                (, LZSendParam memory lzSendParam_,) = abi.decode(_actionCalldata[4:], (address, LZSendParam, bytes));
                uint256 amount_ = lzSendParam_.sendParam.amountLD;
                IERC20(_target).safeTransferFrom(msg.sender, address(this), amount_); //sendPacketFrom happens on msg.sender
            }

            _executeCall(_target, _actionCalldata, _actionValue);
            return;
        }

        revert Magnetar_ActionNotValid(uint8(MagnetarAction.OFT), _actionCalldata);
    }

    function _validateOFTOperation(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        selectorValidated = false;

        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        if (funcSig == ITOFT.wrap.selector) {
            selectorValidated = true;
            /// @dev Owner param check. See Warning above.
            _checkSender(abi.decode(_actionCalldata[4:36], (address)));
        }

        if (funcSig == ITOFT.unwrap.selector) {
            selectorValidated = true;
        }

        if (funcSig == ITapiocaOmnichainEngine.sendPacketFrom.selector) {
            selectorValidated = true;
            (address from_, LZSendParam memory lzSendParam_,) =
                abi.decode(_actionCalldata[4:], (address, LZSendParam, bytes));
            address owner_ = OFTMsgCodec.bytes32ToAddress(lzSendParam_.sendParam.to);
            _checkSender(owner_);
            _checkSender(from_);
        }
    }

    /**
     * @dev Process a market operation, will only execute if the selector is allowed.
     * @dev !!! WARNING !!! Make sure to check the Owner param and check that function definition didn't change.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processMarketOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue) private {
        /// @dev owner address should always be first param.
        bool selectorValidated = _validateMarketOperation(_target, _actionCalldata);

        if (selectorValidated) {
            bytes4 funcSig = bytes4(_actionCalldata[:4]);
            if (funcSig == ISingularity.addAsset.selector) {
                uint256 amount = abi.decode(_actionCalldata[68:100], (uint256));
                address user = abi.decode(_actionCalldata[36:68], (address));
                address asset = ISingularity(_target)._asset();

                IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
                IERC20(asset).safeApprove(address(_target), amount);

                bytes memory addAssetCalldata =
                    abi.encodeWithSelector(ISingularity.addAsset.selector, address(this), user, amount);

                _executeCallMemory(_target, addAssetCalldata, _actionValue);

                IERC20(ISingularity(_target)._asset()).safeApprove(address(_target), 0);
            } else if (funcSig == ISingularity.removeAsset.selector) {
                uint256 amount = abi.decode(_actionCalldata[68:100], (uint256));
                address user = abi.decode(_actionCalldata[36:68], (address));
                address asset = ISingularity(_target)._asset();

                _executeCallMemory(_target, _actionCalldata, _actionValue);
            } else {
                _executeCall(_target, _actionCalldata, _actionValue);
            }

            return;
        }
        revert Magnetar_ActionNotValid(uint8(MagnetarAction.Market), _actionCalldata);
    }

    function _validateMarketOperation(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        selectorValidated = false;

        _checkWhitelisted(_target);

        return true;
        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        // function addCollateral(address from, address to, bool skim, uint256 amount, uint256 share)
        // function removeCollateral(address from, address to, uint256 share)
        // function borrow(address from, address to, uint256 amount)
        // function repay(address from, address to, bool skim, uint256 part)
        // function buyCollateral(address from, uint256 borrowAmount, uint256 supplyAmount, bytes calldata data)
        // function sellCollateral(address from, uint256 share, bytes calldata data)
        if (funcSig == IMarket.execute.selector) {
            selectorValidated = true;
            (Module[] memory modules, bytes[] memory calls,) =
                abi.decode(_actionCalldata[4:], (Module[], bytes[], bool));
            // sanitize modules
            uint256 modulesLength;
            for (uint256 i; i < modulesLength; i++) {
                if (modules[i] == Module.Liquidation) revert Magnetar_MarketOperationNotAllowed();
            }

            // sanitize call
            uint256 callsLength = calls.length;
            for (uint256 i; i < callsLength; i++) {
                bytes memory _call = calls[i];

                address _from;
                assembly {
                    let dataPointer := add(_call, 0x24)
                    _from := mload(dataPointer)
                }
                _checkSender(_from);
            }
        }

        // function addAsset(address from, address to, uint256 share)
        // function removeAsset(address from, address to, uint256 fraction)
        if (funcSig == ISingularity.addAsset.selector || funcSig == ISingularity.removeAsset.selector) {
            selectorValidated = true;
            /// @dev Owner param check. See Warning above.
            _checkSender(abi.decode(_actionCalldata[4:36], (address)));
        }
    }

    /**
     * @notice DO NOT USE
     * @dev Used to generate ABI
     */
    function participate(address _participant, uint256 _amount, uint256 _duration, uint24 minMultiplierOut)
        external
        view
    {
        revert("DO NOT USE");
    }

    /**
     * @dev Process a TOB/TOLP/TWTAP lock operation, will only execute if the selector is allowed.
     * @dev !!! WARNING !!! Make sure to check the Owner param and check that function definition didn't change.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processTapLockOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue) private {
        /**
         * @dev Executes the following:
         *      ITapiocaOptionBroker.lock(....)
         *      ITWTAPv2.participate(....)
         */
        bool selectorValidated = _validateTapLockOperation(_target, _actionCalldata);
        bytes4 funcSig = bytes4(_actionCalldata[:4]);

        if (selectorValidated) {
            // Token is sent to the owner after execute
            if (funcSig == ITWTAPv2.participate.selector) {
                (address _participant, uint256 _amount, uint8 _bucketId) =
                    abi.decode(_actionCalldata[4:], (address, uint256, uint8));

                _executeCallMemory(
                    _target,
                    abi.encodeWithSelector(ITWTAPv2.participate.selector, _participant, _amount, _bucketId),
                    _actionValue
                );

                return;
            }
        }
        if (funcSig == ITapiocaOptionBroker.lock.selector) {
            (address _to, uint8 _bucketId, uint256 _usdoAmount, address _market) =
                abi.decode(_actionCalldata[4:], (address, uint8, uint256, address));
            
            address usdo = ITapiocaOptionBroker(_target).getUSDO();
            IERC20(usdo).safeTransferFrom(msg.sender, address(this), _usdoAmount);
            IERC20(usdo).safeApprove(address(_target), _usdoAmount);

            _executeCallMemory(
                _target,
                abi.encodeWithSelector(ITapiocaOptionBroker.lock.selector, _to, _bucketId, _usdoAmount, _market),
                _actionValue
            );

            return;
        }

        revert Magnetar_ActionNotValid(uint8(MagnetarAction.TapLock), _actionCalldata);
    }

    function _validateTapLockOperation(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        selectorValidated = false;

        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        if (funcSig == ITapiocaOptionBroker.lock.selector || funcSig == ITWTAPv2.participate.selector) {
            _checkSender(abi.decode(_actionCalldata[4:36], (address)));
            selectorValidated = true;
        }
    }

    /**
     * @dev Process a TOB/TOLP/TWTAP unlock operation, will only execute if the selector is allowed.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processTapUnlockOperation(address _target, bytes calldata _actionCalldata, uint256 _actionValue)
        private
    {
        /**
         * @dev Executes the following:
         *      twTap.exitPosition(....)
         *      tOB.exitPosition(....)
         *      tOLP.unlock(....)
         */
        bool selectorValidated = _validateTapUnlockOperation(_target, _actionCalldata);

        /// @dev No need to check owner as anyone can unlock twTap/tOB/tOLP positions by design.
        /// Owner of the token receives the unlocked tokens.
        if (selectorValidated) {
            _executeCall(_target, _actionCalldata, _actionValue);
            return;
        }
        revert Magnetar_ActionNotValid(uint8(MagnetarAction.TapUnlock), _actionCalldata);
    }

    function _validateTapUnlockOperation(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        _checkWhitelisted(_target);

        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        selectorValidated = funcSig == ITWTAPv2.exitPosition.selector || funcSig == ITapiocaOptionBroker.unlock.selector;
    }

    /**
     * @dev Process a TOB exerciseOption operation, will only execute if the selector is allowed.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processExerciseOption(address _target, bytes calldata _actionCalldata, uint256 _actionValue) private {
        /**
         * @dev Executes the following:
         *      tOB.exerciseOption(....)
         */
        {
            bool selectorValidated = _validateExerciseOption(_target, _actionCalldata);
            if (!selectorValidated) {
                revert Magnetar_ActionNotValid(uint8(MagnetarAction.Market), _actionCalldata);
            }
        }
        // Skip the first 4 bytes (function selector) and decode the parameters
        IExerciseOptionsData memory data = abi.decode(_actionCalldata[4:], (IExerciseOptionsData));

        address tapToken = ITapiocaOptionBroker(_target).getTapToken();

        // transfer `paymentToken` here
        IERC20(data.paymentToken).safeTransferFrom(msg.sender, address(this), data.paymentTokenAmount);

        uint256 tapAmountBefore = IERC20(tapToken).balanceOf(address(this));

        bytes memory exerciseOptionCalldata = abi.encodeWithSelector(
            ITapiocaOptionBroker.exerciseOption.selector,
            data.from,
            uint256(data.bucketId),
            data.paymentToken,
            data.tapAmount
        );

        // execute
        IERC20(data.paymentToken).safeApprove(address(_target), data.paymentTokenAmount);
        _executeCall(_target, exerciseOptionCalldata, _actionValue);

        uint256 tapAmountAfter = IERC20(tapToken).balanceOf(address(this));

        if (tapAmountAfter - tapAmountBefore == 0) {
            revert("exerciseOption failed");
        }

        IERC20(tapToken).safeTransfer(msg.sender, tapAmountAfter - tapAmountBefore);
    }

    function _validateExerciseOption(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        _checkWhitelisted(_target);
        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        selectorValidated = funcSig == ITapiocaOptionBroker.exerciseOption.selector;
    }

    /**
     * @dev Process a weth wrap, will only execute if the selector is allowed.
     *
     * @param _target The contract address to call.
     * @param _actionCalldata The calldata to send to the target.
     * @param _actionValue The value to send with the call.
     */
    function _processWethWrap(address _target, bytes calldata _actionCalldata, uint256 _actionValue) private {
        {
            bool selectorValidated = _validateWethWrap(_target, _actionCalldata);
            if (!selectorValidated) {
                revert Magnetar_ActionNotValid(uint8(MagnetarAction.WethWrap), _actionCalldata);
            }
        }

        // wrap and transfer to sender
        IWeth9(_target).deposit{value: _actionValue}();
        IERC20(_target).safeTransfer(msg.sender, _actionValue);
    }

    function _validateWethWrap(address _target, bytes calldata _actionCalldata)
        private
        view
        returns (bool selectorValidated)
    {
        _checkWhitelisted(_target);
        bytes4 funcSig = bytes4(_actionCalldata[:4]);
        selectorValidated = funcSig == IWeth9.deposit.selector;
    }

    /**
     * @dev Executes a call to an address, optionally reverting on failure. Make sure to sanitize prior to calling.
     */
    function _executeCall(address _target, bytes memory _actionCalldata, uint256 _actionValue)
        private
        returns (bytes memory returnData)
    {
        bool success;
        (success, returnData) = _target.call{value: _actionValue}(_actionCalldata);

        if (!success) {
            revert(RevertMsgDecoder._getRevertMsg(returnData));
        }
    }

    /**
     * @dev Executes a call to an address, optionally reverting on failure. Make sure to sanitize prior to calling.
     * @dev This uses memory
     */
    function _executeCallMemory(address _target, bytes memory _actionCalldata, uint256 _actionValue)
        private
        returns (bytes memory returnData)
    {
        bool success;
        (success, returnData) = _target.call{value: _actionValue}(_actionCalldata);

        if (!success) {
            revert(RevertMsgDecoder._getRevertMsg(returnData));
        }
    }
}
