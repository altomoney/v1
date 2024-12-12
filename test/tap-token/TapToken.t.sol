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

// External
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca
import {
    ITapToken,
    LockTwTapPositionMsg,
    UnlockTwTapPositionMsg,
    LZSendParam,
    ERC20PermitStruct,
    ERC721PermitStruct,
    ERC20PermitApprovalMsg,
    ERC721PermitApprovalMsg,
    ClaimTwTapRewardsMsg,
    RemoteTransferMsg
} from "tap-token/tokens/ITapToken.sol";
import {
    TapTokenHelper,
    PrepareLzCallData,
    PrepareLzCallReturn,
    ComposeMsgData
} from "tap-token/tokens/extensions/TapTokenHelper.sol";
import {TapiocaOmnichainExtExec} from "tap-utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainExtExec.sol";

import {TapTokenReceiver} from "tap-token/tokens/TapTokenReceiver.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {TwTAP, Participation} from "tap-token/governance/twTAP.sol";
import {TapTokenSender} from "tap-token/tokens/TapTokenSender.sol";
import {TapTokenCodec} from "tap-token/tokens/TapTokenCodec.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Bucket} from "tap-token/interfaces/ITWLBase.sol";
// Tapioca Tests
import {TapTestHelper} from "./TapTestHelper.t.sol";
import {TapTokenMock} from "./TapTokenMock.sol";
import {ERC721Mock} from "./ERC721Mock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

