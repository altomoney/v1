// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ErpOffboard02Json, SafeTransaction} from "./ErpOffboard02Json.sol";
import {IAltoVault, IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Generates the final Timelock batch for ordinary-path Batch C recovery.
/// @dev The Vault allocator is an EOA. This script intentionally does not generate `setSupplyQueue` or
/// `updateWithdrawQueue` calldata. Run it only after the allocator has removed every target market from both queues.
/// This script does not implement the exceptional non-zero-Vault-supply removal path.
contract BatchCScript is ErpOffboard02Json {
    string public constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    uint256 private constant TRANSACTIONS_PER_MARKET = 6;

    function run() external {
        require(block.chainid == 1, "Batch C: Ethereum mainnet only");

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        address timelock = vm.parseJsonAddress(addresses, ".contracts.timelock");
        address marketRegistry = vm.parseJsonAddress(addresses, ".contracts.marketRegistry");
        address adapter = vm.parseJsonAddress(addresses, ".contracts.altoAdapter");
        address liquidationPeriphery = vm.parseJsonAddress(addresses, ".contracts.liquidationPeriphery");

        (
            address[] memory borrowMarkets,
            address[] memory leverages,
            address[] memory leverageSwappers,
            address[] memory affectedVaults
        ) = recoveryConfiguration();

        _validateConfiguration(borrowMarkets, leverages, leverageSwappers, affectedVaults);
        _validateZeroDebt(borrowMarkets);
        _validateVaultRemovalComplete(borrowMarkets, affectedVaults);
        _validateFinalRemovalState(
            timelock, marketRegistry, adapter, liquidationPeriphery, borrowMarkets, leverages, leverageSwappers
        );

        SafeTransaction[] memory transactions = _finalRemovalTransactions(
            marketRegistry, adapter, liquidationPeriphery, borrowMarkets, leverages, leverageSwappers
        );

        _writeTimelockPair(
            "batch-c-final-removal",
            "ERP-OFFBOARD-02 - Batch C Final Registry and Integration Removal",
            MAINNET_TIMELOCK_SAFE,
            timelock,
            TimelockController(payable(timelock)).getMinDelay(),
            transactions
        );
    }

    function _validateConfiguration(
        address[] memory borrowMarkets,
        address[] memory leverages,
        address[] memory leverageSwappers,
        address[] memory affectedVaults
    ) private pure {
        require(borrowMarkets.length != 0, "Batch C: no markets");
        require(borrowMarkets.length == leverages.length, "Batch C: market/leverage length mismatch");
        require(borrowMarkets.length == leverageSwappers.length, "Batch C: market/swapper length mismatch");
        require(affectedVaults.length != 0, "Batch C: no affected Vaults");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            require(
                borrowMarkets[i] != address(0) && leverages[i] != address(0) && leverageSwappers[i] != address(0),
                "Batch C: zero market integration"
            );
            for (uint256 j; j < i; ++j) {
                require(borrowMarkets[i] != borrowMarkets[j], "Batch C: duplicate market");
            }
        }

        for (uint256 i; i < affectedVaults.length; ++i) {
            require(affectedVaults[i] != address(0), "Batch C: zero Vault");
            for (uint256 j; j < i; ++j) {
                require(affectedVaults[i] != affectedVaults[j], "Batch C: duplicate Vault");
            }
        }
    }

    function _validateZeroDebt(address[] memory borrowMarkets) private view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            Balance memory borrowed = IMarket(borrowMarkets[i]).totalBorrowed();
            require(borrowed.assets == 0 && borrowed.shares == 0, "Batch C: market debt remains");
        }
    }

    /// @dev The allocator's EOA transaction must already have established every condition checked here.
    function _validateVaultRemovalComplete(address[] memory borrowMarkets, address[] memory affectedVaults)
        private
        view
    {
        for (uint256 vaultIndex; vaultIndex < affectedVaults.length; ++vaultIndex) {
            IAltoVault vault = IAltoVault(affectedVaults[vaultIndex]);

            for (uint256 marketIndex; marketIndex < borrowMarkets.length; ++marketIndex) {
                address market = borrowMarkets[marketIndex];
                MarketConfig memory vaultConfig = vault.config(market);
                PendingUint192 memory pendingCap = vault.pendingCap(market);
                Position memory vaultPosition = IMarket(market).position(address(vault));

                require(vaultConfig.cap == 0, "Batch C: Vault cap remains");
                require(!vaultConfig.enabled, "Batch C: Vault market still enabled");
                require(vaultConfig.removableAt == 0, "Batch C: pending Vault removal remains");
                require(pendingCap.validAt == 0, "Batch C: pending Vault cap remains");
                require(vaultPosition.supplyShares == 0, "Batch C: Vault supply remains");
                require(vault.quarantinedAssets(market) == 0, "Batch C: quarantined assets remain");
                require(!_isInSupplyQueue(vault, market), "Batch C: market remains in supply queue");
                require(!_isInWithdrawQueue(vault, market), "Batch C: market remains in withdraw queue");
            }
        }
    }

    function _validateFinalRemovalState(
        address timelock,
        address marketRegistry,
        address adapter,
        address liquidationPeriphery,
        address[] memory borrowMarkets,
        address[] memory leverages,
        address[] memory leverageSwappers
    ) private view {
        require(timelock != address(0), "Batch C: zero Timelock");
        require(liquidationPeriphery != address(0), "Batch C: zero liquidation periphery");
        require(Ownable(marketRegistry).owner() == timelock, "Batch C: Timelock does not own registry");
        require(Ownable(adapter).owner() == timelock, "Batch C: Timelock does not own adapter");

        for (uint256 i; i < borrowMarkets.length; ++i) {
            IMarket market = IMarket(borrowMarkets[i]);
            AltoLeverage leverage = AltoLeverage(leverages[i]);
            IAltoLeverageSwapper leverageSwapper = IAltoLeverageSwapper(leverageSwappers[i]);

            require(market.paused(FROZEN_TYPE), "Batch C: market not frozen");
            require(!market.paused(PAUSE_TYPE), "Batch C: market paused");
            require(market.oracle() != address(0), "Batch C: market oracle unavailable");

            require(Ownable(address(market)).owner() == timelock, "Batch C: Timelock does not own market");
            require(Ownable(address(leverage)).owner() == timelock, "Batch C: Timelock does not own leverage");
            require(
                Ownable(address(leverageSwapper)).owner() == timelock, "Batch C: Timelock does not own leverage swapper"
            );
            require(address(leverage.swapper()) == address(leverageSwapper), "Batch C: wrong leverage swapper");

            require(IMarketRegistry(marketRegistry).isBorrowMarket(address(market)), "Batch C: market not registered");
            require(
                AdapterContractApproval(adapter).isApprovedContract(address(market)),
                "Batch C: market not adapter-approved"
            );
            require(leverage.supportedMarkets(address(market)), "Batch C: leverage support already disabled");
            require(market.authorizedCallbacks(address(leverage)), "Batch C: leverage callback already revoked");
            require(leverageSwapper.isWhitelisted(address(leverage)), "Batch C: leverage whitelist already revoked");
            require(
                market.authorizedLiquidationPeriphery(liquidationPeriphery),
                "Batch C: liquidation periphery already revoked"
            );

            _requireNoLeverageResidue(market, address(leverage), address(leverageSwapper));
        }
    }

    function _requireNoLeverageResidue(IMarket market, address leverage, address leverageSwapper) private view {
        IERC20 borrowToken = IERC20(market.borrowToken());
        IERC20 collateralToken = IERC20(market.collateralToken());

        require(borrowToken.balanceOf(leverage) == 0, "Batch C: leverage borrow-token residue");
        require(collateralToken.balanceOf(leverage) == 0, "Batch C: leverage collateral residue");
        require(borrowToken.balanceOf(leverageSwapper) == 0, "Batch C: swapper borrow-token residue");
        require(collateralToken.balanceOf(leverageSwapper) == 0, "Batch C: swapper collateral residue");
        require(borrowToken.allowance(leverage, address(market)) == 0, "Batch C: leverage market borrow approval");
        require(
            collateralToken.allowance(leverage, address(market)) == 0, "Batch C: leverage market collateral approval"
        );
        require(borrowToken.allowance(leverage, leverageSwapper) == 0, "Batch C: leverage swapper borrow approval");
        require(
            collateralToken.allowance(leverage, leverageSwapper) == 0, "Batch C: leverage swapper collateral approval"
        );
    }

    function _finalRemovalTransactions(
        address marketRegistry,
        address adapter,
        address liquidationPeriphery,
        address[] memory borrowMarkets,
        address[] memory leverages,
        address[] memory leverageSwappers
    ) private pure returns (SafeTransaction[] memory transactions) {
        transactions = new SafeTransaction[](borrowMarkets.length * TRANSACTIONS_PER_MARKET);
        uint256 transactionIndex;

        // Dependencies on registry membership have already been cleared by the Vault allocator.
        for (uint256 i; i < borrowMarkets.length; ++i) {
            transactions[transactionIndex++] =
                _transaction(marketRegistry, abi.encodeCall(IMarketRegistry.removeBorrowMarket, (borrowMarkets[i])));
        }

        // Remove optional entry and bundled-exit discovery only after the Vault and debt gates pass.
        for (uint256 i; i < borrowMarkets.length; ++i) {
            transactions[transactionIndex++] =
                _transaction(adapter, abi.encodeCall(AdapterContractApproval.revokeContract, (borrowMarkets[i])));
        }

        // Disable every market-specific leverage permission after deleveraging is no longer required.
        for (uint256 i; i < borrowMarkets.length; ++i) {
            transactions[transactionIndex++] =
                _transaction(leverages[i], abi.encodeCall(AltoLeverage.setMarket, (borrowMarkets[i], false)));
            transactions[transactionIndex++] =
                _transaction(borrowMarkets[i], abi.encodeCall(IMarketBase.setAuthorizedCallback, (leverages[i], false)));
            transactions[transactionIndex++] = _transaction(
                leverageSwappers[i], abi.encodeCall(IAltoLeverageSwapper.setWhitelisted, (leverages[i], false))
            );
        }

        // With zero debt, the liquidation periphery is obsolete for these markets.
        for (uint256 i; i < borrowMarkets.length; ++i) {
            transactions[transactionIndex++] = _transaction(
                borrowMarkets[i],
                abi.encodeCall(IMarketBase.setAuthorizedLiquidationPeriphery, (liquidationPeriphery, false))
            );
        }

        assert(transactionIndex == transactions.length);
    }

    function _isInSupplyQueue(IAltoVaultBase vault, address market) private view returns (bool) {
        for (uint256 i; i < vault.supplyQueueLength(); ++i) {
            if (vault.supplyQueue(i) == market) return true;
        }
        return false;
    }

    function _isInWithdrawQueue(IAltoVaultBase vault, address market) private view returns (bool) {
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            if (vault.withdrawQueue(i) == market) return true;
        }
        return false;
    }

    /// @dev Placeholder configuration only. Batch C can contain any number of borrow markets and affected Vaults.
    /// Keep the market, leverage, and leverage-swapper arrays the same length and in matching order. Add every Vault
    /// affected by any configured market; the final-removal gate requires all configured markets to be cleared from it.
    function recoveryConfiguration()
        public
        view
        returns (
            address[] memory borrowMarkets,
            address[] memory leverages,
            address[] memory leverageSwappers,
            address[] memory affectedVaults
        )
    {
        string memory addresses = vm.readFile(ADDRESSES_FILE);
        borrowMarkets = new address[](5);
        leverages = new address[](5);
        leverageSwappers = new address[](5);
        affectedVaults = new address[](1);

        borrowMarkets[0] = vm.parseJsonAddress(addresses, ".contracts.wbtcBorrowMarket");
        borrowMarkets[1] = vm.parseJsonAddress(addresses, ".contracts.cbbtcBorrowMarket");
        borrowMarkets[2] = vm.parseJsonAddress(addresses, ".contracts.susdeBorrowMarket");
        borrowMarkets[3] = vm.parseJsonAddress(addresses, ".contracts.syrupUsdcBorrowMarket");
        borrowMarkets[4] = vm.parseJsonAddress(addresses, ".contracts.paxgBorrowMarket");

        leverages[0] = vm.parseJsonAddress(addresses, ".contracts.wbtcBorrowLeverage");
        leverages[1] = vm.parseJsonAddress(addresses, ".contracts.cbbtcBorrowLeverage");
        leverages[2] = vm.parseJsonAddress(addresses, ".contracts.susdeBorrowLeverage");
        leverages[3] = vm.parseJsonAddress(addresses, ".contracts.syrupUsdcBorrowLeverage");
        leverages[4] = vm.parseJsonAddress(addresses, ".contracts.paxgBorrowLeverage");

        leverageSwappers[0] = vm.parseJsonAddress(addresses, ".contracts.wbtcBorrowLeverageSwapper");
        leverageSwappers[1] = vm.parseJsonAddress(addresses, ".contracts.cbbtcBorrowLeverageSwapper");
        leverageSwappers[2] = vm.parseJsonAddress(addresses, ".contracts.susdeBorrowLeverageSwapper");
        leverageSwappers[3] = vm.parseJsonAddress(addresses, ".contracts.syrupUsdcBorrowLeverageSwapper");
        leverageSwappers[4] = vm.parseJsonAddress(addresses, ".contracts.paxgBorrowLeverageSwapper");

        affectedVaults[0] = vm.parseJsonAddress(addresses, ".contracts.dusdVault");
    }
}
