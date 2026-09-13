// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {
    BaseMarketInitParams,
    BorrowMarketInitParams,
    MintMarketInitParams,
    IMarketErrors
} from "@alto/lending/interfaces/IMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";

contract MarketInitializationTest is Test {
    BaseMarketInitParams internal baseParams;

    function setUp() public {
        baseParams = BaseMarketInitParams({
            borrowToken: address(new ERC20MockMintable("Borrow", "B")),
            collateralToken: address(new ERC20MockMintable("Collateral", "C")),
            irm: address(0),
            owner: address(this),
            emergencyAdmin: address(this),
            oracle: address(new OracleMock()),
            maxLtv: 0.75 ether,
            feeRecipient: address(this),
            liquidationEngine: address(0)
        });
    }

    function test_BorrowDeploymentRevertsWithoutLiquidationEngine() public {
        AltoBorrowMarket implementation = new AltoBorrowMarket();
        bytes memory data = abi.encodeCall(AltoBorrowMarket.initialize, (_borrowParams()));

        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        new ERC1967Proxy(address(implementation), data);
    }

    function test_MintDeploymentRevertsWithoutLiquidationEngine() public {
        AltoMintMarket implementation = new AltoMintMarket();
        bytes memory data = abi.encodeCall(AltoMintMarket.initialize, (_mintParams()));

        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        new ERC1967Proxy(address(implementation), data);
    }

    function test_BorrowDeploymentRegistersLiquidationEngine() public {
        DlbDcfPriorityLiquidationEngine engine = new DlbDcfPriorityLiquidationEngine(address(this));
        baseParams.liquidationEngine = address(engine);
        AltoBorrowMarket market = AltoBorrowMarket(
            address(
                new ERC1967Proxy(
                    address(new AltoBorrowMarket()), abi.encodeCall(AltoBorrowMarket.initialize, (_borrowParams()))
                )
            )
        );

        assertEq(market.liquidationEngine(), address(engine));
        assertEq(engine.market(), address(market));
        assertEq(market.owner(), address(this));
    }

    function test_MintDeploymentRegistersLiquidationEngine() public {
        DlbDcfPriorityLiquidationEngine engine = new DlbDcfPriorityLiquidationEngine(address(this));
        baseParams.liquidationEngine = address(engine);
        AltoMintMarket market = AltoMintMarket(
            address(
                new ERC1967Proxy(
                    address(new AltoMintMarket()), abi.encodeCall(AltoMintMarket.initialize, (_mintParams()))
                )
            )
        );

        assertEq(market.liquidationEngine(), address(engine));
        assertEq(engine.market(), address(market));
        assertEq(market.owner(), address(this));
    }

    function _borrowParams() internal view returns (BorrowMarketInitParams memory) {
        return BorrowMarketInitParams({
            baseMarketInitParams: baseParams, initialBorrowOpeningFee: 0, supplyCapAssets: 0, initialInterestFee: 0
        });
    }

    function _mintParams() internal view returns (MintMarketInitParams memory) {
        return
            MintMarketInitParams({
                baseMarketInitParams: baseParams, debtCeiling: 1000 ether, initialBorrowOpeningFee: 0
            });
    }
}
