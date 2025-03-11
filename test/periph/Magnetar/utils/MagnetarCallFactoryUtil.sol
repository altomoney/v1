// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {MagnetarCollateralModule} from "../../../../contracts/periph/Magnetar/modules/MagnetarCollateralModule.sol";
import {
    MagnetarLeverageModule,
    BuyCollateralData,
    SellCollateralData
} from "../../../../contracts/periph/Magnetar/modules/MagnetarLeverageModule.sol";
import {
    MagnetarAction,
    MagnetarCall,
    DepositAddCollateralAndBorrowFromMarketData,
    DepositRepayAndRemoveCollateralFromMarketData,
    IExerciseOptionsData
} from "../../../../contracts/utils/interfaces/periph/IMagnetar.sol";
import {Singularity} from "../../../../contracts/bar/markets/singularity/Singularity.sol";
import {SGLCollateral} from "../../../../contracts/bar/markets/singularity/SGLCollateral.sol";
import {SGLLeverage} from "../../../../contracts/bar/markets/singularity/SGLLeverage.sol";
import {TwTAP} from "tap-token/governance/twTAP.sol";
import {TapToken} from "../../../../contracts/tap-token/tokens/TapToken.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Market4626PermitUtils} from "./Market4626PermitUtils.t.sol";
import {MarketERC4626} from "../../../../contracts/bar/markets/MarketERC4626.sol";
import {SLeverageSwapData, SToftInfo} from "../../../../contracts/bar/markets/leverage/BaseLeverageExecutor.sol";
import {TapiocaOptionBroker} from "../../../../contracts/tap-token/options/TapiocaOptionBroker.sol";

