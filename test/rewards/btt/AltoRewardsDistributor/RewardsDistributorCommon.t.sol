// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";
import {USD_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IUsdOracle.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ClaimData} from "@alto/rewards/interfaces/IRewardsDistributor.sol";

contract MockLock {
    mapping(address => uint256) public locked;
    address public lastTo;
    uint256 public lastAmount;
    IERC20 public rewardToken;
    uint256 public lastContainerId;
    bool public lastIsReuse;
    uint256 public lastMaxEpochsToLockFor;

    uint256 public maxMultiplierStakingContainerId = 1;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    function lock(address onBehalf, uint256 amount, uint256 containerId, bool isReuse, uint256 maxEpochsToLockFor)
        external
        returns (uint256)
    {
        locked[onBehalf] += amount;
        lastTo = onBehalf;
        lastAmount = amount;
        lastContainerId = containerId;
        lastIsReuse = isReuse;
        lastMaxEpochsToLockFor = maxEpochsToLockFor;
        // Pull tokens from caller (RewardsDistributor)
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        rewardToken.transferFrom(msg.sender, address(this), amount);
        return amount;
    }
}

contract RewardsDistributorCommon is Test {
    AltoRewardsDistributor public distributor;
    ERC20MockDecimals public rewardToken;
    ERC20MockDecimals public paymentToken;
    ERC20MockDecimals public paymentToken2;
    OracleMock public paymentOracle;
    OracleMock public paymentOracle2;
    OracleMock public rewardOracle;
    MockLock public lockContract;

    address public OWNER = address(0x1);
    address public UPDATER = address(0x2);
    address public ALICE = address(0x3);
    address public BOB = address(0x4);
    address public PAUSER = address(0x5);

    uint256 public constant INITIAL_TIMELOCK = 1 days;

    // Test merkle tree data
    bytes32 public testRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    uint256 public aliceAvailable = 1000 ether;
    uint256 public bobAvailable = 2000 ether;

    // Pricing constants
    uint256 public REWARD_PRICE = _getOraclePriceFromEther(100 ether); // $100 per token
    uint256 public PAYMENT_TOKEN_PRICE = _getOraclePriceFromEther(1 ether); // $1 per payment token
    uint256 public constant BASE_DISCOUNT = 0.25 ether; // 25%
    uint256 public constant LOCK_DISCOUNT = 0.15 ether; // 15%

    function _getOraclePriceFromEther(uint256 etherPrice) internal pure returns (uint256) {
        return etherPrice * USD_ORACLE_PRICE_PRECISION / 1 ether;
    }

    function setUp() public virtual {
        // Deploy tokens
        rewardToken = new ERC20MockDecimals("Reward Token", "RWD", 18);
        paymentToken = new ERC20MockDecimals("Payment Token", "PAY", 6);
        paymentToken2 = new ERC20MockDecimals("Payment Token 2", "PAY2", 18);

        // Deploy oracles
        paymentOracle = new OracleMock();
        paymentOracle2 = new OracleMock();
        rewardOracle = new OracleMock();

        paymentOracle.setPrice(PAYMENT_TOKEN_PRICE);
        paymentOracle2.setPrice(_getOraclePriceFromEther(2 ether)); // $2 per token
        rewardOracle.setPrice(REWARD_PRICE);

        // Deploy lock contract
        lockContract = new MockLock(address(rewardToken));

        // Setup merkle tree
        _setupMerkleTree();

        // Deploy distributor
        distributor = new AltoRewardsDistributor(OWNER, INITIAL_TIMELOCK, address(rewardToken));

        // Setup distributor
        vm.startPrank(OWNER);
        distributor.setMerkleRootUpdater(UPDATER, true);
        distributor.setPaymentToken(address(paymentToken), address(paymentOracle));
        distributor.setPaymentToken(address(paymentToken2), address(paymentOracle2));
        distributor.setRewardTokenUsdOracle(address(rewardOracle));
        distributor.setLockBonusDiscount(LOCK_DISCOUNT);
        distributor.setLockContract(address(lockContract));
        distributor.setPauser(PAUSER, PAUSE_TYPE, true);
        distributor.submitNewPendingRoot(testRoot, bytes32(0));
        distributor.acceptPendingRoot(testRoot);
        vm.stopPrank();

        // Fund distributor with reward tokens
        deal(address(rewardToken), address(distributor), 10000 * 10 ** rewardToken.decimals());

        // Fund users with payment tokens
        deal(address(paymentToken), ALICE, 1000000 * 10 ** paymentToken.decimals());
        deal(address(paymentToken), BOB, 1000000 * 10 ** paymentToken.decimals());
        deal(address(paymentToken2), ALICE, 1000000 * 10 ** paymentToken2.decimals());
        deal(address(paymentToken2), BOB, 1000000 * 10 ** paymentToken2.decimals());
    }

    function _setupMerkleTree() internal {
        // Include BASE_DISCOUNT in leaves
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceAvailable, BASE_DISCOUNT, 0, 0))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobAvailable, BASE_DISCOUNT, 0, 0))));

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            testRoot = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        } else {
            testRoot = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            bobProof = new bytes32[](1);
            bobProof[0] = aliceLeaf;
        }
    }

    function _setupMerkleTreeWithDiscount(
        uint256 aliceId,
        uint256 aliceClaim,
        uint256 aliceDiscount,
        uint256 bobId,
        uint256 bobClaim,
        uint256 bobDiscount
    ) internal view returns (bytes32 root, bytes32[] memory aliceProofResult, bytes32[] memory bobProofResult) {
        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, aliceClaim, aliceDiscount, aliceId, 0))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encode(BOB, bobClaim, bobDiscount, bobId, 0))));

        bytes32[] memory newAliceProof = new bytes32[](1);
        bytes32[] memory newBobProof = new bytes32[](1);

        if (uint256(aliceLeaf) < uint256(bobLeaf)) {
            root = keccak256(abi.encodePacked(aliceLeaf, bobLeaf));
            newAliceProof[0] = bobLeaf;
            newBobProof[0] = aliceLeaf;
        } else {
            root = keccak256(abi.encodePacked(bobLeaf, aliceLeaf));
            newAliceProof[0] = bobLeaf;
            newBobProof[0] = aliceLeaf;
        }

        return (root, newAliceProof, newBobProof);
    }

    function _getExpectedPayment(bool isAlice, uint8 paymentTokenId, bool isLockDiscount)
        internal
        view
        returns (uint256)
    {
        ERC20MockDecimals token = paymentTokenId == 0 ? paymentToken : paymentToken2;
        uint256 discount = isLockDiscount ? BASE_DISCOUNT + LOCK_DISCOUNT : BASE_DISCOUNT;
        uint256 purchaseAmount = isAlice ? aliceAvailable : bobAvailable;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discount) / MATH_PRECISION;
        uint256 tokenPrice = paymentTokenId == 0 ? PAYMENT_TOKEN_PRICE : _getOraclePriceFromEther(2 ether);
        uint256 expectedPayment = (discountedCostUSD * 10 ** token.decimals() + tokenPrice - 1) / tokenPrice; // Round up
        return expectedPayment;
    }

    function _getExpectedPaymentWithDiscount(bool isAlice, uint8 paymentTokenId, uint256 discount)
        internal
        view
        returns (uint256)
    {
        ERC20MockDecimals token = paymentTokenId == 0 ? paymentToken : paymentToken2;
        uint256 purchaseAmount = isAlice ? aliceAvailable : bobAvailable;
        uint256 baseCostUSD = (purchaseAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discount) / MATH_PRECISION;
        uint256 tokenPrice = paymentTokenId == 0 ? PAYMENT_TOKEN_PRICE : _getOraclePriceFromEther(2 ether);
        uint256 expectedPayment = (discountedCostUSD * 10 ** token.decimals() + tokenPrice - 1) / tokenPrice; // Round up
        return expectedPayment;
    }

    function _getClaimData(uint256 totalRewards, uint256 discount, uint256 id, uint256 expirationTimestamp)
        internal
        view
        returns (ClaimData memory)
    {
        return ClaimData({
            totalRewardsForUser: totalRewards,
            discount: discount,
            id: id,
            expirationTimestamp: expirationTimestamp
        });
    }
}
