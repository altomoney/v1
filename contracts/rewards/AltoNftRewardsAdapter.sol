// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewardsAdapter, BonusRewardInfo} from "./interfaces/IRewardsAdapter.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title AltoNftRewards
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract that allows users to set their NFT referral ID and receive rewards
/// this allows referrees to receive bonus discount and referrers to receive payment token share
contract AltoNftRewardsAdapter is IRewardsAdapter, Ownable2Step {
    error AltoNftRewardsInvalidReferralNftId();
    error AltoNftRewardsInvalidInput();

    event NftReferralIdSet(address indexed onBehalf, uint256 indexed referralNftId);
    event BonusDiscountSet(uint256 bonusDiscount);
    event PaymentTokenShareSet(uint256 paymentTokenShare);
    event PearlClubNftAddressInitialized(address nftAddress);

    /// @notice The address of the Pearl Club NFT
    address public immutable PEARL_CLUB_NFT_ADDRESS;

    /// @notice The bonus discount for being the referee of the NFT
    uint256 public bonusDiscount;

    /// @notice The payment token share for being the referrer of the NFT
    uint256 public paymentTokenShare;

    /// @notice The mapping of the NFT referral ID to the address
    mapping(address => uint256) public nftReferralId;

    /// @notice Initializes the contract
    /// @param _nftAddress The address of the Pearl Club NFT
    /// @param _bonusDiscount The initial bonus discount for being the referee of the NFT (in MATH_PRECISION)
    /// @param _paymentTokenShare The initial payment token share for being the referrer of the NFT (in MATH_PRECISION)
    constructor(address _nftAddress, uint256 _bonusDiscount, uint256 _paymentTokenShare) Ownable(msg.sender) {
        if (_nftAddress == address(0)) {
            revert AltoNftRewardsInvalidInput();
        }
        if (_bonusDiscount > 0.1 ether) {
            revert AltoNftRewardsInvalidInput();
        }
        if (_paymentTokenShare > 0.1 ether) {
            revert AltoNftRewardsInvalidInput();
        }

        PEARL_CLUB_NFT_ADDRESS = _nftAddress;
        bonusDiscount = _bonusDiscount;
        paymentTokenShare = _paymentTokenShare;

        emit BonusDiscountSet(_bonusDiscount);
        emit PaymentTokenShareSet(_paymentTokenShare);
        emit PearlClubNftAddressInitialized(_nftAddress);
    }

    /// @notice Sets the bonus discount for being the referee of the NFT
    /// @param _bonusDiscount The bonus discount for being the referee of the NFT (in MATH_PRECISION)
    /// @dev The bonus discount is capped at 10%
    function setBonusDiscount(uint256 _bonusDiscount) external onlyOwner {
        if (_bonusDiscount > 0.1 ether) {
            revert AltoNftRewardsInvalidInput();
        }
        bonusDiscount = _bonusDiscount;
        emit BonusDiscountSet(_bonusDiscount);
    }

    /// @notice Sets the payment token share for being the referrer of the NFT
    /// @param _paymentTokenShare The payment token share for being the referrer of the NFT (in MATH_PRECISION)
    /// @dev The payment token share is capped at 10%
    function setPaymentTokenShare(uint256 _paymentTokenShare) external onlyOwner {
        if (_paymentTokenShare > 0.1 ether) {
            revert AltoNftRewardsInvalidInput();
        }
        paymentTokenShare = _paymentTokenShare;
        emit PaymentTokenShareSet(_paymentTokenShare);
    }

    /// @notice Sets the NFT referral ID for the caller
    /// @param referralNftId The NFT referral ID for the caller
    /// @dev only non-team NFTs are allowed up to and including 700
    function setNftReferralId(uint256 referralNftId) external {
        // nft is fully minted, valid range is [1-700]
        // we allow 0 as user can just cancel their referral
        if (referralNftId > 700) {
            revert AltoNftRewardsInvalidReferralNftId();
        }

        address nftOwner;
        try IERC721(PEARL_CLUB_NFT_ADDRESS).ownerOf(referralNftId) returns (address owner) {
            nftOwner = owner;
        } catch {
            nftOwner = address(0);
        }

        // we don't allow self-referral
        if (nftOwner == msg.sender) {
            revert AltoNftRewardsInvalidReferralNftId();
        }

        nftReferralId[msg.sender] = referralNftId;
        emit NftReferralIdSet(msg.sender, referralNftId);
    }

    /// @inheritdoc IRewardsAdapter
    function getBonusRewardInfo(address onBehalf) external view returns (BonusRewardInfo memory) {
        uint256 referralNftId = nftReferralId[onBehalf];
        // we return nothing on unset referral nft id
        if (referralNftId == 0) {
            return BonusRewardInfo({bonusDiscount: 0, paymentTokenShare: 0, paymentTokenShareReceiver: address(0)});
        }

        address ownerOfNft;

        // all NFTs were minted, so we can safely try to get the owner
        try IERC721(PEARL_CLUB_NFT_ADDRESS).ownerOf(referralNftId) returns (address nftOwner) {
            ownerOfNft = nftOwner;
        } catch {
            ownerOfNft = address(0);
        }

        // we don't allow self-referral
        if (ownerOfNft == onBehalf) {
            return BonusRewardInfo({bonusDiscount: 0, paymentTokenShare: 0, paymentTokenShareReceiver: address(0)});
        }

        // we are okay with any address as paymentTokenShareReceiver
        // because the referee should still be able to receive bonus discount
        // and the paymentTokenShareReceiver should be verified by the distributor
        return BonusRewardInfo({
            bonusDiscount: bonusDiscount,
            paymentTokenShare: paymentTokenShare,
            paymentTokenShareReceiver: ownerOfNft
        });
    }
}
