// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {BaseMarketInitParams, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
contract AltoBorrowMarketUpgradedOriginalBaseMarket is AltoBaseMarket {
    uint128 public addedProperty1;

    address public addedProperty2;

    uint128 public addedProperty3;

    /// upgrade gap (previous slot has 16 bytes left)
    uint256[48] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(BaseMarketInitParams memory _baseMarketInitParams) public initializer {
        __AltoBaseMarket_init(_baseMarketInitParams, MarketType.BORROW);
    }

    function borrowOpeningFee() public view override returns (uint256) {
        return 0;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
    }

    /// @dev Reinitializer for version 2 upgrade - initializes new storage variables
    function initializeV2() public reinitializer(2) {}

    function setAddedProperty1(uint128 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(address value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(uint128 value) external {
        addedProperty3 = value;
    }
}
