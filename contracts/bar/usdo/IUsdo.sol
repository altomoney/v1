pragma solidity ^0.8.19;

import {IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20PermitStruct} from "tap-utils/interfaces/periph/ITapiocaOmnichainEngine.sol";

/**
 * @title IUsdo Interface
 * @notice Interface for the USDO stablecoin contract
 */
interface IUsdo is IOFT, IERC20, IERC20Permit {
    error Usdo_NotAuthorized();


    /// =====================
    /// Events
    /// =====================
    event SetMinterStatus(address indexed _for, bool _status);
    event SetBurnerStatus(address indexed _for, bool _status);

    /// =====================
    /// View Functions
    /// =====================
    function fees() external view returns (uint256);
    function flashLoanHelper() external view returns (address);
    function allowedMinter(address minter) external view returns (bool);
    function allowedBurner(address burner) external view returns (bool);
    function getTypedDataHash(ERC20PermitStruct calldata _permitData) external view returns (bytes32);

    /// =====================
    /// External Functions
    /// =====================
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function addFlashloanFee(uint256 _fee) external;
    function setPause(bool _pauseState) external;
    function setFlashloanHelper(address _helper) external;
    function extractFees() external;
    function setMinterStatus(address _for, bool _status) external;
    function setBurnerStatus(address _for, bool _status) external;
}
