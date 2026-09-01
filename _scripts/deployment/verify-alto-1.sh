#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

# Check required environment variables
if [ -z "$ETHERSCAN_API_KEY" ] || [ -z "$ETHERSCAN_API_URL" ] || [ -z "$CHAIN_ID" ]; then
    echo "Error: Missing required environment variables for verification. Please check your .env file."
    echo "Required: ETHERSCAN_API_KEY, ETHERSCAN_API_URL, CHAIN_ID"
    exit 1
fi

# Build Etherscan v2-compatible verifier URL with required chainid param
if [[ "$ETHERSCAN_API_URL" == *\?* ]]; then
    VERIFIER_URL="${ETHERSCAN_API_URL}&chainid=${CHAIN_ID}"
else
    VERIFIER_URL="${ETHERSCAN_API_URL}?chainid=${CHAIN_ID}"
fi

echo "Enter the deployment ID (timestamp) to verify:"
read DEPLOYMENT_TIMESTAMP
if [ -z "$DEPLOYMENT_TIMESTAMP" ]; then
    echo "Error: Deployment ID is required"
    exit 1
fi

ADDRESSES_FILE="contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-${CHAIN_ID}-${DEPLOYMENT_TIMESTAMP}/addresses.json"

if [ ! -f "$ADDRESSES_FILE" ]; then
    echo "Error: Addresses file not found at $ADDRESSES_FILE"
    exit 1
fi

# Function to extract address from JSON
get_address() {
    local path=$1
    if command -v jq >/dev/null 2>&1; then
        jq -r "$path // empty" "$ADDRESSES_FILE" 2>/dev/null
    else
        cat "$ADDRESSES_FILE" | grep -o "\"${path##*.}\": \"[^\"]*\"" | cut -d'"' -f4
    fi
}

echo "🔍 Starting contract verification on $CHAIN_ID..."
echo "📁 Using addresses from: $ADDRESSES_FILE"
echo ""

# Initialize verification tracking
VERIFICATION_RESULTS=()
SUCCESSFUL_VERIFICATIONS=0
FAILED_VERIFICATIONS=0
declare -A VERIFICATION_ATTEMPTS=()

# Function to verify contract with rate limiting
verify_contract() {
    local name=$1
    local address=$2
    local contract_path=$3
    local extra_args=${4:-""}
    
    if [ -z "$address" ] || [ "$address" == "null" ] || [ "$address" == "0x0000000000000000000000000000000000000000" ]; then
        echo "⚠️  Skipping $name - no address found"
        VERIFICATION_RESULTS+=("SKIPPED: $name - no address found")
        return
    fi

    local verification_key="${address}|${contract_path}"
    if [ -n "${VERIFICATION_ATTEMPTS[$verification_key]:-}" ]; then
        echo "⚠️  Skipping $name at $address - already attempted for $contract_path"
        VERIFICATION_RESULTS+=("SKIPPED: $name at $address - duplicate verification")
        return
    fi
    VERIFICATION_ATTEMPTS[$verification_key]=1
    
    echo "🔍 Verifying $name at $address..."
    
    # Rate limiting: wait 0.5 seconds between requests
    if [ -n "${LAST_VERIFICATION_TIME_MS:-}" ]; then
        local current_time_ms=$(date +%s%3N)
        local time_diff_ms=$((current_time_ms - LAST_VERIFICATION_TIME_MS))
        if [ $time_diff_ms -lt 500 ]; then
            local sleep_time
            sleep_time=$(awk -v diff="$time_diff_ms" 'BEGIN { printf "%.3f", (500 - diff)/1000 }')
            echo "⏳ Rate limiting: waiting ${sleep_time} seconds..."
            sleep "$sleep_time"
        fi
    fi
    
    local max_retries=3
    local retry_count=0
    local success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            echo "🔄 Retry attempt $retry_count for $name..."
            local wait_time=$((10 * retry_count))
            echo "⏳ Waiting ${wait_time} seconds before retry..."
            sleep $wait_time
        fi
        
        if [ -n "$extra_args" ]; then
            forge verify-contract \
                --chain-id $CHAIN_ID \
                --verifier-url $VERIFIER_URL \
                --etherscan-api-key $ETHERSCAN_API_KEY \
                $extra_args \
                $address \
                $contract_path
        else
            forge verify-contract \
                --chain-id $CHAIN_ID \
                --verifier-url $VERIFIER_URL \
                --etherscan-api-key $ETHERSCAN_API_KEY \
                $address \
                $contract_path
        fi
        
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "✅ Successfully verified $name"
            success=true
            SUCCESSFUL_VERIFICATIONS=$((SUCCESSFUL_VERIFICATIONS + 1))
            VERIFICATION_RESULTS+=("SUCCESS: $name at $address")
        else
            echo "❌ Verification attempt failed for $name (exit code: $exit_code)"
            retry_count=$((retry_count + 1))
        fi
    done
    
    if [ "$success" = false ]; then
        echo "💥 Failed to verify $name after $max_retries attempts"
        echo "📝 You may need to verify this contract manually later"
        FAILED_VERIFICATIONS=$((FAILED_VERIFICATIONS + 1))
        VERIFICATION_RESULTS+=("FAILED: $name at $address")
    fi
    
    LAST_VERIFICATION_TIME_MS=$(date +%s%3N)
    echo ""
}

