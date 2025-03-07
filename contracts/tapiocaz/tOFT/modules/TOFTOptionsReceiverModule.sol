// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// LZ
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

// External
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Tapioca
import {
    LockData,
    IMagnetar,
    MagnetarCall,
    MagnetarAction,
    IExerciseOptionsData
} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {IMagnetarOptionModule} from "tap-utils/interfaces/periph/IMagnetar.sol";
import {ITapiocaOptionBroker} from "tap-token/interfaces/ITapiocaOptionBroker.sol";
import {TOFTInitStruct, ExerciseOptionsMsg, LZSendParam} from "tap-utils/interfaces/oft/ITOFT.sol";
import {ITapiocaOmnichainEngine} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {SafeApprove} from "tap-utils/libraries/SafeApprove.sol";
import {TOFTMsgCodec} from "../libraries/TOFTMsgCodec.sol";
import {BaseTOFT} from "../BaseTOFT.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title TOFTOptionsReceiverModule
 * @author TapiocaDAO
 * @notice TOFT Options module
 */
contract TOFTOptionsReceiverModule is BaseTOFT {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    error TOFTOptionsReceiverModule_NotAuthorized(address invalidAddress);
    error TOFTOptionsReceiverModule_Reentrancy();

    event ExerciseOptionsReceived(
        address indexed user,
        address indexed target,
        uint256 indexed bucketId,
        uint256 paymentTokenAmount,
        address paymentTokenAddress
    );
    event LockReceived(
        address indexed user, address indexed srcChainSender, bool lock, address indexed lockTarget, uint256 usdoAmount
    );

    constructor(TOFTInitStruct memory _data) BaseTOFT(_data) {}

    /**
     * @notice Execute `magnetar.lockAndParticipate`
     * @dev Lock on tOB and/or participate on tOLP
     * @param srcChainSender The address of the sender on the source chain.
     * @param _data The call data containing info about the operation.
     * @param _data.user the user to perform the operation for
     * @param _data.tSglToken The address of the tOFT SGL token
     * @param _data.fraction the amount to lock
     * @param _data.lockData the data needed to lock on tOB
     * @param _data.participateData the data needed to participate on tOLP
     */
    function lockAndParticipateReceiver(address srcChainSender, bytes memory _data) public payable {
        // Decode receive message
        LockData memory msg_ = TOFTMsgCodec.decodeLockAndParticipateMsg(_data);

        /**
         * @dev validate data
         */
        msg_ = _validateLock(msg_, srcChainSender);

        /**
         * @dev execute through `Magnetar`
         */
        _lockAndParticipate(msg_);

        emit LockReceived(msg_.user, srcChainSender, msg_.lockData.lock, msg_.lockData.target, msg_.lockData.usdoAmount);
    }

    /**
     * @notice Exercise tOB option
     * @param srcChainSender The address of the sender on the source chain.
     * @param _data The call data containing info about the operation.
     *      - optionsData::address: TapiocaOptionsBroker exercise params.
     *      - lzSendParams::struct: LZ v2 send to source params.
     *      - composeMsg::bytes: Further compose data.
     */
    function exerciseOptionsReceiver(address srcChainSender, bytes memory _data) public payable {
        // Decode received message.
        ExerciseOptionsMsg memory msg_ = TOFTMsgCodec.decodeExerciseOptionsMsg(_data);

        /**
         * @dev validate data
         */
        msg_ = _validateExerciseOptionReceiver(msg_);

        /**
         * @dev Validate caller
         */
        _validateExerciseOptionCaller(msg_.optionsData, srcChainSender);

        /**
         * @dev retrieve paymentToken amount
         */
        _internalTransferWithAllowance(msg_.optionsData.from, srcChainSender, msg_.optionsData.paymentTokenAmount);

        /**
         * @dev call exerciseOption() with address(this) as the payment token
         */
        _approve(address(this), msg_.optionsData.target, msg_.optionsData.paymentTokenAmount);

        /**
         * @dev exercise and refund if less paymentToken amount was used
         */
        _exerciseAndRefund(msg_.optionsData);
        // _approve(address(this), address(pearl mit), 0);

        /**
         * @dev retrieve exercised amount
         */
        _withdrawExercised(msg_);

        emit ExerciseOptionsReceived(
            msg_.optionsData.from,
            msg_.optionsData.target,
            msg_.optionsData.bucketId,
            msg_.optionsData.paymentTokenAmount,
            msg_.optionsData.paymentToken
        );
    }

    function _validateLock(LockData memory msg_, address srcChainSender) private returns (LockData memory) {
        _checkWhitelistStatus(msg_.magnetar);
        if (msg_.lockData.lock) {
            _checkWhitelistStatus(msg_.lockData.target);
            if (msg_.lockData.usdoAmount > 0) {
                msg_.lockData.usdoAmount = _toLD(msg_.lockData.usdoAmount.toUint64());
                _validateAndSpendAllowance(msg_.user, srcChainSender, msg_.lockData.usdoAmount);
            }
        }

        return msg_;
    }

    function _lockAndParticipate(LockData memory msg_) private {
        bytes memory call = abi.encodeWithSelector(IMagnetarOptionModule.lockAndParticipate.selector, msg_);
        MagnetarCall[] memory magnetarCall = new MagnetarCall[](1);
        magnetarCall[0] =
            MagnetarCall({id: uint8(MagnetarAction.OptionModule), target: msg_.magnetar, value: msg.value, call: call});
        IMagnetar(payable(msg_.magnetar)).burst(magnetarCall);
    }

    function _validateExerciseOptionReceiver(ExerciseOptionsMsg memory msg_)
        private
        view
        returns (ExerciseOptionsMsg memory)
    {
        _checkWhitelistStatus(msg_.optionsData.target);

        if (msg_.optionsData.tapAmount > 0) {
            msg_.optionsData.tapAmount = _toLD(msg_.optionsData.tapAmount.toUint64());
        }

        if (msg_.optionsData.paymentTokenAmount > 0) {
            msg_.optionsData.paymentTokenAmount = _toLD(msg_.optionsData.paymentTokenAmount.toUint64());
        }

        return msg_;
    }

    function _exerciseAndRefund(IExerciseOptionsData memory _options) private {
        address paymentToken = _options.paymentToken;
        uint256 bBefore = IERC20(paymentToken).balanceOf(address(this));

        ITapiocaOptionBroker(_options.target).exerciseOption(
            _options.from,
            _options.bucketId,
            _options.paymentToken, //payment token
            _options.tapAmount
        );

        uint256 bAfter = IERC20(paymentToken).balanceOf(address(this));

        // Refund if less was used.
        if (bBefore >= bAfter) {
            uint256 diff = bBefore - bAfter;
            if (diff < _options.paymentTokenAmount) {
                IERC20(paymentToken).safeTransfer(_options.from, _options.paymentTokenAmount - diff);
            }
        }
    }

    /**
     *   @notice checks that the caller is allowed by the owner of the token
     */
    function _validateExerciseOptionCaller(IExerciseOptionsData memory _options, address _srcChainSender) internal {
        if (_options.from != _srcChainSender) {
            revert TOFTOptionsReceiverModule_NotAuthorized(_options.from);
        }
    }

    function _withdrawExercised(ExerciseOptionsMsg memory msg_) private {
        SendParam memory _send = msg_.lzSendParams.sendParam;

        address tapOft = ITapiocaOptionBroker(msg_.optionsData.target).getTapToken();
        uint256 tapBalance = IERC20(tapOft).balanceOf(address(this));
        if (msg_.withdrawOnOtherChain) {
            /// @dev determine the right amount to send back to source

            uint256 amountToSend = _send.amountLD > tapBalance ? tapBalance : _send.amountLD;
            if (_send.minAmountLD > amountToSend) {
                _send.minAmountLD = amountToSend;
            }
            _send.amountLD = amountToSend;

            msg_.lzSendParams.sendParam = _send;

            ITapiocaOmnichainEngine(tapOft).sendPacketFrom{value: msg.value}(
                msg_.optionsData.from, msg_.lzSendParams, ""
            );

            // Refund extra amounts
            if (tapBalance - amountToSend > 0) {
                IERC20(tapOft).safeTransfer(msg_.optionsData.from, tapBalance - amountToSend);
            }
        } else {
            //send on this chain
            IERC20(tapOft).safeTransfer(msg_.optionsData.from, tapBalance);
        }
    }

    function _checkWhitelistStatus(address _addr) private view {
        if (_addr != address(0)) {
            if (!getCluster().isWhitelisted(0, _addr)) {
                revert TOFTOptionsReceiverModule_NotAuthorized(_addr);
            }
        }
    }
}
