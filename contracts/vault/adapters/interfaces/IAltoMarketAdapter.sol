// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IAltoMarketAdapter is IAdapter {
    /* EVENTS */

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Accept(bytes4 indexed selector, bytes data);
    event Abdicate(bytes4 indexed selector);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event BurnShares(address indexed market, uint256 supplyShares);
    event Allocate(address indexed market, uint256 newAllocation, uint256 mintedShares);
    event Deallocate(address indexed market, uint256 newAllocation, uint256 burnedShares);

    /* ERRORS */

    error Abdicated();
    error AutomaticallyTimelocked();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error LoanAssetMismatch();
    error SharePriceAboveOne();
    error TimelockNotDecreasing();
    error TimelockNotExpired();
    error TimelockNotIncreasing();
    error Unauthorized();

    /* VIEW FUNCTIONS */

    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function markets(uint256 index) external view returns (address);
    function supplyShares(address market) external view returns (uint256);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketsLength() external view returns (uint256);
    function allocation(address market) external view returns (uint256);
    function expectedSupplyAssets(address market) external view returns (uint256);
    function ids(address market) external view returns (bytes32[] memory);
    function timelock(bytes4 selector) external view returns (uint256);
    function abdicated(bytes4 selector) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);

    /* NON-VIEW FUNCTIONS */

    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicate(bytes4 selector) external;
    function setSkimRecipient(address newSkimRecipient) external;
    function burnShares(address market) external;
    function skim(address token) external;
}