# Extract addresses
TIMELOCK=$(get_address ".contracts.timelock")
FEE_RECIPIENT=$(get_address ".contracts.feeRecipient")
ALTO_ADAPTER=$(get_address ".contracts.altoAdapter")
ALTO_REFERRAL_ADAPTER=$(get_address ".contracts.referralAdapter")
DUSD=$(get_address ".contracts.dusd")
DUSD_FLASH_MINTER=$(get_address ".contracts.dusdFlashMinter")
DUSD_VAULT=$(get_address ".contracts.dusdVault")
MARKET_REGISTRY=$(get_address ".contracts.marketRegistry")
USM_REGISTRY=$(get_address ".contracts.usmRegistry")
VAULT_REGISTRY=$(get_address ".contracts.vaultRegistry")
LIQUIDATION_PERIPHERY=$(get_address ".contracts.liquidationPeriphery")
UNIVERSAL_REWARDS_DISTRIBUTOR=$(get_address ".contracts.universalRewardsDistributor")
EMERGENCY_CONTROLLER=$(get_address ".contracts.emergencyController")
EMERGENCY_CONTROLLER_IMPL=$(get_address ".contracts.emergencyControllerImplementation")
OWNER_FIXED_RATE_IRM_FACTORY=$(get_address ".contracts.ownerFixedRateIrmFactory")

# Refreshed WETH Market contracts
WETH_MARKET=$(get_address ".contracts.refreshWethMarket")
WETH_MARKET_IMPL=$(get_address ".contracts.refreshWethMarketImplementation")
WETH_MARKET_IRM=$(get_address ".contracts.refreshWethMarketIrm")
WETH_MARKET_ORACLE=$(get_address ".contracts.refreshWethMarketOracle")
WETH_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshWethLiquidationEngine")
WETH_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshWethLeverageSwapper")
WETH_LEVERAGE=$(get_address ".contracts.refreshWethLeverage")

# Refreshed WSTETH Market contracts
WSTETH_MARKET=$(get_address ".contracts.refreshWstethMarket")
WSTETH_MARKET_IMPL=$(get_address ".contracts.refreshWstethMarketImplementation")
WSTETH_MARKET_IRM=$(get_address ".contracts.refreshWstethMarketIrm")
WSTETH_MARKET_ORACLE=$(get_address ".contracts.refreshWstethMarketOracle")
WSTETH_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshWstethLiquidationEngine")
WSTETH_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshWstethLeverageSwapper")
WSTETH_LEVERAGE=$(get_address ".contracts.refreshWstethLeverage")

# Refreshed RETH Market contracts
RETH_MARKET=$(get_address ".contracts.refreshRethMarket")
RETH_MARKET_IMPL=$(get_address ".contracts.refreshRethMarketImplementation")
RETH_MARKET_IRM=$(get_address ".contracts.refreshRethMarketIrm")
RETH_MARKET_ORACLE=$(get_address ".contracts.refreshRethMarketOracle")
RETH_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshRethLiquidationEngine")
RETH_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshRethLeverageSwapper")
RETH_LEVERAGE=$(get_address ".contracts.refreshRethLeverage")

# METH Market contracts
METH_MARKET=$(get_address ".contracts.methMarket")
METH_MARKET_IMPL=$(get_address ".contracts.methMarketImplementation")
METH_MARKET_IRM=$(get_address ".contracts.methMarketIrm")
METH_MARKET_ORACLE=$(get_address ".contracts.methMarketOracle")
METH_LIQUIDATION_ENGINE=$(get_address ".contracts.methLiquidationEngine")
METH_LEVERAGE_SWAPPER=$(get_address ".contracts.methLeverageSwapper")
METH_LEVERAGE=$(get_address ".contracts.methLeverage")

# TBTC Market contracts
TBTC_MARKET=$(get_address ".contracts.tbtcMarket")
TBTC_MARKET_IMPL=$(get_address ".contracts.tbtcMarketImplementation")
TBTC_MARKET_IRM=$(get_address ".contracts.tbtcMarketIrm")
TBTC_MARKET_ORACLE=$(get_address ".contracts.tbtcMarketOracle")
TBTC_LIQUIDATION_ENGINE=$(get_address ".contracts.tbtcLiquidationEngine")
TBTC_LEVERAGE_SWAPPER=$(get_address ".contracts.tbtcLeverageSwapper")
TBTC_LEVERAGE=$(get_address ".contracts.tbtcLeverage")

# WBTC Borrow Market contracts
WBTC_MARKET=$(get_address ".contracts.wbtcBorrowMarket")
WBTC_MARKET_IMPL=$(get_address ".contracts.wbtcBorrowMarketImplementation")
WBTC_MARKET_IRM=$(get_address ".contracts.wbtcBorrowMarketIrm")
WBTC_MARKET_ORACLE=$(get_address ".contracts.wbtcBorrowMarketOracle")
WBTC_LIQUIDATION_ENGINE=$(get_address ".contracts.wbtcBorrowLiquidationEngine")
WBTC_LEVERAGE_SWAPPER=$(get_address ".contracts.wbtcBorrowLeverageSwapper")
WBTC_LEVERAGE=$(get_address ".contracts.wbtcBorrowLeverage")

# CBBTC Borrow Market contracts
CBBTC_MARKET=$(get_address ".contracts.cbbtcBorrowMarket")
CBBTC_MARKET_IMPL=$(get_address ".contracts.cbbtcBorrowMarketImplementation")
CBBTC_MARKET_IRM=$(get_address ".contracts.cbbtcBorrowMarketIrm")
CBBTC_MARKET_ORACLE=$(get_address ".contracts.cbbtcBorrowMarketOracle")
CBBTC_LIQUIDATION_ENGINE=$(get_address ".contracts.cbbtcBorrowLiquidationEngine")
CBBTC_LEVERAGE_SWAPPER=$(get_address ".contracts.cbbtcBorrowLeverageSwapper")
CBBTC_LEVERAGE=$(get_address ".contracts.cbbtcBorrowLeverage")

# Refreshed SUSDE Borrow Market contracts
SUSDE_MARKET=$(get_address ".contracts.refreshSusdeBorrowMarket")
SUSDE_MARKET_IMPL=$(get_address ".contracts.refreshSusdeBorrowMarketImplementation")
SUSDE_MARKET_IRM=$(get_address ".contracts.refreshSusdeBorrowMarketIrm")
SUSDE_MARKET_ORACLE=$(get_address ".contracts.refreshSusdeBorrowMarketOracle")
SUSDE_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshSusdeBorrowLiquidationEngine")
SUSDE_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshSusdeBorrowLeverageSwapper")
SUSDE_LEVERAGE=$(get_address ".contracts.refreshSusdeBorrowLeverage")

