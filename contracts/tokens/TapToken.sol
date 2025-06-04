// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFT} from "@alto/utils/layerzero/OFT.sol";
import {OFTCore} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

// External
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// Tapioca
import {ITapToken} from "@alto/tokens/interfaces/ITapToken.sol";
import {ICluster} from "@alto/utils/interfaces/common/ICluster.sol";

/// @title Tapioca OFTv2 token
/// @notice OFT compatible TAP token
/// @dev Emissions E(x)= E(x-1) - E(x-1) * D with E being total supply a x week, and D the initial decay rate
contract TapToken is OFT, Pausable {
    uint256 public constant INITIAL_SUPPLY = 47_500_000 * 1e18; // Everything minus DSO
    uint256 public dso_supply = 52_500_000 * 1e18; // Emission supply for DSO

    /// @notice the a parameter used in the emission function;
    uint256 constant decay_rate = 8800000000000000; // 0.88%
    uint256 constant DECAY_RATE_DECIMAL = 1e18;

    /// @notice seconds in a week
    uint256 public immutable EPOCH_DURATION;

    /// @notice starts time for emissions
    /// @dev initialized in the constructor with block.timestamp
    uint256 public emissionsStartTime;

    /// @notice returns the amount of emitted TAP for a specific week
    /// @dev week is computed using (timestamp - emissionStartTime) / WEEK
    mapping(uint256 => uint256) public emissionForWeek;

    /// @notice returns the amount minted for a specific week
    /// @dev week is computed using (timestamp - emissionStartTime) / WEEK
    mapping(uint256 => uint256) public mintedInWeek;

    /// @notice returns the minter address
    address public minter;

    // ITWTAPv2 public twTap;

    ICluster public cluster;

    // ==========
    // *EVENTS*
    // ==========
    /// @notice event emitted when a new minter is set
    event MinterUpdated(address _old, address _new);
    /// @notice event emitted when a new emission is called
    event Emitted(uint256 indexed week, uint256 amount);
    /// @notice event emitted when new TAP is minted
    event Minted(address indexed _by, address indexed _to, uint256 _amount);
    /// @notice event emitted when new TAP is burned
    event Burned(address indexed _from, uint256 _amount);

    // ==========
    // *ERRORS*
    // ==========
    error NotValid(); // Generic error for simple functions
    error AddressWrong();
    error SupplyNotValid(); // Initial supply is not valid
    error AllowanceNotValid();
    error OnlyMinter();
    error TwTapAlreadySet();
    error InitStarted();
    error InitNotStarted();
    error InsufficientEmissions();
    error NotAuthorized();
    error twTapNotSet();

    // ===========
    // *MODIFIERS*
    // ===========

    // modifier twTapExists() {
    //     if (address(twTap) == address(0)) revert twTapNotSet();
    //     _;
    // }

    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    /**
     * @notice Creates a new TAP OFT type token
     * @dev The initial supply of 100M is not minted here as we have the wrap method
     *
     * Allocation:
     * ============
     * Contributors: 15m
     * Early supporters: 3_500_001
     * Supporters: 14,938,030.34
     * LTAP: 3989472714402321147960046
     * DAO: 6,561,968.66 + remaining for LBP
     * Airdrop: 2.5m
     * == 47.5M ==
     * DSO: 52.5m
     * == 100M ==
     *
     * @param _data.epochDuration The duration of an epoch in seconds.
     * @param _data.endpoint The layer zero address endpoint deployed on the current chain.
     * @param _data.contributors Address of the  contributors.
     * @param _data.earlySupporters Address of early supporters.
     * @param _data.supporters Address of supporters.
     * @param _data.lTap Address of the LBP redemption token, lTap.
     * @param _data.dao Address of the DAO.
     * @param _data.airdrop Address of the airdrop contract.
     * @param _data.owner Address of the conservator/owner.
     */
    constructor(ITapToken.TapTokenConstructorData memory _data)
        OFT("ALTO", "ALTO", _data.endpoint, _data.owner)
        Ownable(_data.owner)
    {
        cluster = ICluster(_data.cluster);
        if (_data.endpoint == address(0)) revert AddressWrong();

        if (_data.epochDuration == 0) revert NotValid();
        EPOCH_DURATION = _data.epochDuration;

        uint256 lbpSold = 3989472714402321147960046; // LBP sold 3.9m
        uint256 lbpRemaining = (1e18 * 5_000_000) - lbpSold; // Remaining of the  LBP goes to the DAO

        _mint(_data.contributors, 1e18 * 15_000_000);
        _mint(_data.earlySupporters, 1e18 * 3_500_001);
        _mint(_data.supporters, 1e18 * 14_938_030.34);
        _mint(_data.lTap, lbpSold);
        _mint(_data.dao, (1e18 * 6_561_968.66) + lbpRemaining);
        _mint(_data.airdrop, 1e18 * 2_500_000);
        if (totalSupply() != INITIAL_SUPPLY) revert SupplyNotValid();

        _transferOwnership(_data.owner);
    }

    /// =====================
    /// View
    /// =====================

    /**
     * @notice returns token's decimals
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Returns the current week
     */
    function getCurrentWeek() external view returns (uint256) {
        return _timestampToWeek(block.timestamp);
    }

    /**
     * @notice Returns the current week emission
     */
    function getCurrentWeekEmission() external view returns (uint256) {
        return emissionForWeek[_timestampToWeek(block.timestamp)];
    }

    /**
     * @notice Returns the current week given a timestamp
     * @param timestamp The timestamp to use to compute the week
     */
    function timestampToWeek(uint256 timestamp) external view returns (uint256) {
        if (timestamp == 0) {
            timestamp = block.timestamp;
        }
        if (timestamp < emissionsStartTime) return 0;

        return _timestampToWeek(timestamp);
    }

    /// =====================
    /// External
    /// =====================

    /**
     * @notice Initializes the emissions.
     * @dev Can be called only once. By Minter.
     */
    function initEmissions() external onlyMinter {
        if (emissionsStartTime != 0) revert InitStarted();
        emissionsStartTime = block.timestamp;
    }

    /**
     * @notice Mint TAP for the current week. Follow the emission function.
     *
     * @param _to Address to send the minted TAP to
     * @param _amount TAP amount
     */
    function extractTAP(address _to, uint256 _amount) external onlyMinter whenNotPaused {
        if (_amount == 0) revert NotValid();
        uint256 week = _timestampToWeek(block.timestamp);

        uint256 boostedTAP = balanceOf(address(this));
        uint256 availableTap = emissionForWeek[week] - mintedInWeek[week];

        // Check if there are enough emissions for the current week for the requested amount.
        if (availableTap < _amount) {
            // If there are not enough emissions, check if the boosted TAP can cover the difference.
            if (availableTap + boostedTAP < _amount) {
                revert InsufficientEmissions();
            } else {
                // If the boosted TAP can cover the difference, mint the available TAP.
                if (availableTap > 0) {
                    _mint(_to, availableTap);
                    mintedInWeek[week] += availableTap;
                    _amount -= availableTap;
                }

                // And transfer from the boosted TAP.
                _transfer(address(this), _to, _amount);
                emit Minted(msg.sender, _to, _amount);
                return;
            }
        }

        // Mint the requested amount if there are enough emissions.
        _mint(_to, _amount);
        mintedInWeek[week] += _amount;
        emit Minted(msg.sender, _to, _amount);
    }

    /**
     * @notice Burns TAP.
     * @param _amount TAP amount.
     */
    function removeTAP(uint256 _amount) external whenNotPaused {
        _burn(msg.sender, _amount);
        emit Burned(msg.sender, _amount);
    }

    /// =====================
    /// Minter
    /// =====================

    /**
     * @notice Emit the TAP for the current week. Follow the emission function.
     * If there are unclaimed emissions from the previous week, they are added to the current week.
     * If there are some TAP in the contract, use it as boosted TAP.
     *
     * @return the emitted amount.
     */
    function emitForWeek() external onlyMinter whenNotPaused returns (uint256) {
        if (emissionsStartTime == 0) revert InitNotStarted();

        uint256 week = _timestampToWeek(block.timestamp);
        if (emissionForWeek[week] > 0) return 0;

        // Compute unclaimed emission from last week and add it to the current week emission
        uint256 unclaimed;
        if (week > 0) {
            // Update DSO supply from last minted emissions
            dso_supply -= mintedInWeek[week - 1];

            // Push unclaimed emission from last week to the current week
            unclaimed = emissionForWeek[week - 1] - mintedInWeek[week - 1];
        }
        uint256 emission = _computeEmission();
        emission += unclaimed;

        emissionForWeek[week] = emission;
        emit Emitted(week, emission);

        return emission;
    }

    /// =====================
    /// Owner
    /// =====================

    /**
     * @notice Sets a new minter address.
     * @param _minter the new address
     */
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert NotValid();
        minter = _minter;
        emit MinterUpdated(minter, _minter);
    }

    // /**
    //  * @notice set the twTAP address, can be done only once.
    //  */
    // function setTwTAP(address _twTap) external onlyOwner {
    //     if (address(twTap) != address(0)) {
    //         revert TwTapAlreadySet();
    //     }
    //     twTap = ITWTAPv2(_twTap);
    // }

    /**
     * @notice Un/Pauses this contract.
     */
    function setPause(bool _pauseState) external {
        if (!cluster.hasRole(msg.sender, keccak256("PAUSABLE")) && msg.sender != owner()) revert NotAuthorized();
        if (_pauseState) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Sets the cluster address.
     * @param _cluster The address of the cluster.
     */
    function setCluster(address _cluster) external onlyOwner {
        cluster = ICluster(_cluster);
    }

    /// =====================
    /// Internal
    /// =====================

    /**
     * @dev Returns the current week given a timestamp
     * @param timestamp The timestamp to use to compute the week
     */
    function _timestampToWeek(uint256 timestamp) internal view returns (uint256) {
        return ((timestamp - emissionsStartTime) / EPOCH_DURATION);
    }

    /**
     *  @notice returns the available emissions for a given supply
     */
    function _computeEmission() internal view returns (uint256 result) {
        result = (dso_supply * decay_rate) / DECAY_RATE_DECIMAL;
    }
}
