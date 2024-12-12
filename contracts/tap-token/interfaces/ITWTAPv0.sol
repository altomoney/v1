// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721PermitStruct} from "tap-token/tokens/ITapToken.sol";

/// @title ITWTAPv0
/// @author Tapioca
/// @notice DEPRECATED
/// @dev This interface is deprecated and only kept for compatibility with old contracts
interface ITWTAPv0 {
    error AdvanceEpochFirst();
    error AdvanceWeekFirst();
    error Duplicate();
    error DurationNotMultiple();
    error EmergencySweepCooldownNotReached();
    error InvalidShortString();
    error LockNotAWeek();
    error LockNotExpired();
    error LockTooLong();
    error NotApproved(uint256 tokenId, address spender);
    error NotAuthorized();
    error NotValid();
    error Registered();
    error StringTooLong(string str);
    error TokenLimitReached();

    event AMLDivergence(
        uint256 indexed cumulative, uint256 indexed averageMagnitude, uint256 indexed totalParticipants
    );
    event ActivateEmergencySweep();
    event AddRewardToken(address indexed rewardTokenAddress, uint256 rewardTokenIndex);
    event AdvanceEpoch(uint256 indexed newEpoch, uint256 lastEpoch);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event ClaimReward(
        address indexed rewardTokenAddress,
        address indexed to,
        uint256 indexed twTapTokenId,
        uint256 amount,
        uint256 rewardTokenIndex
    );
    event DistributeReward(
        address indexed rewardTokenAddress, address indexed from, uint256 amount, uint256 rewardTokenIndex
    );
    event EIP712DomainChanged();
    event EmergencySweepLocks();
    event EmergencySweepRewards();
    event ExitPosition(uint256 indexed twTapTokenId, address indexed releasedTo, uint256 amount);
    event LogMaxRewardsLength(uint256 _oldLength, uint256 _newLength, uint256 _currentLength);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Participate(
        address indexed participant, uint256 mintedTokenId, uint256 tapAmount, uint256 multiplier, uint256 lockDuration
    );
    event Paused(address account);
    event RescueMode(bool _rescueMode);
    event SetCluster(address _cluster);
    event SetEmergencySweepCooldown(uint256 emergencySweepCooldown);
    event SetMinWeightFactor(uint256 newMinWeightFactor, uint256 oldMinWeightFactor);
    event SetVirtualTotalAmount(uint256 newVirtualTotalAmount, uint256 oldVirtualTotalAmount);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Unpaused(address account);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function EPOCH_DURATION() external view returns (uint256);

    function MAX_LOCK_DURATION() external view returns (uint256);

    function MIN_WEIGHT_FACTOR() external view returns (uint256);

    function VIRTUAL_TOTAL_AMOUNT() external view returns (uint256);

    function activateEmergencySweep() external;

    function addRewardToken(address _token) external returns (uint256);

    function advanceWeek(uint256 _limit) external;

    function approve(address to, uint256 tokenId) external;

    function balanceOf(address owner) external view returns (uint256);

    function baseURI() external view returns (string memory);

    function batchClaimRewards(uint256[] memory _tokenIds) external returns (uint256[][] memory amounts_);

    function claimRewards(uint256 _tokenId) external returns (uint256[] memory amounts_);

    function claimable(uint256 _tokenId) external view returns (uint256[] memory);

    function claimed(uint256, uint256) external view returns (uint256);

    function cluster() external view returns (address);

    function creation() external view returns (uint256);

    function currentWeek() external view returns (uint256);

    function distributeReward(uint256 _rewardTokenId, uint256 _amount) external;

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    function emergencySweepCooldown() external view returns (uint256);

    function emergencySweepLocks() external;

    function emergencySweepRewards() external;

    function exitPosition(uint256 _tokenId) external returns (uint256 tapAmount_);

    function getApproved(uint256 tokenId) external view returns (address);

    function getParticipation(uint256 _tokenId) external view returns (Participation memory participant);

    function getPosition(uint256 _tokenId)
        external
        view
        returns (Participation memory position, uint256[] memory claimables);

    function getRewardTokens() external view returns (IERC20[] memory);

    function getTotalDistPerVoteForWeek(uint256 _week, uint256 _rewardTokenId) external view returns (uint256);

    function getTypedDataHash(ERC721PermitStruct memory _permitData) external view returns (bytes32);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function lastEmergencySweep() external view returns (uint256);

    function lastProcessedWeek() external view returns (uint256);

    function maxRewardTokens() external view returns (uint256);

    function mintedTWTap() external view returns (uint256);

    function name() external view returns (string memory);

    function nftLoader() external view returns (address);

    function nonces(uint256 _tokenId) external view returns (uint256);

    function owner() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function participants(uint256)
        external
        view
        returns (
            uint256 averageMagnitude,
            bool hasVotingPower,
            bool divergenceForce,
            bool tapReleased,
            uint56 lockedAt,
            uint56 expiry,
            uint88 tapAmount,
            uint24 multiplier,
            uint40 lastInactive,
            uint40 lastActive
        );

    function participate(address _participant, uint256 _amount, uint256 _duration) external returns (uint256 tokenId);

    function paused() external view returns (bool);

    function permit(address spender, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    function renounceOwnership() external;

    function rewardTokenIndex(address) external view returns (uint256);

    function rewardTokens(uint256) external view returns (address);

    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;

    function setApprovalForAll(address operator, bool approved) external;

    function setBaseURI(string memory __baseURI) external;

    function setCluster(address _cluster) external;

    function setEmergencySweepCooldown(uint256 _emergencySweepCooldown) external;

    function setMaxRewardTokensLength(uint256 _length) external;

    function setMinWeightFactor(uint256 _minWeightFactor) external;

    function setNftLoader(address _nftLoader) external;

    function setPause(bool _pauseState) external;

    function setRescueMode(bool _rescueMode) external;

    function setVirtualTotalAmount(uint256 _virtualTotalAmount) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function symbol() external view returns (string memory);

    function tapOFT() external view returns (address);

    function tokenByIndex(uint256 index) external view returns (uint256);

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function transferFrom(address from, address to, uint256 tokenId) external;

    function transferOwnership(address newOwner) external;

    function twAML()
        external
        view
        returns (uint256 totalParticipants, uint256 averageMagnitude, uint256 totalDeposited, uint256 cumulative);

    function weekTotals(uint256) external view returns (int256 netActiveVotes);
}

struct Participation {
    uint256 averageMagnitude;
    bool hasVotingPower;
    bool divergenceForce;
    bool tapReleased;
    uint56 lockedAt;
    uint56 expiry;
    uint88 tapAmount;
    uint24 multiplier;
    uint40 lastInactive;
    uint40 lastActive;
}