# Refreshed SYRUP USDC Borrow Market contracts
SYRUPUSDC_MARKET=$(get_address ".contracts.refreshSyrupUsdcBorrowMarket")
SYRUPUSDC_MARKET_IMPL=$(get_address ".contracts.refreshSyrupUsdcBorrowMarketImplementation")
SYRUPUSDC_MARKET_IRM=$(get_address ".contracts.refreshSyrupUsdcBorrowMarketIrm")
SYRUPUSDC_MARKET_ORACLE=$(get_address ".contracts.refreshSyrupUsdcBorrowMarketOracle")
SYRUPUSDC_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshSyrupUsdcBorrowLiquidationEngine")
SYRUPUSDC_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshSyrupUsdcBorrowLeverageSwapper")
SYRUPUSDC_LEVERAGE=$(get_address ".contracts.refreshSyrupUsdcBorrowLeverage")

# PAXG Borrow Market contracts
PAXG_MARKET=$(get_address ".contracts.paxgBorrowMarket")
PAXG_MARKET_IMPL=$(get_address ".contracts.paxgBorrowMarketImplementation")
PAXG_MARKET_IRM=$(get_address ".contracts.paxgBorrowMarketIrm")
PAXG_MARKET_ORACLE=$(get_address ".contracts.paxgBorrowMarketOracle")
PAXG_LIQUIDATION_ENGINE=$(get_address ".contracts.paxgBorrowLiquidationEngine")
PAXG_LEVERAGE_SWAPPER=$(get_address ".contracts.paxgBorrowLeverageSwapper")
PAXG_LEVERAGE=$(get_address ".contracts.paxgBorrowLeverage")

# Refreshed sUSDe Mint Market contracts
SUSDE_MINT_MARKET=$(get_address ".contracts.refreshSusdeMintMarket")
SUSDE_MINT_MARKET_IMPL=$(get_address ".contracts.refreshSusdeMintMarketImplementation")
SUSDE_MINT_MARKET_IRM=$(get_address ".contracts.refreshSusdeMintMarketIrm")
SUSDE_MINT_MARKET_ORACLE=$(get_address ".contracts.refreshSusdeMintMarketOracle")
SUSDE_MINT_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshSusdeMintLiquidationEngine")
SUSDE_MINT_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshSusdeMintLeverageSwapper")
SUSDE_MINT_LEVERAGE=$(get_address ".contracts.refreshSusdeMintLeverage")

# Refreshed syrupUSDC Mint Market contracts
SYRUPUSDC_MINT_MARKET=$(get_address ".contracts.refreshSyrupUsdcMintMarket")
SYRUPUSDC_MINT_MARKET_IMPL=$(get_address ".contracts.refreshSyrupUsdcMintMarketImplementation")
SYRUPUSDC_MINT_MARKET_IRM=$(get_address ".contracts.refreshSyrupUsdcMintMarketIrm")
SYRUPUSDC_MINT_MARKET_ORACLE=$(get_address ".contracts.refreshSyrupUsdcMintMarketOracle")
SYRUPUSDC_MINT_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshSyrupUsdcMintLiquidationEngine")
SYRUPUSDC_MINT_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshSyrupUsdcMintLeverageSwapper")
SYRUPUSDC_MINT_LEVERAGE=$(get_address ".contracts.refreshSyrupUsdcMintLeverage")

# Refreshed frxUSD Mint Market contracts
FRXUSD_MINT_MARKET=$(get_address ".contracts.refreshFrxUsdMarket")
FRXUSD_MINT_MARKET_IMPL=$(get_address ".contracts.refreshFrxUsdMarketImplementation")
FRXUSD_MINT_MARKET_IRM=$(get_address ".contracts.refreshFrxUsdMarketIrm")
FRXUSD_MINT_MARKET_ORACLE=$(get_address ".contracts.refreshFrxUsdMarketOracle")
FRXUSD_MINT_LIQUIDATION_ENGINE=$(get_address ".contracts.refreshFrxUsdLiquidationEngine")
FRXUSD_MINT_LEVERAGE_SWAPPER=$(get_address ".contracts.refreshFrxUsdLeverageSwapper")
FRXUSD_MINT_LEVERAGE=$(get_address ".contracts.refreshFrxUsdLeverage")

# Permissioned USM contracts
PERMISSIONED_USM=$(get_address ".contracts.permissionedUsm")
PERMISSIONED_USM_IMPL=$(get_address ".contracts.permissionedUsmImplementation")
PERMISSIONED_USM_FIXED_PRICE_STRATEGY=$(get_address ".contracts.permissionedUsmFixedPriceStrategy")
PERMISSIONED_USM_FIXED_FEE_STRATEGY=$(get_address ".contracts.permissionedUsmFixedFeeStrategy")

# Permissionless USM contracts
PERMISSIONLESS_USM=$(get_address ".contracts.permissionlessUsm")
PERMISSIONLESS_USM_IMPL=$(get_address ".contracts.permissionlessUsmImplementation")
PERMISSIONLESS_USM_FIXED_PRICE_STRATEGY=$(get_address ".contracts.permissionlessUsmFixedPriceStrategy")
PERMISSIONLESS_USM_FIXED_FEE_STRATEGY=$(get_address ".contracts.permissionlessUsmFixedFeeStrategy")

