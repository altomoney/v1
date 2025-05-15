// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// LZ
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Tapioca
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {ICluster} from "tap-utils/interfaces/common/ICluster.sol";
import {TwTAP, Participation} from "tap-token/governance/twTAP.sol";
import {Cluster} from "tap-utils/Cluster/Cluster.sol";
import {Bucket} from "tap-token/interfaces/ITWLBase.sol";
// Tapioca Tests
import {TapTestHelper} from "./TapTestHelper.t.sol";
import {TapTokenMock} from "./TapTokenMock.sol";
import {ERC20PermitStruct, ERC20PermitApprovalMsg} from "tap-utils/interfaces/common/ICommonData.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract TapTokenTest is TapTestHelper, TestHelperOz5 {
    uint32 aEid = 1;
    uint32 bEid = 2;

    TapTokenMock aTapOFT;

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

        cluster = new Cluster(aEid, __owner);

        setUpEndpoints(2, LibraryType.UltraLightNode);

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
                address(this),
                address(cluster)
            )
        );
        vm.label(address(aTapOFT), "aTapOFT");

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

        twTap = new TwTAP(payable(address(aTapOFT)), address(this), EPOCH_DURATION, buckets);
        twTap.setCluster(cluster);

        // Cluster approvals
        cluster.setRoleForContract(address(this), keccak256("NEW_EPOCH"), true);
        cluster.updateContract(0, address(this), true);
        cluster.updateContract(0, address(aTapOFT), true);
        cluster.updateContract(0, address(twTap), true);

        vm.label(address(twTap), "twTAP");

        aTapOFT.setTwTAP(address(twTap));

        // config and wire the ofts
        address[] memory ofts = new address[](1);
        ofts[0] = address(aTapOFT);
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
        // B tests
        assertEq(aTapOFT.owner(), address(this));
        assertEq(aTapOFT.token(), address(aTapOFT));
        assertEq(aTapOFT.totalSupply(), 47_500_000 ether); // Everything minus DSO
        assertEq(aTapOFT.INITIAL_SUPPLY(), 47_500_000 ether);
        assertEq(address(aTapOFT.endpoint()), address(endpoints[aEid]));
        assertEq(address(aTapOFT.twTap()), address(twTap));
    }

    /**
     * @dev Can only be set once, and on host chain.
     */
    function test_set_tw_tap() public {
        // Already set in `this.setUp()`
        vm.expectRevert(ITapToken.TwTapAlreadySet.selector);
        aTapOFT.setTwTAP(address(twTap));
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
                address(this),
                address(cluster)
            )
        );
        vm.label(address(newToken_), _tokenLabel);
    }
}
