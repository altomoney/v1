// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

/**
 * @title IDUSD Interface
 * @notice Interface for the DUSD stablecoin contract
 */
interface IDUSD is IOFT, IMintableERC20 {
    error DUSDNotAuthorized();

    event SetMinterStatus(address indexed _for, bool _status);
    event SetBurnerStatus(address indexed _for, bool _status);

    function fees() external view returns (uint256);
    function flashLoanHelper() external view returns (address);
    function allowedMinter(address minter) external view returns (bool);
    function allowedBurner(address burner) external view returns (bool);

    function addFlashloanFee(uint256 _fee) external;
    function setFlashloanHelper(address _helper) external;
    function extractFees() external;
    function setMinterStatus(address _for, bool _status) external;
    function setBurnerStatus(address _for, bool _status) external;
}
