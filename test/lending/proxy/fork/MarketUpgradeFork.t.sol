// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AltoBorrowMarketUpgradedFork} from "./contracts/AltoBorrowMarketUpgradedFork.sol";
import {
    AltoBorrowMarketUpgradedOriginalBaseMarketFork
} from "./contracts/AltoBorrowMarketUpgradedOriginalBaseMarketFork.sol";
import {AltoMintMarketUpgradedFork} from "./contracts/AltoMintMarketUpgradedFork.sol";
import {
    AltoMintMarketUpgradedOriginalBaseMarketFork
} from "./contracts/AltoMintMarketUpgradedOriginalBaseMarketFork.sol";
import {MarketUpgradeForkTestBase} from "./MarketUpgradeForkTestBase.sol";

/// @notice Fork tests for market upgrades after liquidation-periphery deployment phases.
contract MarketUpgradeForkTest is MarketUpgradeForkTestBase {
    string internal constant BORROW_UPGRADED_FORK_CONTRACT = "AltoBorrowMarketUpgradedFork.sol";
    string internal constant BORROW_ORIGINAL_BASE_FORK_CONTRACT = "AltoBorrowMarketUpgradedOriginalBaseMarketFork.sol";
    string internal constant MINT_UPGRADED_FORK_CONTRACT = "AltoMintMarketUpgradedFork.sol";
    string internal constant MINT_ORIGINAL_BASE_FORK_CONTRACT = "AltoMintMarketUpgradedOriginalBaseMarketFork.sol";

    // --- borrow market ---

    function test_borrowMarket_upgradeWhenBaseWasUpgraded() public {
        IMarket[] memory markets = _allBorrowMarkets();
        assertEq(markets.length, 5, "expected 5 borrow markets");

        for (uint256 i; i < markets.length; ++i) {
            _assertBorrowMarketBaseUpgrade(markets[i], i);
        }
    }

    function test_borrowMarket_upgradeWhenBorrowOnlyWasUpgraded() public {
        IMarket[] memory markets = _allBorrowMarkets();
        assertEq(markets.length, 5, "expected 5 borrow markets");

        for (uint256 i; i < markets.length; ++i) {
            _assertBorrowMarketBorrowOnlyUpgrade(markets[i]);
        }
    }

    function test_borrowMarket_upgradeWhenNotOwner() public {
        IMarket[] memory markets = _allBorrowMarkets();
        assertEq(markets.length, 5, "expected 5 borrow markets");

        for (uint256 i; i < markets.length; ++i) {
            vm.warp(block.timestamp + 1 days);
            markets[i].accrueInterest();

            _assertUpgradeRevertsWhenNotOwner(
                address(markets[i]),
                BORROW_ORIGINAL_BASE_FORK_CONTRACT,
                address(new AltoBorrowMarketUpgradedOriginalBaseMarketFork()),
                abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarketFork.initializeV2, ())
            );
        }
    }

    // --- mint market ---

    function test_mintMarket_upgradeWhenBaseWasUpgraded() public {
        IMarket[] memory markets = _allMintMarkets();
        assertEq(markets.length, 7, "expected 7 mint markets");

        for (uint256 i; i < markets.length; ++i) {
            _assertMintMarketBaseUpgrade(markets[i], i);
        }
    }

    function test_mintMarket_upgradeWhenMintOnlyWasUpgraded() public {
        IMarket[] memory markets = _allMintMarkets();
        assertEq(markets.length, 7, "expected 7 mint markets");

        for (uint256 i; i < markets.length; ++i) {
            _assertMintMarketMintOnlyUpgrade(markets[i]);
        }
    }

    function test_mintMarket_upgradeWhenNotOwner() public {
        IMarket[] memory markets = _allMintMarkets();
        assertEq(markets.length, 7, "expected 7 mint markets");

        for (uint256 i; i < markets.length; ++i) {
            vm.warp(block.timestamp + 1 days);
            markets[i].accrueInterest();

            _assertUpgradeRevertsWhenNotOwner(
                address(markets[i]),
                MINT_ORIGINAL_BASE_FORK_CONTRACT,
                address(new AltoMintMarketUpgradedOriginalBaseMarketFork()),
                abi.encodeCall(AltoMintMarketUpgradedOriginalBaseMarketFork.initializeV2, ())
            );
        }
    }

    function _assertBorrowMarketBaseUpgrade(IMarket market, uint256 i) internal {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getMarketData(market);
        _assertMarketNotEmpty(market, marketDataBefore);
        _assertPeripheryAuthorized(marketDataBefore, "periphery should be authorized before upgrade");

        vm.startPrank(input.contracts.timelock);
        _upgradeProxy(
            address(market),
            BORROW_UPGRADED_FORK_CONTRACT,
            address(new AltoBorrowMarketUpgradedFork()),
            abi.encodeCall(AltoBorrowMarketUpgradedFork.initializeV2, (i, i + 1, address(uint160(i + 2))))
        );
        vm.stopPrank();

        AltoBorrowMarketUpgradedFork upgraded = AltoBorrowMarketUpgradedFork(address(market));
        assertEq(upgraded.addedProperty1(), i);
        assertEq(upgraded.addedProperty2(), i + 1);
        assertEq(upgraded.addedProperty3(), address(uint160(i + 2)));

        upgraded.setAddedProperty1(100);
        upgraded.setAddedProperty2(200);
        upgraded.setAddedProperty3(address(0x123));
        assertEq(upgraded.addedProperty1(), 100);
        assertEq(upgraded.addedProperty2(), 200);
        assertEq(upgraded.addedProperty3(), address(0x123));

        MarketData memory marketDataAfter = _getMarketData(market);
        _assertMarketDataEqual(marketDataBefore, marketDataAfter);
        _assertPeripheryAuthorized(marketDataAfter, "periphery should stay authorized after upgrade");

        market.accrueInterest();
    }

    function _assertBorrowMarketBorrowOnlyUpgrade(IMarket market) internal {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getMarketData(market);
        _assertMarketNotEmpty(market, marketDataBefore);
        _assertPeripheryAuthorized(marketDataBefore, "periphery should be authorized before upgrade");

        vm.startPrank(input.contracts.timelock);
        _upgradeProxy(
            address(market),
            BORROW_ORIGINAL_BASE_FORK_CONTRACT,
            address(new AltoBorrowMarketUpgradedOriginalBaseMarketFork()),
            abi.encodeCall(AltoBorrowMarketUpgradedOriginalBaseMarketFork.initializeV2, ())
        );
        vm.stopPrank();

        AltoBorrowMarketUpgradedOriginalBaseMarketFork upgraded =
            AltoBorrowMarketUpgradedOriginalBaseMarketFork(address(market));
        upgraded.setAddedProperty1(100);
        upgraded.setAddedProperty2(address(0x123));
        upgraded.setAddedProperty3(200);
        assertEq(upgraded.addedProperty1(), 100);
        assertEq(upgraded.addedProperty2(), address(0x123));
        assertEq(upgraded.addedProperty3(), 200);

        MarketData memory marketDataAfter = _getMarketData(market);
        _assertMarketDataEqual(marketDataBefore, marketDataAfter, true);
        _assertPeripheryAuthorized(marketDataAfter, "periphery should stay authorized after upgrade");

        market.accrueInterest();
    }

    function _assertMintMarketBaseUpgrade(IMarket market, uint256 i) internal {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getMarketData(market);
        _assertMarketNotEmpty(market, marketDataBefore);
        _assertPeripheryAuthorized(marketDataBefore, "periphery should be authorized before upgrade");

        vm.startPrank(input.contracts.timelock);
        _upgradeProxy(
            address(market),
            MINT_UPGRADED_FORK_CONTRACT,
            address(new AltoMintMarketUpgradedFork()),
            abi.encodeCall(AltoMintMarketUpgradedFork.initializeV2, (i, i + 1, address(uint160(i + 2))))
        );
        vm.stopPrank();

        AltoMintMarketUpgradedFork upgraded = AltoMintMarketUpgradedFork(address(market));
        assertEq(upgraded.addedProperty1(), i);
        assertEq(upgraded.addedProperty2(), i + 1);
        assertEq(upgraded.addedProperty3(), address(uint160(i + 2)));

        upgraded.setAddedProperty1(100);
        upgraded.setAddedProperty2(200);
        upgraded.setAddedProperty3(address(0x123));
        assertEq(upgraded.addedProperty1(), 100);
        assertEq(upgraded.addedProperty2(), 200);
        assertEq(upgraded.addedProperty3(), address(0x123));

        MarketData memory marketDataAfter = _getMarketData(market);
        _assertMarketDataEqual(marketDataBefore, marketDataAfter);
        _assertPeripheryAuthorized(marketDataAfter, "periphery should stay authorized after upgrade");

        market.accrueInterest();
    }

    function _assertMintMarketMintOnlyUpgrade(IMarket market) internal {
        vm.warp(block.timestamp + 1 days);
        market.accrueInterest();

        MarketData memory marketDataBefore = _getMarketData(market);
        _assertMarketNotEmpty(market, marketDataBefore);
        _assertPeripheryAuthorized(marketDataBefore, "periphery should be authorized before upgrade");

        vm.startPrank(input.contracts.timelock);
        _upgradeProxy(
            address(market),
            MINT_ORIGINAL_BASE_FORK_CONTRACT,
            address(new AltoMintMarketUpgradedOriginalBaseMarketFork()),
            abi.encodeCall(AltoMintMarketUpgradedOriginalBaseMarketFork.initializeV2, ())
        );
        vm.stopPrank();

        AltoMintMarketUpgradedOriginalBaseMarketFork upgraded =
            AltoMintMarketUpgradedOriginalBaseMarketFork(address(market));
        upgraded.setAddedProperty1(100);
        upgraded.setAddedProperty2(address(0x123));
        upgraded.setAddedProperty3(200);
        assertEq(upgraded.addedProperty1(), 100);
        assertEq(upgraded.addedProperty2(), address(0x123));
        assertEq(upgraded.addedProperty3(), 200);

        MarketData memory marketDataAfter = _getMarketData(market);
        _assertMarketDataEqual(marketDataBefore, marketDataAfter, true);
        _assertPeripheryAuthorized(marketDataAfter, "periphery should stay authorized after upgrade");

        market.accrueInterest();
    }

    function _assertUpgradeRevertsWhenNotOwner(
        address proxy,
        string memory contractName,
        address unsafeImpl,
        bytes memory data
    ) internal {
        if (_shouldUseSafeProxy()) {
            try this.upgradeProxyExternal(proxy, contractName, data) {
                assertTrue(false, "expected upgrade to revert when caller is not owner");
            } catch (bytes memory reason) {
                bytes memory expectedError =
                    abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));
                assertEq(reason, expectedError, "unexpected revert reason");
            }
        } else {
            try this.upgradeProxyExternalUnsafe(proxy, unsafeImpl, data) {
                assertTrue(false, "expected upgrade to revert when caller is not owner");
            } catch (bytes memory reason) {
                bytes memory expectedError =
                    abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));
                assertEq(reason, expectedError, "unexpected revert reason");
            }
        }
    }
}
