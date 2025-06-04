// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

interface IAltoToken is IOFT, IMintableERC20 {
    error AltoTokenNotAuthorized();

    event SetMinterStatus(address indexed _for, bool _status);
    event SetBurnerStatus(address indexed _for, bool _status);

    function allowedMinter(address minter) external view returns (bool);
    function allowedBurner(address burner) external view returns (bool);

    function setMinterStatus(address _for, bool _status) external;
    function setBurnerStatus(address _for, bool _status) external;
}