# Permissioned frxUSD USM contracts
PERMISSIONED_FRXUSD_USM=$(get_address ".contracts.permissionedFrxUsdUsm")
PERMISSIONED_FRXUSD_USM_IMPL=$(get_address ".contracts.permissionedFrxUsdUsmImplementation")
PERMISSIONED_FRXUSD_USM_FIXED_PRICE_STRATEGY=$(get_address ".contracts.permissionedFrxUsdUsmFixedPriceStrategy")
PERMISSIONED_FRXUSD_USM_FIXED_FEE_STRATEGY=$(get_address ".contracts.permissionedFrxUsdUsmFixedFeeStrategy")

# Permissionless frxUSD USM contracts
PERMISSIONLESS_FRXUSD_USM=$(get_address ".contracts.permissionlessFrxUsdUsm")
PERMISSIONLESS_FRXUSD_USM_IMPL=$(get_address ".contracts.permissionlessFrxUsdUsmImplementation")
PERMISSIONLESS_FRXUSD_USM_FIXED_PRICE_STRATEGY=$(get_address ".contracts.permissionlessFrxUsdUsmFixedPriceStrategy")
PERMISSIONLESS_FRXUSD_USM_FIXED_FEE_STRATEGY=$(get_address ".contracts.permissionlessFrxUsdUsmFixedFeeStrategy")

# Advanced permissions frxUSD USM contracts
ADVANCED_PERMISSIONS_FRXUSD_USM=$(get_address ".contracts.advancedPermissionsFrxusdUsm")
ADVANCED_PERMISSIONS_FRXUSD_USM_IMPL=$(get_address ".contracts.advancedPermissionsFrxusdUsmImplementation")
ADVANCED_PERMISSIONS_FRXUSD_USM_FIXED_PRICE_STRATEGY=$(get_address ".contracts.advancedPermissionsFrxusdUsmFixedPriceStrategy")
ADVANCED_PERMISSIONS_FRXUSD_USM_FEE_STRATEGY=$(get_address ".contracts.advancedPermissionsFrxusdUsmFeeStrategy")

