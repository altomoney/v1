// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Tapioca
import {IPausable} from "src/tap-utils/interfaces/common/IPausable.sol";
import {ICluster} from "src/tap-utils/interfaces/common/ICluster.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract Pauser is Ownable {
    ICluster public cluster;

    enum SpecialStrategyType {
        Deposit,
        Withdraw
    }

    enum PausableContractType {
        Singularity, // it does not contain `updatePauseAll` like BB or Origins
        NonSingularityMarket, // it includes `updatePauseAll`
        SpecialStrategy, // it has `setPause(bool, uint256)
        Generic // method is called `setPause`

    }

    struct PausableContract {
        address _contract;
        PausableContractType _contractType;
    }

    PausableContract[] public pausableAddresses;
    mapping(address _contract => bool _registered) public registeredContracts;

    error Pauser_NotAuthorized();
    error Pauser_NotWhitelisted(address _who);
    error Pauser_NotValid();

    event PauseToggledFor(address indexed _contract, bool _pause);
    event EmergencyTogglePause(bool _pause);

    constructor(address _cluster, address _owner) Ownable(_owner) {
        cluster = ICluster(_cluster);
    }

    modifier onlyAllowed() {
        if (msg.sender != owner() && !cluster.hasRole(msg.sender, keccak256("PAUSER_MANAGER"))) {
            revert Pauser_NotAuthorized();
        }
        _;
    }

    // ************************* //
    // *** OWNER FUNCTIONS ***** //
    // ************************* //
    /// @notice add pauable contract
    /// @param _contract the pausable contract
    /// @param _type the pusable type
    function addPausableAddress(address _contract, PausableContractType _type) external onlyOwner {
        if (registeredContracts[_contract]) revert Pauser_NotAuthorized();
        registeredContracts[_contract] = true;
        pausableAddresses.push(PausableContract(_contract, _type));
    }

    /// @notice remove pauable contract
    /// @param _contract the pausable contract
    function removePausableAddress(address _contract) external onlyOwner {
        uint256 index = _findIndex(_contract);
        pausableAddresses[index] = pausableAddresses[pausableAddresses.length - 1];
        pausableAddresses.pop();
        registeredContracts[_contract] = false;
    }

    // ************************** //
    // *** PUBLIC FUNCTIONS ***** //
    // ************************** //
    function toggleEmergencyPauseForType(bool _pause, PausableContractType _type) external onlyAllowed {
        uint256 len = pausableAddresses.length;
        for (uint256 i; i < len; i++) {
            PausableContract memory _pausable = pausableAddresses[i];
            if (_pausable._contractType == _type) {
                _togglePauseHelper(_pausable, _pause);
            }
        }
    }

    function toggleEmergencyPause(bool _pause) external onlyAllowed {
        uint256 len = pausableAddresses.length;
        for (uint256 i; i < len; i++) {
            PausableContract memory _pausable = pausableAddresses[i];
            _togglePauseHelper(_pausable, _pause);
        }
        emit EmergencyTogglePause(_pause);
    }

    /// @notice pauses contract
    /// @param _pausable address to pause/unpause
    /// @param _pause true/false
    /// @dev for Penrose, Leverage executors, Usdo, Toft, Magnetar
    function togglePause(IPausable _pausable, bool _pause) external onlyAllowed {
        if (!registeredContracts[address(_pausable)]) revert Pauser_NotValid();
        uint256 _index = _findIndex(address(_pausable));
        PausableContract memory _pausable = pausableAddresses[_index];
        _togglePauseHelper(_pausable, _pause);
    }

    // *************************** //
    // *** PRIVATE FUNCTIONS ***** //
    // *************************** //
    function _togglePauseHelper(PausableContract memory _pausable, bool _pause) private {
        if (_pausable._contractType == PausableContractType.SpecialStrategy) {
            _toggleSpecialStrategy(IPausable(_pausable._contract), _pause);
        } else if (_pausable._contractType == PausableContractType.Generic) {
            _toggleGenericPause(IPausable(_pausable._contract), _pause);
        }
    }

    function _toggleGenericPause(IPausable _pausable, bool _pause) private {
        if (!cluster.isWhitelisted(0, address(this))) revert Pauser_NotWhitelisted(address(this));
        if (!cluster.isWhitelisted(0, address(_pausable))) revert Pauser_NotWhitelisted(address(_pausable));

        _pausable.setPause(_pause);
        emit PauseToggledFor(address(_pausable), _pause);
    }

    function _toggleSpecialStrategy(IPausable _pausable, bool _pause) private {
        if (!cluster.isWhitelisted(0, address(this))) revert Pauser_NotWhitelisted(address(this));
        if (!cluster.isWhitelisted(0, address(_pausable))) revert Pauser_NotWhitelisted(address(_pausable));

        _pausable.setPause(_pause, uint256(SpecialStrategyType.Deposit));
        _pausable.setPause(_pause, uint256(SpecialStrategyType.Withdraw));
        emit PauseToggledFor(address(_pausable), _pause);
    }

    function _findIndex(address _address) private view returns (uint256) {
        uint256 len = pausableAddresses.length;
        for (uint256 i; i < len; i++) {
            if (pausableAddresses[i]._contract == _address) {
                return i;
            }
        }
        revert Pauser_NotValid();
    }
}
