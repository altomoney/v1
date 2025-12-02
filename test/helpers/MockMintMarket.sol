// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMarket} from "@alto-test/helpers/MockMarket.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";

contract MockMintMarket is MockMarket {
    using Uint128Converter for uint256;

    uint128 public claimableFeesAssets;

    function addClaimableFeesAssets(uint256 amount) external {
        claimableFeesAssets += uint128(amount);
    }

    function claimInterest(uint256 interest) external whenNotPaused returns (uint256) {
        if (feeRecipient == address(0) || interest > claimableFeesAssets) {
            revert AltoBaseMarketInvalidInput();
        }

        if (msg.sender != owner() && msg.sender != feeRecipient) {
            revert AltoBaseMarketUnauthorized();
        }

        if (interest == 0) {
            interest = claimableFeesAssets;
        }

        IMintableERC20(borrowToken).mint(feeRecipient, interest);
        claimableFeesAssets -= interest.toUint128();

        return interest;
    }
}

library MockMintMarketDeployer {
    function deployMarket(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public returns (MockMintMarket market) {
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(address(this)));

        market = new MockMintMarket();

        market.initialize(
            BaseMarketInitParams({
                borrowToken: _borrowToken,
                collateralToken: _collateralToken,
                irm: _irm,
                owner: _owner,
                oracle: _oracle,
                maxLtv: _maxLtv,
                feeRecipient: _feeRecipient,
                liquidationEngine: liquidationEngine
            }),
            _borrowOpeningFee
        );

        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_liquidationConfiguration);
    }
}