echo "📋 Contract verification plan:"
echo "- Timelock: $TIMELOCK"
echo "- Fee Recipient: $FEE_RECIPIENT"
echo "- Alto Adapter: $ALTO_ADAPTER"
echo "- Alto Referral Adapter: $ALTO_REFERRAL_ADAPTER"
echo "- DUSD: $DUSD"
echo "- DUSD Flash Minter: $DUSD_FLASH_MINTER"
echo "- DUSD Vault: $DUSD_VAULT"
echo "- Market Registry: $MARKET_REGISTRY"
echo "- USM Registry: $USM_REGISTRY"
echo "- Vault Registry: $VAULT_REGISTRY"
echo "- Liquidation Periphery: $LIQUIDATION_PERIPHERY"
echo "- Universal Rewards Distributor: $UNIVERSAL_REWARDS_DISTRIBUTOR"
echo "- Emergency Controller: $EMERGENCY_CONTROLLER"
echo "- Emergency Controller Implementation: $EMERGENCY_CONTROLLER_IMPL"
echo "- Owner Fixed Rate IRM Factory: $OWNER_FIXED_RATE_IRM_FACTORY"
echo "- WETH Market: $WETH_MARKET"
echo "- WETH Market Implementation: $WETH_MARKET_IMPL"
echo "- WETH Market IRM: $WETH_MARKET_IRM"
echo "- WETH Market Oracle: $WETH_MARKET_ORACLE"
echo "- WETH Liquidation Engine: $WETH_LIQUIDATION_ENGINE"
echo "- WETH Leverage Swapper: $WETH_LEVERAGE_SWAPPER"
echo "- WETH Leverage: $WETH_LEVERAGE"
echo "- WSTETH Market: $WSTETH_MARKET"
echo "- WSTETH Market Implementation: $WSTETH_MARKET_IMPL"
echo "- WSTETH Market IRM: $WSTETH_MARKET_IRM"
echo "- WSTETH Market Oracle: $WSTETH_MARKET_ORACLE"
echo "- WSTETH Liquidation Engine: $WSTETH_LIQUIDATION_ENGINE"
echo "- WSTETH Leverage Swapper: $WSTETH_LEVERAGE_SWAPPER"
echo "- WSTETH Leverage: $WSTETH_LEVERAGE"
echo "- RETH Market: $RETH_MARKET"
echo "- RETH Market Implementation: $RETH_MARKET_IMPL"
echo "- RETH Market IRM: $RETH_MARKET_IRM"
echo "- RETH Market Oracle: $RETH_MARKET_ORACLE"
echo "- RETH Liquidation Engine: $RETH_LIQUIDATION_ENGINE"
echo "- RETH Leverage Swapper: $RETH_LEVERAGE_SWAPPER"
echo "- RETH Leverage: $RETH_LEVERAGE"
echo "- METH Market: $METH_MARKET"
echo "- METH Market Implementation: $METH_MARKET_IMPL"
echo "- METH Market IRM: $METH_MARKET_IRM"
echo "- METH Market Oracle: $METH_MARKET_ORACLE"
echo "- METH Liquidation Engine: $METH_LIQUIDATION_ENGINE"
echo "- METH Leverage Swapper: $METH_LEVERAGE_SWAPPER"
echo "- METH Leverage: $METH_LEVERAGE"
echo "- TBTC Market: $TBTC_MARKET"
echo "- TBTC Market Implementation: $TBTC_MARKET_IMPL"
echo "- TBTC Market IRM: $TBTC_MARKET_IRM"
echo "- TBTC Market Oracle: $TBTC_MARKET_ORACLE"
echo "- TBTC Liquidation Engine: $TBTC_LIQUIDATION_ENGINE"
echo "- TBTC Leverage Swapper: $TBTC_LEVERAGE_SWAPPER"
echo "- TBTC Leverage: $TBTC_LEVERAGE"
echo "- WBTC Borrow Market: $WBTC_MARKET"
echo "- WBTC Borrow Market Implementation: $WBTC_MARKET_IMPL"
echo "- WBTC Borrow Market IRM: $WBTC_MARKET_IRM"
echo "- WBTC Borrow Market Oracle: $WBTC_MARKET_ORACLE"
echo "- WBTC Borrow Liquidation Engine: $WBTC_LIQUIDATION_ENGINE"
echo "- WBTC Borrow Leverage Swapper: $WBTC_LEVERAGE_SWAPPER"
echo "- WBTC Borrow Leverage: $WBTC_LEVERAGE"
echo "- CBBTC Borrow Market: $CBBTC_MARKET"
echo "- CBBTC Borrow Market Implementation: $CBBTC_MARKET_IMPL"
echo "- CBBTC Borrow Market IRM: $CBBTC_MARKET_IRM"
echo "- CBBTC Borrow Market Oracle: $CBBTC_MARKET_ORACLE"
echo "- CBBTC Borrow Liquidation Engine: $CBBTC_LIQUIDATION_ENGINE"
echo "- CBBTC Borrow Leverage Swapper: $CBBTC_LEVERAGE_SWAPPER"
echo "- CBBTC Borrow Leverage: $CBBTC_LEVERAGE"
echo "- SUSDE Borrow Market: $SUSDE_MARKET"
echo "- SUSDE Borrow Market Implementation: $SUSDE_MARKET_IMPL"
echo "- SUSDE Borrow Market IRM: $SUSDE_MARKET_IRM"
echo "- SUSDE Borrow Market Oracle: $SUSDE_MARKET_ORACLE"
echo "- SUSDE Borrow Liquidation Engine: $SUSDE_LIQUIDATION_ENGINE"
echo "- SUSDE Borrow Leverage Swapper: $SUSDE_LEVERAGE_SWAPPER"
echo "- SUSDE Borrow Leverage: $SUSDE_LEVERAGE"
echo "- SYRUP USDC Borrow Market: $SYRUPUSDC_MARKET"
echo "- SYRUP USDC Borrow Market Implementation: $SYRUPUSDC_MARKET_IMPL"
echo "- SYRUP USDC Borrow Market IRM: $SYRUPUSDC_MARKET_IRM"
echo "- SYRUP USDC Borrow Market Oracle: $SYRUPUSDC_MARKET_ORACLE"
echo "- SYRUP USDC Borrow Liquidation Engine: $SYRUPUSDC_LIQUIDATION_ENGINE"
echo "- SYRUP USDC Borrow Leverage Swapper: $SYRUPUSDC_LEVERAGE_SWAPPER"
echo "- SYRUP USDC Borrow Leverage: $SYRUPUSDC_LEVERAGE"
echo "- PAXG Borrow Market: $PAXG_MARKET"
echo "- PAXG Borrow Market Implementation: $PAXG_MARKET_IMPL"
echo "- PAXG Borrow Market IRM: $PAXG_MARKET_IRM"
echo "- PAXG Borrow Market Oracle: $PAXG_MARKET_ORACLE"
echo "- PAXG Borrow Liquidation Engine: $PAXG_LIQUIDATION_ENGINE"
echo "- PAXG Borrow Leverage Swapper: $PAXG_LEVERAGE_SWAPPER"
echo "- PAXG Borrow Leverage: $PAXG_LEVERAGE"
echo "- sUSDe Mint Market: $SUSDE_MINT_MARKET"
echo "- sUSDe Mint Market Implementation: $SUSDE_MINT_MARKET_IMPL"
echo "- sUSDe Mint Market IRM: $SUSDE_MINT_MARKET_IRM"
echo "- sUSDe Mint Market Oracle: $SUSDE_MINT_MARKET_ORACLE"
echo "- sUSDe Mint Liquidation Engine: $SUSDE_MINT_LIQUIDATION_ENGINE"
echo "- sUSDe Mint Leverage Swapper: $SUSDE_MINT_LEVERAGE_SWAPPER"
echo "- sUSDe Mint Leverage: $SUSDE_MINT_LEVERAGE"
echo "- syrupUSDC Mint Market: $SYRUPUSDC_MINT_MARKET"
echo "- syrupUSDC Mint Market Implementation: $SYRUPUSDC_MINT_MARKET_IMPL"
echo "- syrupUSDC Mint Market IRM: $SYRUPUSDC_MINT_MARKET_IRM"
echo "- syrupUSDC Mint Market Oracle: $SYRUPUSDC_MINT_MARKET_ORACLE"
echo "- syrupUSDC Mint Liquidation Engine: $SYRUPUSDC_MINT_LIQUIDATION_ENGINE"
echo "- syrupUSDC Mint Leverage Swapper: $SYRUPUSDC_MINT_LEVERAGE_SWAPPER"
echo "- syrupUSDC Mint Leverage: $SYRUPUSDC_MINT_LEVERAGE"
echo "- frxUSD Mint Market: $FRXUSD_MINT_MARKET"
echo "- frxUSD Mint Market Implementation: $FRXUSD_MINT_MARKET_IMPL"
echo "- frxUSD Mint Market IRM: $FRXUSD_MINT_MARKET_IRM"
echo "- frxUSD Mint Market Oracle: $FRXUSD_MINT_MARKET_ORACLE"
echo "- frxUSD Mint Liquidation Engine: $FRXUSD_MINT_LIQUIDATION_ENGINE"
echo "- frxUSD Mint Leverage Swapper: $FRXUSD_MINT_LEVERAGE_SWAPPER"
echo "- frxUSD Mint Leverage: $FRXUSD_MINT_LEVERAGE"
echo "- Permissioned USM: $PERMISSIONED_USM"
echo "- Permissioned USM Implementation: $PERMISSIONED_USM_IMPL"
echo "- Permissioned USM Fixed Price Strategy: $PERMISSIONED_USM_FIXED_PRICE_STRATEGY"
echo "- Permissioned USM Fixed Fee Strategy: $PERMISSIONED_USM_FIXED_FEE_STRATEGY"
echo "- Permissionless USM: $PERMISSIONLESS_USM"
echo "- Permissionless USM Implementation: $PERMISSIONLESS_USM_IMPL"
echo "- Permissionless USM Fixed Price Strategy: $PERMISSIONLESS_USM_FIXED_PRICE_STRATEGY"
echo "- Permissionless USM Fixed Fee Strategy: $PERMISSIONLESS_USM_FIXED_FEE_STRATEGY"
echo "- Permissioned frxUSD USM: $PERMISSIONED_FRXUSD_USM"
echo "- Permissioned frxUSD USM Implementation: $PERMISSIONED_FRXUSD_USM_IMPL"
echo "- Permissioned frxUSD USM Fixed Price Strategy: $PERMISSIONED_FRXUSD_USM_FIXED_PRICE_STRATEGY"
echo "- Permissioned frxUSD USM Fixed Fee Strategy: $PERMISSIONED_FRXUSD_USM_FIXED_FEE_STRATEGY"
echo "- Permissionless frxUSD USM: $PERMISSIONLESS_FRXUSD_USM"
echo "- Permissionless frxUSD USM Implementation: $PERMISSIONLESS_FRXUSD_USM_IMPL"
echo "- Permissionless frxUSD USM Fixed Price Strategy: $PERMISSIONLESS_FRXUSD_USM_FIXED_PRICE_STRATEGY"
echo "- Permissionless frxUSD USM Fixed Fee Strategy: $PERMISSIONLESS_FRXUSD_USM_FIXED_FEE_STRATEGY"
echo "- Advanced Permissions frxUSD USM: $ADVANCED_PERMISSIONS_FRXUSD_USM"
echo "- Advanced Permissions frxUSD USM Implementation: $ADVANCED_PERMISSIONS_FRXUSD_USM_IMPL"
echo "- Advanced Permissions frxUSD USM Fixed Price Strategy: $ADVANCED_PERMISSIONS_FRXUSD_USM_FIXED_PRICE_STRATEGY"
echo "- Advanced Permissions frxUSD USM Fee Strategy: $ADVANCED_PERMISSIONS_FRXUSD_USM_FEE_STRATEGY"
echo ""

