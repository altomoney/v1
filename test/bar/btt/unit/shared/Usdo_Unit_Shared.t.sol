// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// LZ
import {
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

import {IUsdo} from "tapioca-bar/usdo/IUsdo.sol";
import {Usdo} from "tapioca-bar/usdo/Usdo.sol";

import {ICommonExternalContracts} from "tap-utils/interfaces/common/ICommonData.sol";
import {
    MagnetarWithdrawData,
    IExerciseOptionsData,
    IOptionsLockData,
    IOptionsUnlockData,
    MarketLendOrRepayMsg,
    MarketRemoveAssetMsg,
    IRemoveAndRepay,
    ILendOrRepayParams
} from "tap-utils/interfaces/periph/IMagnetar.sol";

import {
    TapiocaOmnichainEngineHelper,
    PrepareLzCallData,
    PrepareLzCallReturn,
    ComposeMsgData,
    LZSendParam,
    RemoteTransferMsg
} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";
import {ERC20PermitStruct, ERC20PermitApprovalMsg, MarketPermitActionMsg} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";

// tests
import {Base_Test} from "../../Base_Test.t.sol";

import "forge-std/console.sol";

abstract contract Usdo_Unit_Shared is Base_Test {
    // ************ //
    // *** VARS *** //
    // ************ //
    TapiocaOmnichainEngineHelper tapiocaOmnichainEngineHelper;

    struct LzOFTComposedData {
        uint16 msgType;
        bytes32 guid;
        bytes composeMsg;
        uint32 dstEid;
        address from;
        address to;
        address srcMsgSender;
        bytes extraOptions;
    }

    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public virtual override {
        super.setUp();

        tapiocaOmnichainEngineHelper = new TapiocaOmnichainEngineHelper();
        vm.label(address(tapiocaOmnichainEngineHelper), "tapiocaOmnichainEngineHelper");
    }

    // **************** //
    // *** INTERNAL *** //
    // **************** //
    function _tryCreateUsdo(
        bool shouldRevert,
        address _sender,
        address _receiver,
        address _marketReceiver,
        address _optionReceiver
    ) internal {
        if (shouldRevert) {
            vm.expectRevert();
        }
        usdo = new Usdo(address(endpoints[aEid]), address(this), address(cluster));
    }

    struct _LendOrRepayInternal {
        bool repay;
        bool lock;
        bool participate;
        bool removeCollateral;
        uint256 repayAmount;
        uint256 depositAmount;
        address magnetar;
        address marketHelper;
        address market;
        uint256 removeCollateralAmount;
        address lockDataTarget;
        address participateDataTarget;
    }

    function _createMinimalLendOrRepayMsg(_LendOrRepayInternal memory data)
        internal
        view
        returns (MarketLendOrRepayMsg memory marketMsg)
    {
        uint256 _depositAmountSD = tapiocaOmnichainEngineHelper.toSD(data.depositAmount, usdo.decimalConversionRate());
        uint256 _repayAmountSD = tapiocaOmnichainEngineHelper.toSD(data.repayAmount, usdo.decimalConversionRate());
        uint256 _removeCollateralAmountSD = tapiocaOmnichainEngineHelper.toSD(data.removeCollateralAmount, usdo.decimalConversionRate());

        marketMsg = MarketLendOrRepayMsg({
            user: address(this),
            lendParams: ILendOrRepayParams({
                repay: data.repay,
                depositAmount: _depositAmountSD,
                repayAmount: _repayAmountSD,
                magnetar: data.magnetar,
                marketHelper: data.marketHelper,
                market: data.market,
                removeCollateral: data.removeCollateral,
                removeCollateralAmount: _removeCollateralAmountSD,
                lockData: IOptionsLockData({
                    lock: data.lock,
                    target: data.lockDataTarget,
                    to: address(this),
                    sglMarket: address(0),
                    usdoAmount: 0,
                    bucketId: 0
                })
            }),
            withdrawParams: MagnetarWithdrawData({
                asset: address(0),
                unwrap: false,
                amount: 0,
                withdraw: false,
                receiver: address(this),
                extractFromSender: false
            }),
            value: 0
        });
    }

    struct _RemoveAssetInternal {
        address magnetar;
        address marketHelper;
        address market;
        address bb;
        uint256 removeAmount;
        uint256 repayAmount;
        uint256 removeCollateralAmount;
    }

    function _createMinimalRemoveAssetMsg(_RemoveAssetInternal memory data)
        internal
        view
        returns (MarketRemoveAssetMsg memory marketMsg)
    {
        uint256 _removeAmountSD = tapiocaOmnichainEngineHelper.toSD(data.removeAmount, usdo.decimalConversionRate());
        uint256 _repayAmountSD = tapiocaOmnichainEngineHelper.toSD(data.repayAmount, usdo.decimalConversionRate());
        uint256 _removeCollateralAmountSD = tapiocaOmnichainEngineHelper.toSD(data.removeCollateralAmount, usdo.decimalConversionRate());

        console.log("-------- _removeAmountSD            %s", _removeAmountSD);
        console.log("-------- _repayAmountSD             %s", _repayAmountSD);
        console.log("-------- _removeCollateralAmountSD  %s", _removeCollateralAmountSD);
        marketMsg = MarketRemoveAssetMsg({
            user: address(this),
            externalData: ICommonExternalContracts({
                magnetar: data.magnetar,
                singularity: data.market,
                bigBang: data.bb,
                marketHelper: data.marketHelper
            }),
            removeAndRepayData: IRemoveAndRepay({
                removeAssetFromSGL: true,
                removeAmount: _removeAmountSD,
                repayAssetOnBB: data.repayAmount > 0,
                repayAmount: _repayAmountSD,
                removeCollateralFromBB: data.removeCollateralAmount > 0,
                collateralAmount: _removeCollateralAmountSD,
                unlockData: IOptionsUnlockData({unlock: false, target: address(0), bucketId: 0, to: address(this), amount: 0}),
                assetWithdrawData: MagnetarWithdrawData({
                    asset: address(0),
                    unwrap: false,
                    amount: 0,
                    withdraw: false,
                    receiver: address(this),
                    extractFromSender: false
                }),
                collateralWithdrawData: MagnetarWithdrawData({
                    asset: address(0),
                    unwrap: false,
                    amount: 0,
                    withdraw: false,
                    receiver: address(this),
                    extractFromSender: false
                })
            }),
            value: 0
        });
    }


    // *** Crosschain helpers *** //
    function __callLzCompose(LzOFTComposedData memory _lzOFTComposedData) internal {
        vm.expectEmit(true, true, true, false);
        emit ComposeReceived(_lzOFTComposedData.msgType, _lzOFTComposedData.guid, _lzOFTComposedData.composeMsg);

        this.lzCompose(
            _lzOFTComposedData.dstEid,
            _lzOFTComposedData.from,
            _lzOFTComposedData.extraOptions,
            _lzOFTComposedData.guid,
            _lzOFTComposedData.to,
            _lzOFTComposedData.composeMsg
        );
    }
}