// TODO Split into multiple part?
contract TapTokenTest is TapTestHelper, IERC721Receiver {
    using OptionsBuilder for bytes;
    using OFTMsgCodec for bytes32;
    using OFTMsgCodec for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;

    TapTokenMock aTapOFT;
    TapTokenMock bTapOFT;

    TapiocaOmnichainExtExec extExec;
    TapTokenHelper tapTokenHelper;

    uint256 internal userAPKey = 0x1;
    uint256 internal userBPKey = 0x2;
    address public userA = vm.addr(userAPKey);
    address public userB = vm.addr(userBPKey);
    uint256 public initialBalance = 100 ether;
    uint256 EPOCH_DURATION = 7 days;

    Bucket public defaultBucket;

    /**
     * DEPLOY setup addresses
     */
    TwTAP twTap;
    address __endpoint;
    address __contributors = address(0x30);
    address __earlySupporters = address(0x31);
    address __supporters = address(0x32);
    address __lbp = address(0x33);
    address __dao = address(0x34);
    address __airdrop = address(0x35);
    uint256 __governanceEid = bEid;
    address __owner = address(this);
    Cluster cluster;

    /**
     * DEPLOY setup addresses
     */
    uint16 internal constant SEND = 1; // Send LZ message type
    uint16 internal constant PT_APPROVALS = 500;
    uint16 internal constant PT_NFT_APPROVALS = 501;
    uint16 internal constant PT_LOCK_TWTAP = 870;
    uint16 internal constant PT_UNLOCK_TWTAP = 871;
    uint16 internal constant PT_CLAIM_REWARDS = 872;
    uint16 internal constant PT_REMOTE_TRANSFER = 700;

    /**
     * @dev TapToken global event checks
     */
    event OFTReceived(bytes32, address, uint256, uint256);
    event ComposeReceived(uint16 indexed msgType, bytes32 indexed guid, bytes composeMsg);

    /**
     * @dev Setup the OApps by deploying them and setting up the endpoints.
     */
    function setUp() public override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.label(userA, "userA");
        vm.label(userB, "userB");

        setUpEndpoints(3, LibraryType.UltraLightNode);

        extExec = new TapiocaOmnichainExtExec();
        cluster = new Cluster(aEid, __owner);

        aTapOFT = new TapTokenMock(
            ITapToken.TapTokenConstructorData(
                EPOCH_DURATION,
                address(endpoints[aEid]),
                __contributors,
                __earlySupporters,
                __supporters,
                __lbp,
                __dao,
                __airdrop,
                __governanceEid,
                address(this),
                address(new TapTokenSender("", "", address(endpoints[aEid]), address(this), address(0))),
                address(new TapTokenReceiver("", "", address(endpoints[aEid]), address(this), address(0))),
                address(extExec),
                ICluster(address(cluster))
            )
        );
        vm.label(address(aTapOFT), "aTapOFT");

        bTapOFT = new TapTokenMock(
            ITapToken.TapTokenConstructorData(
                EPOCH_DURATION,
                address(endpoints[bEid]),
                __contributors,
                __earlySupporters,
                __supporters,
                __lbp,
                __dao,
                __airdrop,
                __governanceEid,
                address(this),
                address(new TapTokenSender("", "", address(endpoints[bEid]), address(this), address(0))),
                address(new TapTokenReceiver("", "", address(endpoints[bEid]), address(this), address(0))),
                address(extExec),
                ICluster(address(cluster))
            )
        );
        vm.label(address(bTapOFT), "bTapOFT");

        defaultBucket = Bucket({
            enabled: true,
            epochGrowthRate: 1,
            epochDecayRate: 1,
            epochCeiling: 10,
            epochFloor: 1,
            rewardsMultiplier: 10_00,
            lockEpochDuration: 1,
            currentEpochInflows: 0,
            lastEpochInflows: 0,
            growthGoal: 1e18
        });
        Bucket[] memory buckets = new Bucket[](1);
        buckets[0] = defaultBucket;

        twTap = new TwTAP(payable(address(bTapOFT)), address(this), EPOCH_DURATION, buckets);
        twTap.setCluster(cluster);

        // Cluster approvals
        cluster.setRoleForContract(address(this), keccak256("NEW_EPOCH"), true);
        cluster.updateContract(0, address(this), true);
        cluster.updateContract(0, address(aTapOFT), true);
        cluster.updateContract(0, address(bTapOFT), true);
        cluster.updateContract(0, address(twTap), true);

        vm.label(address(twTap), "twTAP");

        bTapOFT.setTwTAP(address(twTap));

        tapTokenHelper = new TapTokenHelper();
        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aTapOFT);
        ofts[1] = address(bTapOFT);
        this.wireOApps(ofts);

        console.log("setup", twTap.lastProcessedWeek(), twTap.currentEpoch());
        console.log("tup", twTap.INIT_TIMESTAMP(), twTap.EPOCH_DURATION());
    }

    /**
     * Allocation:
     * ============
     * DSO: 53,313,405
     * DAO: 8m
     * Contributors: 15m
     * Early supporters: 3,686,595
     * Supporters: 12.5m
     * LBP: 5m
     * Airdrop: 2.5m
     * == 100M ==
     */
    function test_constructor() public view {
        // A tests
        assertEq(aTapOFT.owner(), address(this));
        assertEq(aTapOFT.token(), address(aTapOFT));
        assertEq(aTapOFT.totalSupply(), 0);
        assertEq(aTapOFT.governanceEid(), bEid);
        assertEq(address(aTapOFT.endpoint()), address(endpoints[aEid]));
        assertEq(address(aTapOFT.twTap()), address(0));

        // B tests
        assertEq(bTapOFT.owner(), address(this));
        assertEq(bTapOFT.token(), address(bTapOFT));
        assertEq(bTapOFT.totalSupply(), 47_500_000 ether); // Everything minus DSO
        assertEq(bTapOFT.INITIAL_SUPPLY(), 47_500_000 ether);
        assertEq(bTapOFT.governanceEid(), bEid);
        assertEq(address(bTapOFT.endpoint()), address(endpoints[bEid]));
        assertEq(address(bTapOFT.twTap()), address(twTap));
    }

    /**
     * @dev Can only be set once, and on host chain.
     */
    function test_set_tw_tap() public {
        // Can't set because not host chain
        vm.expectRevert(ITapToken.OnlyHostChain.selector);
        aTapOFT.setTwTAP(address(twTap));

        // Already set in `this.setUp()`
        vm.expectRevert(ITapToken.TwTapAlreadySet.selector);
        bTapOFT.setTwTAP(address(twTap));
    }

    function test_erc20_permit() public {
        ERC20PermitStruct memory permit_ =
            ERC20PermitStruct({owner: userA, spender: userB, value: 1e18, nonce: 0, deadline: 1 days});

        bytes32 digest_ = aTapOFT.getTypedDataHash(permit_);
        ERC20PermitApprovalMsg memory permitApproval_ =
            __getERC20PermitData(permit_, digest_, address(aTapOFT), userAPKey);

        aTapOFT.permit(
            permit_.owner,
            permit_.spender,
            permit_.value,
            permit_.deadline,
            permitApproval_.v,
            permitApproval_.r,
            permitApproval_.s
        );
        assertEq(aTapOFT.allowance(userA, userB), 1e18);
        assertEq(aTapOFT.nonces(userA), 1);
    }

    function test_erc721_permit() public {
        ERC721Mock erc721Mock = new ERC721Mock("Mock", "Mock");
        vm.label(address(erc721Mock), "erc721Mock");
        erc721Mock.mint(address(userA), 1);

        ERC721PermitStruct memory permit_ = ERC721PermitStruct({spender: userB, tokenId: 1, nonce: 1, deadline: 1 days});

        bytes32 digest_ = erc721Mock.getTypedDataHash(permit_);
        ERC721PermitApprovalMsg memory permitApproval_ =
            __getERC721PermitData(permit_, digest_, address(erc721Mock), userAPKey);

        erc721Mock.permit(
            permit_.spender, permit_.tokenId, permit_.deadline, permitApproval_.v, permitApproval_.r, permitApproval_.s
        );
        assertEq(erc721Mock.getApproved(1), userB);
        assertEq(erc721Mock.nonces(permit_.tokenId), 2);
    }

    /**
     * ERC20 APPROVALS
     */
    function test_tapOFT_erc20_approvals() public {
        address userC_ = vm.addr(0x3);

        ERC20PermitApprovalMsg memory permitApprovalB_;
        ERC20PermitApprovalMsg memory permitApprovalC_;
        bytes memory approvalsMsg_;

        {
            ERC20PermitStruct memory approvalUserB_ =
                ERC20PermitStruct({owner: userA, spender: userB, value: 1e18, nonce: 0, deadline: 1 days});
            ERC20PermitStruct memory approvalUserC_ = ERC20PermitStruct({
                owner: userA,
                spender: userC_,
                value: 2e18,
                nonce: 1, // Nonce is 1 because we already called permit() on userB
                deadline: 2 days
            });

            permitApprovalB_ = __getERC20PermitData(
                approvalUserB_, bTapOFT.getTypedDataHash(approvalUserB_), address(bTapOFT), userAPKey
            );

            permitApprovalC_ = __getERC20PermitData(
                approvalUserC_, bTapOFT.getTypedDataHash(approvalUserC_), address(bTapOFT), userAPKey
            );

            ERC20PermitApprovalMsg[] memory approvals_ = new ERC20PermitApprovalMsg[](2);
            approvals_[0] = permitApprovalB_;
            approvals_[1] = permitApprovalC_;

            approvalsMsg_ = tapTokenHelper.encodeERC20PermitApprovalMsg(approvals_);
        }

        PrepareLzCallReturn memory prepareLzCallReturn_ = tapTokenHelper.prepareLzCall(
            ITapToken(address(aTapOFT)),
            PrepareLzCallData({
                dstEid: bEid,
                recipient: OFTMsgCodec.addressToBytes32(address(this)),
                amountToSendLD: 0,
                minAmountToCreditLD: 0,
                msgType: PT_APPROVALS,
                composeMsgData: ComposeMsgData({
                    index: 0,
                    gas: 1_000_000,
                    value: 0,
                    data: approvalsMsg_,
                    prevData: bytes(""),
                    prevOptionsData: bytes("")
                }),
                lzReceiveGas: 1_000_000,
                lzReceiveValue: 0,
                refundAddress: address(this)
            })
        );
        bytes memory composeMsg_ = prepareLzCallReturn_.composeMsg;
        bytes memory oftMsgOptions_ = prepareLzCallReturn_.oftMsgOptions;
        MessagingFee memory msgFee_ = prepareLzCallReturn_.msgFee;
        LZSendParam memory lzSendParam_ = prepareLzCallReturn_.lzSendParam;

        (MessagingReceipt memory msgReceipt_,, bytes memory msgSent,) =
            aTapOFT.sendPacket{value: msgFee_.nativeFee}(lzSendParam_, composeMsg_);

        verifyPackets(uint32(bEid), address(bTapOFT));

        vm.expectEmit(true, true, true, false);
        emit IERC20.Approval(userA, userB, 1e18);

        vm.expectEmit(true, true, true, false);
        emit IERC20.Approval(userA, userC_, 1e18);

        __callLzCompose(
            LzOFTComposedData(
                PT_APPROVALS,
                msgReceipt_.guid,
                msgSent,
                bEid,
                address(bTapOFT), // Compose creator (at lzReceive)
                address(bTapOFT), // Compose receiver (at lzCompose)
                address(this),
                oftMsgOptions_
            )
        );

        assertEq(bTapOFT.allowance(userA, userB), 1e18);
        assertEq(bTapOFT.allowance(userA, userC_), 2e18);
        assertEq(bTapOFT.nonces(userA), 2);
    }

    /**
     * @dev Test the OApp functionality of `TapToken.unlockTwTapPosition()` function.
     */
    function test_remote_transfer() public {
        uint256 tokenAmount_ = 1 ether;
        LZSendParam memory remoteLzSendParam_;
        MessagingFee memory remoteMsgFee_; // Will be used as value for the composed msg

        /**
         * Setup
         */
        {
            deal(address(bTapOFT), address(this), tokenAmount_);

            // @dev `remoteMsgFee_` is to be airdropped on dst to pay for the `remoteTransfer` operation (B->A).
            PrepareLzCallReturn memory prepareLzCallReturn1_ = tapTokenHelper.prepareLzCall( // B->A data
                ITapToken(address(bTapOFT)),
                PrepareLzCallData({
                    dstEid: aEid,
                    recipient: OFTMsgCodec.addressToBytes32(address(this)),
                    amountToSendLD: tokenAmount_,
                    minAmountToCreditLD: tokenAmount_,
                    msgType: SEND,
                    composeMsgData: ComposeMsgData({
                        index: 0,
                        gas: 0,
                        value: 0,
                        data: bytes(""),
                        prevData: bytes(""),
                        prevOptionsData: bytes("")
                    }),
                    lzReceiveGas: 2_000_000,
                    lzReceiveValue: 0,
                    refundAddress: address(this)
                })
            );
            remoteLzSendParam_ = prepareLzCallReturn1_.lzSendParam;
            remoteMsgFee_ = prepareLzCallReturn1_.msgFee;
        }

        /**
         * Actions
         */
        RemoteTransferMsg memory remoteTransferData =
            RemoteTransferMsg({composeMsg: new bytes(0), owner: address(this), lzSendParam: remoteLzSendParam_});
        bytes memory remoteTransferMsg_ = tapTokenHelper.buildRemoteTransferMsg(remoteTransferData);

        PrepareLzCallReturn memory prepareLzCallReturn2_ = tapTokenHelper.prepareLzCall(
            ITapToken(address(aTapOFT)),
            PrepareLzCallData({
                dstEid: bEid,
                recipient: OFTMsgCodec.addressToBytes32(address(this)),
                amountToSendLD: 0,
                minAmountToCreditLD: 0,
                msgType: PT_REMOTE_TRANSFER,
                composeMsgData: ComposeMsgData({
                    index: 0,
                    gas: 1_000_000,
                    value: uint128(remoteMsgFee_.nativeFee), // TODO Should we care about verifying cast boundaries?
                    data: remoteTransferMsg_,
                    prevData: bytes(""),
                    prevOptionsData: bytes("")
                }),
                lzReceiveGas: 2_000_000,
                lzReceiveValue: 0,
                refundAddress: address(this)
            })
        );
        bytes memory composeMsg_ = prepareLzCallReturn2_.composeMsg;
        bytes memory oftMsgOptions_ = prepareLzCallReturn2_.oftMsgOptions;
        MessagingFee memory msgFee_ = prepareLzCallReturn2_.msgFee;
        LZSendParam memory lzSendParam_ = prepareLzCallReturn2_.lzSendParam;

        (MessagingReceipt memory msgReceipt_,, bytes memory msgSent,) =
            aTapOFT.sendPacket{value: msgFee_.nativeFee}(lzSendParam_, composeMsg_);

        {
            verifyPackets(uint32(bEid), address(bTapOFT));

            // Initiate approval
            bTapOFT.approve(address(bTapOFT), tokenAmount_); // Needs to be pre approved on B chain to be able to transfer

            __callLzCompose(
                LzOFTComposedData(
                    PT_REMOTE_TRANSFER,
                    msgReceipt_.guid,
                    msgSent,
                    bEid,
                    address(bTapOFT), // Compose creator (at lzReceive)
                    address(bTapOFT), // Compose receiver (at lzCompose)
                    address(this),
                    oftMsgOptions_
                )
            );
        }

        // Check arrival
        {
            assertEq(aTapOFT.balanceOf(address(this)), 0);
            verifyPackets(uint32(aEid), address(aTapOFT)); // Verify B->A transfer
            assertEq(aTapOFT.balanceOf(address(this)), tokenAmount_);
        }
    }

    // Stack to deep
    struct TestClaimRewardsData {
        TapTokenMock erc20Mock1;
        TapTokenMock erc20Mock1Dst;
        TapTokenMock erc20Mock2;
        TapTokenMock erc20Mock2Dst;
        uint256 tokenAmount1;
        uint256 tokenAmount2;
        uint256 tokenId;
        LZSendParam remoteLzSendParam1;
        LZSendParam remoteLzSendParam2;
        MessagingFee remoteMsgFee1;
        MessagingFee remoteMsgFee2;
        uint256 expectReceive1;
        uint256 expectReceive2;
    }

    /**
     * @dev Receiver for `TapToken::PT_LOCK_TW_TAP` function.
     */
    function onERC721Received(
        address, // operator
        address, //from
        uint256, // tokenId
        bytes calldata // data
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * =================
     *      HELPERS
     * =================
     */

    /**
     * @dev Used to bypass stack too deep
     *
     * @param msgType The message type of the lz Compose.
     * @param guid The message GUID.
     * @param composeMsg The source raw OApp compose message. If compose msg is composed with other msgs,
     * the msg should contain only the compose msg at its index and forward. I.E composeMsg[currentIndex:]
     * @param dstEid The destination EID.
     * @param from The address initiating the composition, typically the OApp where the lzReceive was called.
     * @param to The address of the lzCompose receiver.
     * @param srcMsgSender The address of src EID OFT `msg.sender` call initiator .
     * @param extraOptions The options passed in the source OFT call. Only restriction is to have it contain the actual compose option for the index,
     * whether there are other composed calls or not.
     */
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

    /**
     * @notice Call lzCompose on the destination OApp.
     *
     * @dev Be sure to verify the message by calling `TestHelper.verifyPackets()`.
     * @dev Will internally verify the emission of the `ComposeReceived` event with
     * the right msgType, GUID and lzReceive composer message.
     *
     * @param _lzOFTComposedData The data to pass to the lzCompose call.
     */
    function __callLzCompose(LzOFTComposedData memory _lzOFTComposedData) internal {
        vm.expectEmit(true, true, true, false);
        emit ComposeReceived(_lzOFTComposedData.msgType, _lzOFTComposedData.guid, _lzOFTComposedData.composeMsg);

        this.lzCompose{value: 1_000_000}(
            _lzOFTComposedData.dstEid,
            _lzOFTComposedData.from,
            _lzOFTComposedData.extraOptions,
            _lzOFTComposedData.guid,
            _lzOFTComposedData.to,
            _lzOFTComposedData.composeMsg
        );
    }

    function _createNewToftToken(string memory _tokenLabel, address _endpoint)
        internal
        returns (TapTokenMock newToken_)
    {
        newToken_ = new TapTokenMock(
            ITapToken.TapTokenConstructorData(
                EPOCH_DURATION,
                _endpoint,
                __contributors,
                __earlySupporters,
                __supporters,
                __lbp,
                __dao,
                __airdrop,
                __governanceEid,
                address(this),
                address(new TapTokenSender("", "", _endpoint, address(this), address(extExec))),
                address(new TapTokenReceiver("", "", _endpoint, address(this), address(extExec))),
                address(extExec),
                ICluster(address(cluster))
            )
        );
        vm.label(address(newToken_), _tokenLabel);
    }
}