read -p "Do you want to proceed with verification? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Verification cancelled."
    exit 0
fi

echo "🚀 Starting verification process..."
echo ""

# Verify contracts
verify_contract "Timelock" "$TIMELOCK" "contracts/utils/AltoTimelockController.sol:AltoTimelockController"
verify_contract "FeeRecipient" "$FEE_RECIPIENT" "contracts/utils/AltoTimelockController.sol:AltoTimelockController"
verify_contract "AltoAdapter" "$ALTO_ADAPTER" "contracts/utils/AltoAdapter.sol:AltoAdapter"
verify_contract "AltoReferralAdapter" "$ALTO_REFERRAL_ADAPTER" "contracts/rewards/adapters/AltoReferralWhitelistAdapter.sol:AltoReferralWhitelistAdapter"
verify_contract "DUSD" "$DUSD" "contracts/tokens/DUSD.sol:DUSD"
verify_contract "DUSDFlashMinter" "$DUSD_FLASH_MINTER" "contracts/usm/DUSDFlashMinter.sol:DUSDFlashMinter"
verify_contract "DUSDVault" "$DUSD_VAULT" "contracts/lending/vault/AltoVault.sol:AltoVault"
verify_contract "MarketRegistry" "$MARKET_REGISTRY" "contracts/utils/MarketRegistry.sol:MarketRegistry"
verify_contract "UsmRegistry" "$USM_REGISTRY" "contracts/utils/UsmRegistry.sol:UsmRegistry"
verify_contract "VaultRegistry" "$VAULT_REGISTRY" "contracts/utils/VaultRegistry.sol:VaultRegistry"
verify_contract "LiquidationPeriphery" "$LIQUIDATION_PERIPHERY" "contracts/lending/liquidation/LiquidationPeriphery.sol:LiquidationPeriphery"
verify_contract "UniversalRewardsDistributor" "$UNIVERSAL_REWARDS_DISTRIBUTOR" "contracts/utils/UniversalRewardsDistributor.sol:UniversalRewardsDistributor"
verify_contract "EmergencyController" "$EMERGENCY_CONTROLLER" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "EmergencyControllerImplementation" "$EMERGENCY_CONTROLLER_IMPL" "contracts/utils/EmergencyController.sol:EmergencyController"
verify_contract "OwnerFixedRateIrmFactory" "$OWNER_FIXED_RATE_IRM_FACTORY" "contracts/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol:OwnerFixedRateIrmFactory"

