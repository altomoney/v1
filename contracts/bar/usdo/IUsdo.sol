pragma solidity ^0.8.22;

import {IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20PermitStruct} from "tap-utils/interfaces/common/ICommonData.sol";

struct UsdoMinter {
    uint256 mintCeiling;
    uint256 minted;
}

/**
 * @title IUsdo Interface
 * @notice Interface for the USDO stablecoin contract
 */
interface IUsdo is IOFT, IERC20, IERC20Permit {
    error Usdo_NotAuthorized();

    /// =====================
    /// Events
    /// =====================
    event SetMinterCeiling(address indexed _for, uint256 _mintCeiling);

    /// =====================
    /// View Functions
    /// =====================
    function minterCeiling(address minter) external view returns (uint256 mintCeiling, uint256 minted);

    /// =====================
    /// External Functions
    /// =====================
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function setPause(bool _pauseState) external;
    function setMinterCeiling(address _for, uint256 _mintCeiling) external;
}
