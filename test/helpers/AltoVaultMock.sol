// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoVault} from "@alto/lending/vault/AltoVault.sol";

contract AltoVaultMock is AltoVault {
    constructor(
        address owner,
        uint256 timelock,
        address asset,
        string memory name,
        string memory symbol,
        address _marketRegistry
    ) AltoVault(owner, timelock, asset, name, symbol, _marketRegistry) {}

    function mockSetCap(address market, uint184 newSupplyCap) external {
        _setCap(market, newSupplyCap);
    }

    function mockSimulateWithdraw(uint256 assets) external view returns (uint256) {
        return _simulateWithdrawFromMarkets(assets);
    }

    function mockSetSupplyQueue(address[] memory _supplyQueue) external {
        supplyQueue = _supplyQueue;
    }
}