# Refreshed WETH Market contracts
verify_contract "WethMarket" "$WETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "WethMarketImplementation" "$WETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "WethMarketIRM" "$WETH_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "WethMarketOracle" "$WETH_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "WethLiquidationEngine" "$WETH_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "WethLeverageSwapper" "$WETH_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "WethLeverage" "$WETH_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed WSTETH Market contracts
verify_contract "WstethMarket" "$WSTETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "WstethMarketImplementation" "$WSTETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "WstethMarketIRM" "$WSTETH_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "WstethMarketOracle" "$WSTETH_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleWSTETH.sol:ERC4626RatioChainlinkOracleWSTETH"
verify_contract "WstethLiquidationEngine" "$WSTETH_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "WstethLeverageSwapper" "$WSTETH_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "WstethLeverage" "$WSTETH_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed RETH Market contracts
verify_contract "RethMarket" "$RETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "RethMarketImplementation" "$RETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "RethMarketIRM" "$RETH_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "RethMarketOracle" "$RETH_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleRETH.sol:ERC4626RatioChainlinkOracleRETH"
verify_contract "RethLiquidationEngine" "$RETH_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "RethLeverageSwapper" "$RETH_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "RethLeverage" "$RETH_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# METH Market contracts
verify_contract "MethMarket" "$METH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "MethMarketImplementation" "$METH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "MethMarketIRM" "$METH_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "MethMarketOracle" "$METH_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleMETH.sol:ERC4626RatioChainlinkOracleMETH"
verify_contract "MethLiquidationEngine" "$METH_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "MethLeverageSwapper" "$METH_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "MethLeverage" "$METH_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# TBTC Market contracts
verify_contract "TbtcMarket" "$TBTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "TbtcMarketImplementation" "$TBTC_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "TbtcMarketIRM" "$TBTC_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "TbtcMarketOracle" "$TBTC_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "TbtcLiquidationEngine" "$TBTC_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "TbtcLeverageSwapper" "$TBTC_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "TbtcLeverage" "$TBTC_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# WBTC Borrow Market contracts
verify_contract "WbtcBorrowMarket" "$WBTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "WbtcBorrowMarketImplementation" "$WBTC_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "WbtcBorrowMarketIRM" "$WBTC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "WbtcBorrowMarketOracle" "$WBTC_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "WbtcBorrowLiquidationEngine" "$WBTC_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "WbtcBorrowLeverageSwapper" "$WBTC_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "WbtcBorrowLeverage" "$WBTC_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# CBBTC Borrow Market contracts
verify_contract "CbbtcBorrowMarket" "$CBBTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "CbbtcBorrowMarketImplementation" "$CBBTC_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "CbbtcBorrowMarketIRM" "$CBBTC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "CbbtcBorrowMarketOracle" "$CBBTC_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "CbbtcBorrowLiquidationEngine" "$CBBTC_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "CbbtcBorrowLeverageSwapper" "$CBBTC_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "CbbtcBorrowLeverage" "$CBBTC_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed SUSDE Borrow Market contracts
verify_contract "SusdeBorrowMarket" "$SUSDE_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "SusdeBorrowMarketImplementation" "$SUSDE_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "SusdeBorrowMarketIRM" "$SUSDE_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "SusdeBorrowMarketOracle" "$SUSDE_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSUSDE.sol:ERC4626RatioChainlinkOracleSUSDE"
verify_contract "SusdeBorrowLiquidationEngine" "$SUSDE_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "SusdeBorrowLeverageSwapper" "$SUSDE_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "SusdeBorrowLeverage" "$SUSDE_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed SYRUP USDC Borrow Market contracts
verify_contract "SyrupUsdcBorrowMarket" "$SYRUPUSDC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "SyrupUsdcBorrowMarketImplementation" "$SYRUPUSDC_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "SyrupUsdcBorrowMarketIRM" "$SYRUPUSDC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "SyrupUsdcBorrowMarketOracle" "$SYRUPUSDC_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSYRUPUSDC.sol:ERC4626RatioChainlinkOracleSYRUPUSDC"
verify_contract "SyrupUsdcBorrowLiquidationEngine" "$SYRUPUSDC_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "SyrupUsdcBorrowLeverageSwapper" "$SYRUPUSDC_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "SyrupUsdcBorrowLeverage" "$SYRUPUSDC_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# PAXG Borrow Market contracts
verify_contract "PaxgBorrowMarket" "$PAXG_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "PaxgBorrowMarketImplementation" "$PAXG_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "PaxgBorrowMarketIRM" "$PAXG_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "PaxgBorrowMarketOracle" "$PAXG_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "PaxgBorrowLiquidationEngine" "$PAXG_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "PaxgBorrowLeverageSwapper" "$PAXG_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "PaxgBorrowLeverage" "$PAXG_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed sUSDe Mint Market contracts
verify_contract "SusdeMintMarket" "$SUSDE_MINT_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "SusdeMintMarketImplementation" "$SUSDE_MINT_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "SusdeMintMarketIRM" "$SUSDE_MINT_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "SusdeMintMarketOracle" "$SUSDE_MINT_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSUSDE.sol:ERC4626RatioChainlinkOracleSUSDE"
verify_contract "SusdeMintLiquidationEngine" "$SUSDE_MINT_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "SusdeMintLeverageSwapper" "$SUSDE_MINT_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "SusdeMintLeverage" "$SUSDE_MINT_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed syrupUSDC Mint Market contracts
verify_contract "SyrupUsdcMintMarket" "$SYRUPUSDC_MINT_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "SyrupUsdcMintMarketImplementation" "$SYRUPUSDC_MINT_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "SyrupUsdcMintMarketIRM" "$SYRUPUSDC_MINT_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "SyrupUsdcMintMarketOracle" "$SYRUPUSDC_MINT_MARKET_ORACLE" "contracts/oracles/AltoERC4626RatioChainlinkOracle/implementations/ERC4626RatioChainlinkOracleSYRUPUSDC.sol:ERC4626RatioChainlinkOracleSYRUPUSDC"
verify_contract "SyrupUsdcMintLiquidationEngine" "$SYRUPUSDC_MINT_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "SyrupUsdcMintLeverageSwapper" "$SYRUPUSDC_MINT_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "SyrupUsdcMintLeverage" "$SYRUPUSDC_MINT_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Refreshed frxUSD Mint Market contracts
verify_contract "FrxUsdMintMarket" "$FRXUSD_MINT_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "FrxUsdMintMarketImplementation" "$FRXUSD_MINT_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "FrxUsdMintMarketIRM" "$FRXUSD_MINT_MARKET_IRM" "contracts/lending/irm/FixedRateIrm.sol:FixedRateIrm"
verify_contract "FrxUsdMintMarketOracle" "$FRXUSD_MINT_MARKET_ORACLE" "contracts/oracles/AltoMultiChainlinkLendingOracle.sol:AltoMultiChainlinkLendingOracle"
verify_contract "FrxUsdMintLiquidationEngine" "$FRXUSD_MINT_LIQUIDATION_ENGINE" "contracts/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol:DlbDcfPriorityLiquidationEngine"
verify_contract "FrxUsdMintLeverageSwapper" "$FRXUSD_MINT_LEVERAGE_SWAPPER" "contracts/lending/leverage/AltoLeverageSwapperMultiTarget.sol:AltoLeverageSwapperMultiTarget"
verify_contract "FrxUsdMintLeverage" "$FRXUSD_MINT_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"

