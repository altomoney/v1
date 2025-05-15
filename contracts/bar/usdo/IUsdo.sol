pragma solidity ^0.8.22;

import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IUsdo Interface
 * @notice Interface for the USDO stablecoin contract
 */
interface IUsdo is IOFT, IERC20 {
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
