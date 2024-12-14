// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// LZ
import {
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

// Tapioca
import {UsdoMarketReceiverModule} from "tapioca-bar/usdo/modules/UsdoMarketReceiverModule.sol";
import {MarketLendOrRepayMsg, MarketRemoveAssetMsg, MarketPermitActionMsg} from "tap-utils/interfaces/oft/IUsdo.sol";

import {MarketHelper} from "tapioca-bar/markets/MarketHelper.sol";
import {BigBang} from "tapioca-bar/markets/bigBang/BigBang.sol";

import {ERC20PermitStruct, ERC20PermitApprovalMsg} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";
import {
    TapiocaOmnichainEngineHelper,
    PrepareLzCallData,
    PrepareLzCallReturn,
    ComposeMsgData,
    LZSendParam,
    RemoteTransferMsg
} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol";

// tests
import {Singularity_Unit_Shared} from "../../shared/Singularity_Unit_Shared.t.sol";
import {BigBang_Unit_Shared} from "../../shared/BigBang_Unit_Shared.t.sol";
import {Usdo_Unit_Shared} from "../../shared/Usdo_Unit_Shared.t.sol";
import {Markets_Unit_Shared} from "../../shared/Markets_Unit_Shared.t.sol";
import "forge-std/console.sol";

// @review-test: Review the tests in this contract. It is failing in the setup.
abstract contract Usdo_crossChain is Usdo_Unit_Shared, BigBang_Unit_Shared, Singularity_Unit_Shared {
    // ************* //
    // *** SETUP *** //
    // ************* //
    function setUp() public override(Usdo_Unit_Shared, BigBang_Unit_Shared, Singularity_Unit_Shared) {
        super.setUp();
    }

    function _approveForCollateral(address txExecutor)
        internal
        override(Markets_Unit_Shared, Singularity_Unit_Shared)
        resetPrank(txExecutor)
    {
        // TODO Review it _approveViaERC20(mainBB.collateral(), txExecutor, type(uint256).max);

        // TODO Review it _approveViaERC20(secondaryBB.collateral(), txExecutor, type(uint256).max);
    }

    function test_WhenErc20ApprovalIsPerformedOnCurrentChain(uint256 amount)
        external
        assumeRange(amount, SMALL_AMOUNT, LARGE_AMOUNT)
    {
        ERC20PermitStruct memory permit_ = _createErc20PermitStruct(userA, userB, amount, 0);

        // get permit message
        bytes32 digest_ = usdo.getTypedDataHash(permit_);
        ERC20PermitApprovalMsg memory permitApproval_ =
            __getERC20PermitData(permit_, digest_, address(usdo), USER_A_PKEY);

        // call permit
        usdo.permit(
            permit_.owner,
            permit_.spender,
            permit_.value,
            permit_.deadline,
            permitApproval_.v,
            permitApproval_.r,
            permitApproval_.s
        );

        // it should increase allowance of main Usdo
        assertEq(usdo.allowance(userA, userB), amount);
        // it should increase nonce of main Usdo
        assertEq(usdo.nonces(userA), 1);
    }

    function test_WhenErc20ApprovalIsPerformedOnCrossChainLevel(uint256 amount)
        external
        assumeRange(amount, SMALL_AMOUNT, LARGE_AMOUNT)
    {
        cluster.updateContract(0, address(secondaryUsdo), true);

        // create permit messages
        ERC20PermitApprovalMsg memory permitApprovalB_;
        ERC20PermitApprovalMsg memory permitApprovalC_;
        bytes memory approvalsMsg_;

        {
            ERC20PermitStruct memory permitStructUserB = _createErc20PermitStruct(userA, userB, amount, 0);
            ERC20PermitStruct memory permitStructUserC = _createErc20PermitStruct(userA, userC, amount, 1); // nonce 1

            permitApprovalB_ = __getERC20PermitData(
                permitStructUserB,
                secondaryUsdo.getTypedDataHash(permitStructUserB),
                address(secondaryUsdo),
                USER_A_PKEY
            );
            permitApprovalC_ = __getERC20PermitData(
                permitStructUserC,
                secondaryUsdo.getTypedDataHash(permitStructUserC),
                address(secondaryUsdo),
                USER_A_PKEY
            );

            ERC20PermitApprovalMsg[] memory approvals_ = new ERC20PermitApprovalMsg[](2);
            approvals_[0] = permitApprovalB_;
            approvals_[1] = permitApprovalC_;

            approvalsMsg_ = usdoHelper.encodeERC20PermitApprovalMsg(approvals_);
        }

        _prepareAndExecuteCrossChainPackets(
            address(usdo), address(secondaryUsdo), bEid, address(this), 0, PT_APPROVALS, approvalsMsg_
        );

        // it should increase allowance of secondary Usdo for 2 users
        assertEq(secondaryUsdo.allowance(userA, userB), amount);
        assertEq(secondaryUsdo.allowance(userA, userC), amount);

        // it should increase nonce of secondary Usdo
        assertEq(secondaryUsdo.nonces(userA), 2);
    }

    function test_WhenRemoteTransferIsCalledFromSecondaryChain(uint256 amount)
        external
        assumeRange(amount, SMALL_AMOUNT, LARGE_AMOUNT)
        whenApprovedViaERC20(address(secondaryUsdo), address(this), address(secondaryUsdo), amount)
    {
        LZSendParam memory remoteLzSendParam_;
        MessagingFee memory remoteMsgFee_;
        {
            deal(address(secondaryUsdo), address(this), amount);

            PrepareLzCallReturn memory prepareLzCallReturn1_ =
                _prepareLzCall(address(secondaryUsdo), aEid, address(this), amount, SEND, "", 0);
            remoteLzSendParam_ = prepareLzCallReturn1_.lzSendParam;
            remoteMsgFee_ = prepareLzCallReturn1_.msgFee;
        }

        {
            RemoteTransferMsg memory remoteTransferData =
                RemoteTransferMsg({composeMsg: new bytes(0), owner: address(this), lzSendParam: remoteLzSendParam_});
            bytes memory remoteTransferMsg_ = usdoHelper.buildRemoteTransferMsg(remoteTransferData);

            PrepareLzCallReturn memory prepareLzCallReturn2_ = _prepareLzCall(
                address(usdo), bEid, address(this), 0, PT_REMOTE_TRANSFER, remoteTransferMsg_, remoteMsgFee_.nativeFee
            );
            bytes memory composeMsg_ = prepareLzCallReturn2_.composeMsg;
            bytes memory oftMsgOptions_ = prepareLzCallReturn2_.oftMsgOptions;
            MessagingFee memory msgFee_ = prepareLzCallReturn2_.msgFee;
            LZSendParam memory lzSendParam_ = prepareLzCallReturn2_.lzSendParam;

            (MessagingReceipt memory msgReceipt_,, bytes memory sentMsg,) =
                usdo.sendPacket{value: msgFee_.nativeFee}(lzSendParam_, composeMsg_);

            verifyPackets(uint32(bEid), address(secondaryUsdo));

            __callLzCompose(
                LzOFTComposedData(
                    PT_REMOTE_TRANSFER,
                    msgReceipt_.guid,
                    sentMsg,
                    bEid,
                    address(secondaryUsdo), // Compose creator (at lzReceive)
                    address(secondaryUsdo), // Compose receiver (at lzCompose)
                    address(this),
                    oftMsgOptions_
                )
            );
        }

        // it should increase local chain balance
        assertEq(usdo.balanceOf(address(this)), 0);
        verifyPackets(uint32(aEid), address(usdo)); // Verify B->A transfer
        assertApproxEqRel(usdo.balanceOf(address(this)), amount, 0.0001e18); // to pass over the LD to SD and SD to LD conversion
    }

    function test_whenCrossChainPermitOrRevokeIsTriggered_WhenPermitAllIsCalled() external {
        vm.skip(true);
        // _resetPrank(address(this));
        // _crossChainApproveOrRevokeAll(true);
    }

    function test_whenCrossChainPermitOrRevokeIsTriggered_WhenRevokeAllIsCalled() external {
        vm.skip(true);
        // _resetPrank(address(this));
        // _crossChainApproveOrRevokeAll(false);
    }

    function test_whenMarketPermitIsCalled_WhenPermitAsset(uint256 amount)
        external
        assumeRange(amount, SMALL_AMOUNT, LARGE_AMOUNT)
        whenWhitelisted(address(secondaryUsdo))
        whenWhitelisted(address(mainBB))
    {
        _marketPermit(amount, true);

        // it should increase market allowance for asset
        assertEq(mainBB.allowance(userA, userB), amount);
    }

    function test_whenMarketPermitIsCalled_WhenPermitCollateral(uint256 amount)
        external
        assumeRange(amount, SMALL_AMOUNT, LARGE_AMOUNT)
        whenWhitelisted(address(secondaryUsdo))
        whenWhitelisted(address(mainBB))
    {
        _marketPermit(amount, false);

        // it should increase market allowance for collateral
        assertEq(mainBB.allowanceBorrow(userA, userB), amount);
    }

    function _createMarketLendOrRepayMsg(
        BigBang _mainBB,
        uint256 _repayPart,
        uint256 _collateralAmount,
        uint256 _borrowAmount
    ) internal returns (MarketLendOrRepayMsg memory marketMsg) {
        _repayPart = _boundRepayAmount(_repayPart, _mainBB);
        uint256 repayPercentage = _repayPart * FEE_PRECISION / _borrowAmount;
        uint256 removeCollateralAmount = repayPercentage * _collateralAmount / FEE_PRECISION;

        MarketLendOrRepayMsg memory marketMsg = _createMinimalLendOrRepayMsg(
            _LendOrRepayInternal({
                repay: true,
                lock: false,
                participate: false,
                removeCollateral: true,
                repayAmount: _repayPart,
                depositAmount: 0,
                magnetar: address(magnetar),
                marketHelper: address(marketHelper),
                market: address(_mainBB),
                removeCollateralAmount: removeCollateralAmount,
                lockDataTarget: address(0),
                participateDataTarget: address(0)
            })
        );
        return marketMsg;
    }

    function test_WhenRepayAndRemoveCollateralIsPerformed(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 repayPart
    )
        external
        whenContractIsNotPaused
        whenCollateralAmountIsValid(collateralAmount)
        whenOracleRateIsEth
        whenAssetOracleRateIsBelowMin
        whenWhitelisted(address(magnetar))
        whenWhitelisted(address(marketHelper))
        whenWhitelisted(address(mainBB))
    {
        vm.skip(true);
        /*
        uint256 borrowedAmount = _addCollateralAndBorrow(
            collateralAmount,
            borrowAmount,
            mainBB,
            address(this),
            address(this)
        );

        MarketLendOrRepayMsg memory marketMsg = _createMarketLendOrRepayMsg(
            mainBB,
            repayPart,
            collateralAmount,
            borrowAmount
        );


        _BorrowInternal memory _borrowData;
        _RemoveCollateralInternal memory _data;
        _data.userCollateralBefore = mainBB.balanceOf(address(this));
        _data.totalCollateralShareBefore = mainBB._totalCollateralShare();
        _borrowData.totalBorrowBefore = mainBB._totalBorrow();
        _borrowData.userBorrowPartBefore = mainBB._userBorrowPart(address(this));

        // approvals
        {
            mainBB.approveBorrow(address(magnetar), type(uint256).max);
        }

        _prepareAndExecuteComposedCrossChainPackets(
            address(usdo),
            address(secondaryUsdo),
            aEid,
            bEid,
            address(this),
            0,
            PT_YB_SEND_SGL_LEND_OR_REPAY,
            usdoHelper.buildMarketLendOrRepayMsg(marketMsg)
        );

        _data.userCollateralAfter = mainBB.balanceOf(address(this));
        _data.totalCollateralShareAfter = mainBB._totalCollateralShare();
        _borrowData.totalBorrowAfter = mainBB._totalBorrow();
        _borrowData.userBorrowPartAfter = mainBB._userBorrowPart(address(this));

        // it should decrease userCollateralShare
        assertGt(_data.userCollateralBefore, _data.userCollateralAfter);
        // it should decrease totalCollateralShare
        assertGt(_data.totalCollateralShareBefore, _data.totalCollateralShareAfter);
        // it should decrease userBorrowPart
        assertGt(_borrowData.userBorrowPartBefore, _borrowData.userBorrowPartAfter);
        // it should decrease totalBorrow
        assertGt(_borrowData.totalBorrowBefore.base, _borrowData.totalBorrowAfter.base);
        assertGt(_borrowData.totalBorrowBefore.elastic, _borrowData.totalBorrowAfter.elastic);
        */
    }

    function test_whenRemoveAssetIsCalledCrossChain_WhenMagnetarIsAvailable(uint256 collateralAmount)
        external
        whenContractIsNotPaused
        whenOracleRateIsEth
        whenAssetOracleRateIsBelowMin
        whenCollateralAmountIsValid(collateralAmount)
        whenWhitelisted(address(magnetar))
        whenWhitelisted(address(marketHelper))
        whenWhitelisted(address(mainBB))
        whenWhitelisted(address(randomSgl))
    {
        vm.skip(true);
        uint256 repayPart;
        uint256 removeCollateralAmount = collateralAmount * 1e4 / 1e5; //remove 10%
        // BigBang section - to obtain Usdo
        {
            uint256 minLendAmount = randomSgl.minLendAmount() + 1;
            // **** Add collateral ****
            _addCollateral(collateralAmount, mainBB, address(this), address(this), address(this), address(this), false);

            uint256 borrowAmount = minLendAmount * 2;
            repayPart = minLendAmount;

            // **** Borrow ****
            _borrow(borrowAmount, mainBB, address(this), address(this), address(this));
        }

        uint256 lendAmount = repayPart;
        uint256 removeAmount = lendAmount / 4;

        MarketRemoveAssetMsg memory marketMsg = _createMinimalRemoveAssetMsg(
            _RemoveAssetInternal({
                magnetar: address(magnetar),
                marketHelper: address(marketHelper),
                market: address(randomSgl),
                removeAmount: removeAmount,
                repayAmount: repayPart - 1,
                removeCollateralAmount: removeCollateralAmount,
                bb: address(mainBB)
            })
        );
        // approvals
        {
            mainBB.approveBorrow(address(magnetar), type(uint256).max);
        }

        // add asset
        uint256 lendShare = randomSgl.convertToShares(lendAmount);
        randomSgl.addAsset(address(this), address(this), false, lendShare);

        uint256 balanceBefore = randomSgl.balanceOf(address(this));
        uint256 supplyBefore = randomSgl.totalSupply();
        uint256 userSupplyBefore = randomSgl.balanceOf(address(this));

        _prepareAndExecuteComposedCrossChainPackets(
            address(usdo),
            address(secondaryUsdo),
            aEid,
            bEid,
            address(this),
            0,
            PT_MARKET_REMOVE_ASSET,
            usdoHelper.buildMarketRemoveAssetMsg(marketMsg)
        );
        /*
        TODO review it
        uint256 balanceAfter = randomSgl.balanceOf(address(this));
        uint256 supplyAfter = randomSgl.totalSupply();
        uint256 userSupplyAfter = yieldBox.balanceOf(address(this));

        // it should remove asset from market
        assertGt(balanceBefore, balanceAfter);
        // it should decrease market supply
        assertGt(supplyBefore, supplyAfter);
        // it should transfer asset to user
        assertGt(userSupplyAfter, userSupplyBefore);
        */
    }

    // *************** //
    // *** PRIVATE *** //
    // *************** //
    function _marketPermit(uint256 amount, bool permit) private {
        bytes memory approvalMsg_;
        {
            MarketPermitActionMsg memory approvalUserB_ = MarketPermitActionMsg({
                target: address(mainBB),
                owner: userA,
                spender: userB,
                value: amount,
                deadline: 1 days,
                v: 0,
                r: 0,
                s: 0,
                permitAsset: permit
            });
            bytes32 digest_ =
                _getMarketPermitTypedDataHash(permit, userA, userB, amount, 1 days, 0, mainBB.DOMAIN_SEPARATOR());
            MarketPermitActionMsg memory permitApproval_ = __getMarketPermitData(approvalUserB_, digest_, USER_A_PKEY);

            approvalMsg_ = usdoHelper.buildMarketPermitApprovalMsg(permitApproval_);
        }

        _prepareAndExecuteCrossChainPackets(
            address(usdo), address(secondaryUsdo), bEid, address(this), 0, PT_MARKET_PERMIT, approvalMsg_
        );
    }
}
