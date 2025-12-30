// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRewardsAdapter, BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";
import {MerkleRootManager} from "@alto/utils/MerkleRootManager.sol";
import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title AltoReferralWhitelistAdapter
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice A contract that allows users to set their referral address and receive rewards
/// this allows referrees to receive bonus discount and referrers to receive payment token share
contract AltoReferralWhitelistAdapter is IRewardsAdapter, MerkleRootManager, AltoOwnable2Step {
    error AltoReferralWhitelistAdapterInvalidInput();
    error AltoReferralWhitelistAdapterInvalidReferralAddress();
    error AltoReferralWhitelistAdapterInvalidReferralAlreadySet();
    error AltoReferralWhitelistAdapterInvalidProof();
    error AltoReferralWhitelistAdapterReferralAlreadyActivated();

    event BonusDiscountSet(uint256 bonusDiscount);
    event PaymentTokenShareSet(uint256 paymentTokenShare);
    event ReferralSet(
        address indexed setFor, address indexed referralAddressBefore, address indexed referralAddressAfter
    );
    event ReferralWhitelistSet(address indexed setFor, bool isWhitelisted);
    event PaymentTokenShareReceiverSet(address indexed setFor, address indexed paymentTokenShareReceiver);

    /// @notice The bonus discount for being the referred user
    uint256 public bonusDiscount;

    /// @notice The payment token share for being the referrer
    uint256 public paymentTokenShare;

    /// @notice The mapping of the referral addresses able to be set as a referred user
    /// @dev address => is whitelisted
    mapping(address => bool) public referralWhitelist;

    /// @notice The mapping of the payment token share receiver for a referral address
    /// @dev address => payment token share receiver
    mapping(address => address) public paymentTokenShareReceiver;

    /// @notice The mapping of the referral address set as a referred user
    /// @dev user => referral address
    mapping(address => address) public referral;

    /// @notice Implementation of abstract function from MerkleRootManager
    function _getOwner() internal view override returns (address) {
        return owner();
    }

    /// @notice Initializes the contract
    /// @param _bonusDiscount The initial bonus discount for being the referee (in MATH_PRECISION)
    /// @param _paymentTokenShare The initial payment token share for being the referrer (in MATH_PRECISION)
    constructor(uint256 _bonusDiscount, uint256 _paymentTokenShare) Ownable(msg.sender) {
        if (_bonusDiscount > 0.1 ether) {
            revert AltoReferralWhitelistAdapterInvalidInput();
        }
        if (_paymentTokenShare > 0.1 ether) {
            revert AltoReferralWhitelistAdapterInvalidInput();
        }

        bonusDiscount = _bonusDiscount;
        paymentTokenShare = _paymentTokenShare;

        emit BonusDiscountSet(_bonusDiscount);
        emit PaymentTokenShareSet(_paymentTokenShare);
    }

    /// @notice Sets the bonus discount for being the referee
    /// @param _bonusDiscount The bonus discount for being the referee (in MATH_PRECISION)
    /// @dev The bonus discount is capped at 10%
    function setBonusDiscount(uint256 _bonusDiscount) external onlyOwner {
        if (_bonusDiscount > 0.1 ether) {
            revert AltoReferralWhitelistAdapterInvalidInput();
        }

        bonusDiscount = _bonusDiscount;

        emit BonusDiscountSet(_bonusDiscount);
    }

    /// @notice Sets the payment token share for being the referrer
    /// @param _paymentTokenShare The payment token share for being the referrer (in MATH_PRECISION)
    /// @dev The payment token share is capped at 10%
    function setPaymentTokenShare(uint256 _paymentTokenShare) external onlyOwner {
        if (_paymentTokenShare > 0.1 ether) {
            revert AltoReferralWhitelistAdapterInvalidInput();
        }

        paymentTokenShare = _paymentTokenShare;

        emit PaymentTokenShareSet(_paymentTokenShare);
    }

    /// @notice Sets the referral address for a user
    /// @param referredUser The user to set the referral address for
    /// @param referralAddress The referral address for the user
    /// @dev only whitelisted addresses are allowed and resetting to address(0) is allowed
    function setReferral(address referredUser, address referralAddress) external onlyOwner {
        // don't allow setting a referral address if it is not whitelisted
        // resetting to address(0) is allowed
        if (!referralWhitelist[referralAddress] && referralAddress != address(0)) {
            revert AltoReferralWhitelistAdapterInvalidReferralAddress();
        }

        // don't allow self-referral
        if (referredUser == referralAddress) {
            revert AltoReferralWhitelistAdapterInvalidReferralAddress();
        }

        address referralAddressBefore = referral[referredUser];
        referral[referredUser] = referralAddress;

        emit ReferralSet(referredUser, referralAddressBefore, referralAddress);
    }

    /// @notice Sets the referral whitelist for an address
    /// @param referralAddress The address to set the referral whitelist for
    /// @param isWhitelisted Whether the address is whitelisted
    /// @dev only whitelisted addresses are allowed and resetting to false is allowed
    /// @dev removed addresses should be removed from the merkle root as well
    /// otherwise whitelisted referral can re-add themselves back to the whitelist
    function setReferralWhitelist(address referralAddress, bool isWhitelisted) external onlyOwner {
        referralWhitelist[referralAddress] = isWhitelisted;

        if (!isWhitelisted && paymentTokenShareReceiver[referralAddress] != address(0)) {
            paymentTokenShareReceiver[referralAddress] = address(0);
            emit PaymentTokenShareReceiverSet(referralAddress, address(0));
        }

        emit ReferralWhitelistSet(referralAddress, isWhitelisted);
    }

    /// @notice Sets the referral address for the caller
    /// @param referralAddress The referral address for the caller
    /// @dev only whitelisted addresses are allowed
    function activateReferral(address referralAddress) external {
        // referral address has to be whitelisted, otherwise the user can't set it
        if (!referralWhitelist[referralAddress]) {
            revert AltoReferralWhitelistAdapterInvalidReferralAddress();
        }

        // don't allow setting a referral address if the user already has a referral address and it is whitelisted
        // in case already set address was removed from the whitelist by an admin, the user can set a new one
        if (referral[msg.sender] != address(0) && referralWhitelist[referral[msg.sender]]) {
            revert AltoReferralWhitelistAdapterInvalidReferralAlreadySet();
        }

        // don't allow self-referral
        if (referralAddress == msg.sender) {
            revert AltoReferralWhitelistAdapterInvalidReferralAddress();
        }

        address referralAddressBefore = referral[msg.sender];
        referral[msg.sender] = referralAddress;
        emit ReferralSet(msg.sender, referralAddressBefore, referralAddress);
    }

    /// @notice Activates the referral whitelist for the caller
    /// @param proof The proof to activate the referral whitelist for the caller
    /// @dev only whitelisted addresses are allowed and resetting to false is allowed
    function activateReferralWhitelist(bytes32[] calldata proof) external {
        if (!_verifyProof(proof, keccak256(abi.encode(msg.sender)))) {
            revert AltoReferralWhitelistAdapterInvalidProof();
        }

        if (referralWhitelist[msg.sender]) {
            revert AltoReferralWhitelistAdapterReferralAlreadyActivated();
        }

        referralWhitelist[msg.sender] = true;
        emit ReferralWhitelistSet(msg.sender, true);
    }

    /// @notice Sets the payment token share receiver for the caller
    /// @param receiver The payment token share receiver for the caller
    /// @dev only whitelisted addresses are allowed and resetting to address(0) is allowed
    function setPaymentTokenShareReceiver(address receiver) external {
        if (!referralWhitelist[msg.sender]) {
            revert AltoReferralWhitelistAdapterInvalidReferralAddress();
        }

        if (paymentTokenShareReceiver[msg.sender] == receiver) {
            revert AltoReferralWhitelistAdapterInvalidInput();
        }

        paymentTokenShareReceiver[msg.sender] = receiver;

        emit PaymentTokenShareReceiverSet(msg.sender, receiver);
    }

    /// @inheritdoc IRewardsAdapter
    function getBonusRewardInfo(address onBehalf) external view returns (BonusRewardInfo memory) {
        address referralAddress = referral[onBehalf];
        // we return nothing on unset referral address or if the referral address is not whitelisted
        if (referralAddress == address(0) || !referralWhitelist[referralAddress]) {
            return BonusRewardInfo({bonusDiscount: 0, paymentTokenShare: 0, paymentTokenShareReceiver: address(0)});
        }

        address receiver = paymentTokenShareReceiver[referralAddress];
        if (receiver == address(0)) {
            receiver = referralAddress;
        }

        return BonusRewardInfo({
            bonusDiscount: bonusDiscount, paymentTokenShare: paymentTokenShare, paymentTokenShareReceiver: receiver
        });
    }
}
