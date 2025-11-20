// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarketUpgraded} from "./AltoBaseMarketUpgraded.sol";
import {
    BaseMarketInitParams,
    BorrowMarketInitParams,
    LiquidationConfiguration
} from "@alto/lending/interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @custom:oz-upgrades-from AltoBorrowMarket
contract AltoBorrowMarketUpgraded is AltoBaseMarketUpgraded {
    uint256 private _borrowOpeningFee;
    /// upgrade gap
    uint256[49] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(BorrowMarketInitParams memory _borrowMarketInitParams) public initializer {
        __AltoBaseMarket_init(_borrowMarketInitParams.baseMarketInitParams);
        _borrowOpeningFee = _borrowMarketInitParams.initialBorrowOpeningFee;
    }

    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function setBorrowOpeningFee(uint256 _borrowOpeningFeeWad) external onlyOwner {
        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    /// @dev Reinitializer for version 2 upgrade - initializes new storage variables
    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        reinitializer(2)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }

    function setAddedProperty1(uint256 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(uint256 value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(address value) external {
        addedProperty3 = value;
    }
}