# Permissioned USM contracts
verify_contract "PermissionedUsm" "$PERMISSIONED_USM" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "PermissionedUsmImplementation" "$PERMISSIONED_USM_IMPL" "contracts/usm/DUSDUsm.sol:DUSDUsm"
verify_contract "PermissionedUsmFixedPriceStrategy" "$PERMISSIONED_USM_FIXED_PRICE_STRATEGY" "contracts/usm/FixedPriceStrategy.sol:FixedPriceStrategy"
verify_contract "PermissionedUsmFixedFeeStrategy" "$PERMISSIONED_USM_FIXED_FEE_STRATEGY" "contracts/usm/FixedFeeStrategy.sol:FixedFeeStrategy"

# Permissionless USM contracts
verify_contract "PermissionlessUsm" "$PERMISSIONLESS_USM" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "PermissionlessUsmImplementation" "$PERMISSIONLESS_USM_IMPL" "contracts/usm/DUSDUsm.sol:DUSDUsm"
verify_contract "PermissionlessUsmFixedPriceStrategy" "$PERMISSIONLESS_USM_FIXED_PRICE_STRATEGY" "contracts/usm/FixedPriceStrategy.sol:FixedPriceStrategy"
verify_contract "PermissionlessUsmFixedFeeStrategy" "$PERMISSIONLESS_USM_FIXED_FEE_STRATEGY" "contracts/usm/FixedFeeStrategy.sol:FixedFeeStrategy"

# Permissioned frxUSD USM contracts
verify_contract "PermissionedFrxUsdUsm" "$PERMISSIONED_FRXUSD_USM" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "PermissionedFrxUsdUsmImplementation" "$PERMISSIONED_FRXUSD_USM_IMPL" "contracts/usm/DUSDUsm.sol:DUSDUsm"
verify_contract "PermissionedFrxUsdUsmFixedPriceStrategy" "$PERMISSIONED_FRXUSD_USM_FIXED_PRICE_STRATEGY" "contracts/usm/FixedPriceStrategy.sol:FixedPriceStrategy"
verify_contract "PermissionedFrxUsdUsmFixedFeeStrategy" "$PERMISSIONED_FRXUSD_USM_FIXED_FEE_STRATEGY" "contracts/usm/FixedFeeStrategy.sol:FixedFeeStrategy"

# Permissionless frxUSD USM contracts
verify_contract "PermissionlessFrxUsdUsm" "$PERMISSIONLESS_FRXUSD_USM" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "PermissionlessFrxUsdUsmImplementation" "$PERMISSIONLESS_FRXUSD_USM_IMPL" "contracts/usm/DUSDUsm.sol:DUSDUsm"
verify_contract "PermissionlessFrxUsdUsmFixedPriceStrategy" "$PERMISSIONLESS_FRXUSD_USM_FIXED_PRICE_STRATEGY" "contracts/usm/FixedPriceStrategy.sol:FixedPriceStrategy"
verify_contract "PermissionlessFrxUsdUsmFixedFeeStrategy" "$PERMISSIONLESS_FRXUSD_USM_FIXED_FEE_STRATEGY" "contracts/usm/FixedFeeStrategy.sol:FixedFeeStrategy"

# Advanced permissions frxUSD USM contracts
verify_contract "AdvancedPermissionsFrxUsdUsm" "$ADVANCED_PERMISSIONS_FRXUSD_USM" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "AdvancedPermissionsFrxUsdUsmImplementation" "$ADVANCED_PERMISSIONS_FRXUSD_USM_IMPL" "contracts/usm/DUSDAdvancedPermissionsUsm.sol:DUSDAdvancedPermissionsUsm"
verify_contract "AdvancedPermissionsFrxUsdUsmFixedPriceStrategy" "$ADVANCED_PERMISSIONS_FRXUSD_USM_FIXED_PRICE_STRATEGY" "contracts/usm/FixedPriceStrategy.sol:FixedPriceStrategy"
verify_contract "AdvancedPermissionsFrxUsdUsmFeeStrategy" "$ADVANCED_PERMISSIONS_FRXUSD_USM_FEE_STRATEGY" "contracts/usm/AdvancedPermissionsFeeStrategy.sol:AdvancedPermissionsFeeStrategy"

echo "🎉 Contract verification process completed!"
echo ""
echo "📊 VERIFICATION SUMMARY:"
echo "========================"
echo "✅ Successful verifications: $SUCCESSFUL_VERIFICATIONS"
echo "❌ Failed verifications: $FAILED_VERIFICATIONS"
echo ""

if [ ${#VERIFICATION_RESULTS[@]} -gt 0 ]; then
    echo "📝 Detailed Results:"
    echo "--------------------"
    for result in "${VERIFICATION_RESULTS[@]}"; do
        echo "$result"
    done
    echo ""
fi

if [ $FAILED_VERIFICATIONS -gt 0 ]; then
    echo "⚠️  Some verifications failed. You may need to:"
    echo "   1. Check if the contract addresses are correct"
    echo "   2. Verify the contract paths and names"
    echo "   3. Try manual verification on Etherscan"
    echo "   4. Check if contracts are already verified"
    echo ""
fi

echo "🔗 Check the Etherscan explorer to see the verification status"
echo ""
echo "💡 Tip: You can also run individual verifications using:"
echo "forge verify-contract --chain-id $CHAIN_ID --verifier-url $VERIFIER_URL --etherscan-api-key \$ETHERSCAN_API_KEY <address> <contract_path>"
