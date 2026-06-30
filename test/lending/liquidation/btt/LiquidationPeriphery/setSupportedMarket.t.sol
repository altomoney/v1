// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LiquidationPeripheryCommon} from "./LiquidationPeripheryCommon.t.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {BorrowMarketInitParams, BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ILiquidationPeripheryErrors,
    ILiquidationPeripheryEvents
} from "@alto/lending/liquidation/interfaces/ILiquidationPeriphery.sol";

contract LiquidationPeriphery_SetSupportedMarket_Test is LiquidationPeripheryCommon {
    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        periphery.setSupportedMarket(address(borrowMarket), true);
    }

    function test_RevertWhen_MarketIsZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.ZeroAddress.selector);
        periphery.setSupportedMarket(address(0), true);
    }

    function test_RevertWhen_MarketBorrowTokenDoesNotMatchBorrowToken() public {
        IMarket otherMarket = _deployBorrowMarketWithBorrowToken(address(new DUSD(address(endpoints[1]), OWNER)));

        vm.prank(OWNER);
        vm.expectRevert(ILiquidationPeripheryErrors.InvalidInput.selector);
        periphery.setSupportedMarket(address(otherMarket), true);
    }

    function test_ClearsSupportedMarketWithoutBorrowTokenValidation() public {
        IMarket otherMarket = _deployBorrowMarketWithBorrowToken(address(new DUSD(address(endpoints[1]), OWNER)));

        vm.prank(OWNER);
        periphery.setSupportedMarket(address(otherMarket), false);

        assertFalse(periphery.supportedMarkets(address(otherMarket)));
    }

    function test_SetsSupportedMarketAndEmitsSupportedMarketSet() public {
        vm.prank(OWNER);
        periphery.setSupportedMarket(address(borrowMarket), false);

        vm.expectEmit(true, true, false, true);
        emit ILiquidationPeripheryEvents.SupportedMarketSet(address(borrowMarket), true);

        vm.prank(OWNER);
        periphery.setSupportedMarket(address(borrowMarket), true);

        assertTrue(periphery.supportedMarkets(address(borrowMarket)));
    }

    function _deployBorrowMarketWithBorrowToken(address borrowTokenAddress) internal returns (IMarket) {
        vm.startPrank(OWNER);

        OracleMock marketOracle = new OracleMock();
        marketOracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(OWNER));

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: borrowTokenAddress,
                collateralToken: address(collateralToken),
                irm: address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this))),
                owner: OWNER,
                oracle: address(marketOracle),
                maxLtv: 0.75 ether,
                feeRecipient: makeAddr("FeeRecipient"),
                liquidationEngine: liquidationEngine
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        IMarket deployed = IMarket(MarketDeployer.deployBorrowMarket(borrowMarketInitParams));
        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_liquidationConfig());
        vm.stopPrank();

        return deployed;
    }
}