abstract contract MagnetarCallFactoryUtil is Market4626PermitUtils {
    function _getTwTapBatchClaimRewardsMagnetarCall(address _twTap, address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        uint256[] memory _bucketIds = new uint256[](1);
        _bucketIds[0] = _bucketId;
        bytes memory twTapCallData = abi.encodeWithSelector(TwTAP.batchClaimRewards.selector, _participant, _bucketIds);
        return MagnetarCall({
            id: uint8(MagnetarAction.TapBatchClaimRewards),
            target: address(_twTap),
            value: 0,
            call: twTapCallData
        });
    }

    function _getTwTapReuseParticipationMagnetarCall(address _twTap, address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData = abi.encodeWithSelector(TwTAP.reuseParticipation.selector, _participant, _bucketId);
        return MagnetarCall({
            id: uint8(MagnetarAction.TapExtendLock),
            target: address(_twTap),
            value: 0,
            call: twTapCallData
        });
    }

    function _getTwTapExitPositionMagnetarCall(address _twTap, address _participant, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData =
            abi.encodeWithSelector(TwTAP.exitPosition.selector, _participant, _participant, _bucketId);
        return
            MagnetarCall({id: uint8(MagnetarAction.TapUnlock), target: address(_twTap), value: 0, call: twTapCallData});
    }

    function _getTwTapParticipateMagnetarCall(address _twTap, address _participant, uint256 _amount, uint8 _bucketId)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory twTapCallData =
            abi.encodeWithSelector(TwTAP.participate.selector, _participant, _amount, _bucketId);
        return MagnetarCall({id: uint8(MagnetarAction.TapLock), target: address(_twTap), value: 0, call: twTapCallData});
    }

    function _getTOBLockMagnetarCall(address _tob, address _to, uint8 _bucketId, uint256 _usdoAmount, address _market)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory tobCallData =
            abi.encodeWithSelector(TapiocaOptionBroker.lock.selector, _to, _bucketId, _usdoAmount, _market);
        return MagnetarCall({id: uint8(MagnetarAction.TapLock), target: address(_tob), value: 0, call: tobCallData});
    }

    function _getTOBUnlockMagnetarCall(address _tob, uint8 bucketId, address to)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory tobCallData = abi.encodeWithSelector(TapiocaOptionBroker.unlock.selector, bucketId, to);
        return MagnetarCall({id: uint8(MagnetarAction.TapUnlock), target: address(_tob), value: 0, call: tobCallData});
    }

    function _getTOBExerciseOptionMagnetarCall(
        address _tob,
        address _user,
        uint8 _bucketId,
        address _paymentToken,
        uint256 _paymentTokenAmount,
        uint256 _tapAmount
    ) internal view returns (MagnetarCall memory) {
        /*
            address from;
            address target;
            address paymentToken;
            uint256 paymentTokenAmount;
            uint256 tapAmount;
            uint8 bucketId;
        */
        IExerciseOptionsData memory _params;
        _params.from = _user;
        _params.target = address(_tob);
        _params.paymentToken = _paymentToken;
        _params.paymentTokenAmount = _paymentTokenAmount;
        _params.bucketId = _bucketId;
        _params.tapAmount = _tapAmount;
        bytes memory tobCallData = abi.encodeWithSelector(TapiocaOptionBroker.exerciseOption.selector, _params);
        return
            MagnetarCall({id: uint8(MagnetarAction.ExerciseOption), target: address(_tob), value: 0, call: tobCallData});
    }

    function _getMarketAddAssetMagnetarCall(address _market, address _from, address _to, uint256 _amount)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory marketCallData = abi.encodeWithSelector(Singularity.addAsset.selector, _from, _to, _amount);
        return MagnetarCall({id: uint8(MagnetarAction.Market), target: _market, value: 0, call: marketCallData});
    }

    function _getMarketAddCollateralMagnetarCall(address _market, address _marketHelper, address _user, uint256 _amount)
        internal
        view
        returns (MagnetarCall memory)
    {
        /*
    address market;
    address marketHelper;
    address user;
    uint256 collateralAmount;
    uint256 borrowAmount;
    bool deposit;
    MagnetarWithdrawData withdrawParams;
        */
        DepositAddCollateralAndBorrowFromMarketData memory _params;
        _params.collateralAmount = _amount;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;

        return _getMagnetarCollateralModuleDepositAddCollateralAndBorrowFromMarketMagnetarCall(_market, _params);
    }

    function _getMarketAddCollateral_BorrowMagnetarCall(
        address _market,
        address _marketHelper,
        address _user,
        uint256 _amount,
        uint256 _borrowAmount
    ) internal view returns (MagnetarCall memory) {
        /*
    address market;
    address marketHelper;
    address user;
    uint256 collateralAmount;
    uint256 borrowAmount;
    bool deposit;
    MagnetarWithdrawData withdrawParams;
        */
        DepositAddCollateralAndBorrowFromMarketData memory _params;
        _params.collateralAmount = _amount;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;
        _params.borrowAmount = _borrowAmount;
        return _getMagnetarCollateralModuleDepositAddCollateralAndBorrowFromMarketMagnetarCall(_market, _params);
    }

    function _getMarketRepayMagnetarCall(address _market, address _marketHelper, address _user, uint256 _repayAmount)
        internal
        view
        returns (MagnetarCall memory)
    {
        /*
    address market;
    address marketHelper;
    address user;
    uint256 depositAmount;
    uint256 repayAmount;
    uint256 collateralAmount;
    MagnetarWithdrawData withdrawCollateralParams;
        */
        DepositRepayAndRemoveCollateralFromMarketData memory _params;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;
        _params.repayAmount = _repayAmount;
        return _getMarketDepositRepayAndRemoveCollateralFromMarketMagnetarCall(_market, _params);
    }

    function _getMarketRepayAndWithdrawCollateralMagnetarCall(
        address _market,
        address _marketHelper,
        address _user,
        uint256 _repayAmount,
        uint256 _withdrawCollateralAmount
    ) internal view returns (MagnetarCall memory) {
        /*
    address market;
    address marketHelper;
    address user;
    uint256 depositAmount;
    uint256 repayAmount;
    uint256 collateralAmount;
    MagnetarWithdrawData withdrawCollateralParams;
        */
        DepositRepayAndRemoveCollateralFromMarketData memory _params;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;
        _params.repayAmount = _repayAmount;
        _params.collateralAmount = _withdrawCollateralAmount;

        return _getMarketDepositRepayAndRemoveCollateralFromMarketMagnetarCall(_market, _params);
    }

    function _getMarketDepositRepayAndRemoveCollateralFromMarketMagnetarCall(
        address _market,
        DepositRepayAndRemoveCollateralFromMarketData memory _params
    ) private view returns (MagnetarCall memory) {
        bytes memory depositRepayAndRemoveCollateralFromMarketCallData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositRepayAndRemoveCollateralFromMarket.selector, _params);
        return MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(0x0),
            value: 0,
            call: depositRepayAndRemoveCollateralFromMarketCallData
        });
    }

    function _getMarketRemoveAssetMagnetarCall(address _market, address _from, address _to, uint256 _amount)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory marketCallData = abi.encodeWithSelector(Singularity.removeAsset.selector, _from, _to, _amount);
        return MagnetarCall({id: uint8(MagnetarAction.Market), target: _market, value: 0, call: marketCallData});
    }

    function _getERC20PermitMagnetarCall(
        address payable _permitToken,
        uint256 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset
    ) internal view returns (MagnetarCall memory) {
        address _owner = vm.addr(_ownerPk);
        ERC20PermitStruct memory _permitStruct = ERC20PermitStruct({
            owner: _owner,
            spender: _spender,
            value: _amount,
            nonce: IERC20Permit(_permitToken).nonces(_owner),
            deadline: block.timestamp + _deadlineOffset
        });
        bytes32 _digest = ERC20Mock(_permitToken).getTypedDataHash(_permitStruct);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_ownerPk, _digest);
        bytes memory permitCallData = abi.encodeWithSelector(
            IERC20Permit.permit.selector,
            _permitStruct.owner,
            _permitStruct.spender,
            _permitStruct.value,
            _permitStruct.deadline,
            v,
            r,
            s
        );
        return MagnetarCall({id: uint8(MagnetarAction.Permit), target: _permitToken, value: 0, call: permitCallData});
    }

    function _getMarketPermitMarketSharesMagnetarCall(
        address _market,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) internal returns (MagnetarCall memory) {
        MarketERC4626.PermitActions _action = MarketERC4626.PermitActions.VAULT_ERC4626_TRANSFER;
        return
            _getMarketPermitActionMagnetarCall(_market, _action, _ownerPk, _spender, _amount, _deadlineOffset, _nonce);
    }

    function _getMarketPermitLiquidityMagnetarCall(
        address _market,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) internal returns (MagnetarCall memory) {
        MarketERC4626.PermitActions _action = MarketERC4626.PermitActions.LIQUIDITY;
        return
            _getMarketPermitActionMagnetarCall(_market, _action, _ownerPk, _spender, _amount, _deadlineOffset, _nonce);
    }

    function _getMarketPermitSharesMagnetarCall(
        address _market,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) internal returns (MagnetarCall memory) {
        MarketERC4626.PermitActions _action = MarketERC4626.PermitActions.VAULT_ERC4626_TRANSFER;
        return
            _getMarketPermitActionMagnetarCall(_market, _action, _ownerPk, _spender, _amount, _deadlineOffset, _nonce);
    }

    function _getMarketPermitBorrowMagnetarCall(
        address _market,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) internal returns (MagnetarCall memory) {
        MarketERC4626.PermitActions _action = MarketERC4626.PermitActions.BORROW;
        return
            _getMarketPermitActionMagnetarCall(_market, _action, _ownerPk, _spender, _amount, _deadlineOffset, _nonce);
    }

    function _getMarketPermitCollateralMagnetarCall(
        address _market,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) internal returns (MagnetarCall memory) {
        MarketERC4626.PermitActions _action = MarketERC4626.PermitActions.COLLATERAL;
        return
            _getMarketPermitActionMagnetarCall(_market, _action, _ownerPk, _spender, _amount, _deadlineOffset, _nonce);
    }

    function _getMarketPermitActionMagnetarCall(
        address _market,
        MarketERC4626.PermitActions _action,
        uint160 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset,
        uint256 _nonce
    ) private returns (MagnetarCall memory) {
        address _owner = vm.addr(_ownerPk);
        uint256 _deadline = block.timestamp + _deadlineOffset;
        (uint8 v, bytes32 r, bytes32 s) =
            _signMarketPermitAction(_market, _ownerPk, _spender, _action, _amount, _deadline, _nonce);

        bytes memory permitActionCallData = abi.encodeWithSelector(
            MarketERC4626.permitAction.selector, _action, _owner, _spender, _amount, _deadline, v, r, s
        );
        return MagnetarCall({id: uint8(MagnetarAction.Permit), target: _market, value: 0, call: permitActionCallData});
    }

    function _getTapTokenPermitMagnetarCall(
        address payable _tapToken,
        uint256 _ownerPk,
        address _spender,
        uint256 _amount,
        uint256 _deadlineOffset
    ) internal view returns (MagnetarCall memory) {
        address _owner = vm.addr(_ownerPk);
        ERC20PermitStruct memory _permitStruct = ERC20PermitStruct({
            owner: _owner,
            spender: _spender,
            value: _amount,
            nonce: IERC20Permit(_tapToken).nonces(_owner),
            deadline: block.timestamp + _deadlineOffset
        });
        bytes32 _digest = TapToken(_tapToken).getTypedDataHash(_permitStruct);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_ownerPk, _digest);
        bytes memory tapTokenPermitCallData = abi.encodeWithSelector(
            IERC20Permit.permit.selector,
            _permitStruct.owner,
            _permitStruct.spender,
            _permitStruct.value,
            _permitStruct.deadline,
            v,
            r,
            s
        );
        return
            MagnetarCall({id: uint8(MagnetarAction.Permit), target: _tapToken, value: 0, call: tapTokenPermitCallData});
    }

    function _getERC20ApproveMagnetarCall(address _token, address _owner, address _spender, uint256 _amount)
        internal
        view
        returns (MagnetarCall memory)
    {
        bytes memory tapTokenPermitCallData = abi.encodeWithSelector(IERC20.approve.selector, _owner, _spender, _amount);
        return MagnetarCall({id: uint8(MagnetarAction.Permit), target: _token, value: 0, call: tapTokenPermitCallData});
    }

    function _getMagnetarCollateralModuleDepositAddCollateralAndBorrowFromMarketMagnetarCall(
        address _market,
        DepositAddCollateralAndBorrowFromMarketData memory _params
    ) private view returns (MagnetarCall memory) {
        bytes memory depositAddCollateralAndBorrowFromMarketCallData =
            abi.encodeWithSelector(MagnetarCollateralModule.depositAddCollateralAndBorrowFromMarket.selector, _params);
        return MagnetarCall({
            id: uint8(MagnetarAction.CollateralModule),
            target: address(0x0),
            value: 0,
            call: depositAddCollateralAndBorrowFromMarketCallData
        });
    }

    function _getMagnetarLeverageModuleBuyCollateralMagnetarCall(
        address _market,
        address _marketHelper,
        address _user,
        uint256 _borrowAmount,
        uint256 _collateralAmount,
        bytes memory _data
    ) internal pure returns (MagnetarCall memory) {
        BuyCollateralData memory _params;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;
        _params.borrowAmount = _borrowAmount;
        _params.collateralAmount = _collateralAmount;
        _params.data = _data;

        bytes memory buyCollateralCallData =
            abi.encodeWithSelector(MagnetarLeverageModule.buyCollateral.selector, _params);
        return MagnetarCall({
            id: uint8(MagnetarAction.LeverageModule),
            target: address(0x0),
            value: 0,
            call: buyCollateralCallData
        });
    }

    function _getMagnetarLeverageModuleSellCollateralMagnetarCall(
        address _market,
        address _marketHelper,
        address _user,
        uint256 _collateralShares,
        bytes memory _data
    ) internal pure returns (MagnetarCall memory) {
        SellCollateralData memory _params;
        _params.market = _market;
        _params.marketHelper = _marketHelper;
        _params.user = _user;
        _params.collateralShares = _collateralShares;
        _params.data = _data;

        bytes memory sellCollateralCallData =
            abi.encodeWithSelector(MagnetarLeverageModule.sellCollateral.selector, _params);
        return MagnetarCall({
            id: uint8(MagnetarAction.LeverageModule),
            target: address(0x0),
            value: 0,
            call: sellCollateralCallData
        });
    }
}
