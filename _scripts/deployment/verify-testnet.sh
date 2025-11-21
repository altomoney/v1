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

ADDRESSES_FILE="contracts/deployments/testnet/output/testnet-${CHAIN_ID}-${DEPLOYMENT_TIMESTAMP}/addresses.json"

if [ ! -f "$ADDRESSES_FILE" ]; then
    echo "Error: Addresses file not found at $ADDRESSES_FILE"
    exit 1
fi

# Function to extract address from JSON
get_address() {
    local path=$1
    if command -v jq >/dev/null 2>&1; then
        # Use jq if available (more reliable)
        jq -r "$path // empty" "$ADDRESSES_FILE" 2>/dev/null
    else
        # Fallback to grep/sed for nested JSON
        case "$path" in
            *"wethMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/wethMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"wstethMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/wstethMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"tbtcMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/tbtcMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"sboldMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/sboldMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"rethMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/rethMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"susdeMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/susdeMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"rewardsBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/rewardsBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"stakingBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/stakingBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"tokens"*)
                cat "$ADDRESSES_FILE" | sed -n '/tokens/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *)
                cat "$ADDRESSES_FILE" | grep -o "\"$path\": \"[^\"]*\"" | cut -d'"' -f4
                ;;
        esac
    fi
}



echo "🔍 Starting contract verification on $CHAIN_ID..."
echo "📁 Using addresses from: $ADDRESSES_FILE"
echo ""

# Initialize verification tracking
VERIFICATION_RESULTS=()
SUCCESSFUL_VERIFICATIONS=0
FAILED_VERIFICATIONS=0

# Function to verify contract with rate limiting
verify_contract() {
    local name=$1
    local address=$2
    local contract_path=$3
    local extra_args=${4:-""}
    
    if [ -z "$address" ] || [ "$address" == "null" ]; then
        echo "⚠️  Skipping $name - no address found"
        VERIFICATION_RESULTS+=("SKIPPED: $name - no address found")
        return
    fi
    
    echo "🔍 Verifying $name at $address..."
    
    # Rate limiting: wait 0.5 seconds between requests to respect free account rate limit
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
            # Exponential backoff: wait longer on retries
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
    
    # Update last verification time
    LAST_VERIFICATION_TIME_MS=$(date +%s%3N)
    echo ""
}

# Extract addresses
if command -v jq >/dev/null 2>&1; then
    # Use jq paths for precise extraction
    ALTO_MULTICALL=$(get_address ".contracts.altoMulticall")
    ALTO_ADAPTER=$(get_address ".contracts.altoAdapter")
    ALTO_LEVERAGE=$(get_address ".contracts.altoLeverage")
    BUNDLER3=$(get_address ".contracts.bundler3")
    MOCK_SWAPPER=$(get_address ".contracts.mockSwapper")
    MULTI_TOKEN_SENDER=$(get_address ".contracts.multiTokenSender")
    
    # Mint market addresses
    ## WETH
    WETH_MARKET=$(get_address ".contracts.wethMarketBatch.market")
    WETH_MARKET_IMPL=$(get_address ".contracts.wethMarketBatch.marketImplementation")
    WETH_MARKET_IRM=$(get_address ".contracts.wethMarketBatch.marketIrm")
    WETH_MARKET_ORACLE=$(get_address ".contracts.wethMarketBatch.marketOracle")
    
    ## WSTETH
    WSTETH_MARKET=$(get_address ".contracts.wstethMarketBatch.market")
    WSTETH_MARKET_IMPL=$(get_address ".contracts.wstethMarketBatch.marketImplementation")
    WSTETH_MARKET_IRM=$(get_address ".contracts.wstethMarketBatch.marketIrm")
    WSTETH_MARKET_ORACLE=$(get_address ".contracts.wstethMarketBatch.marketOracle")

    ## RETH
    RETH_MARKET=$(get_address ".contracts.rethMarketBatch.market")
    RETH_MARKET_IMPL=$(get_address ".contracts.rethMarketBatch.marketImplementation")
    RETH_MARKET_IRM=$(get_address ".contracts.rethMarketBatch.marketIrm")
    RETH_MARKET_ORACLE=$(get_address ".contracts.rethMarketBatch.marketOracle")

    ## METH
    METH_MARKET=$(get_address ".contracts.methMarketBatch.market")
    METH_MARKET_IMPL=$(get_address ".contracts.methMarketBatch.marketImplementation")
    METH_MARKET_IRM=$(get_address ".contracts.methMarketBatch.marketIrm")
    METH_MARKET_ORACLE=$(get_address ".contracts.methMarketBatch.marketOracle")

    ## TBTC
    TBTC_MARKET=$(get_address ".contracts.tbtcMarketBatch.market")
    TBTC_MARKET_IMPL=$(get_address ".contracts.tbtcMarketBatch.marketImplementation")
    TBTC_MARKET_IRM=$(get_address ".contracts.tbtcMarketBatch.marketIrm")
    TBTC_MARKET_ORACLE=$(get_address ".contracts.tbtcMarketBatch.marketOracle")


    # Borrow market addresses
    ## WBTC
    WBTC_MARKET=$(get_address ".contracts.wbtcMarketBatch.market")
    WBTC_MARKET_IMPL=$(get_address ".contracts.wbtcMarketBatch.marketImplementation")
    WBTC_MARKET_IRM=$(get_address ".contracts.wbtcMarketBatch.marketIrm")
    WBTC_MARKET_ORACLE=$(get_address ".contracts.wbtcMarketBatch.marketOracle")

    ## CB-BTC
    CB_BTC_MARKET=$(get_address ".contracts.cbbtcMarketBatch.market")
    CB_BTC_MARKET_IMPL=$(get_address ".contracts.cbbtcMarketBatch.marketImplementation")
    CB_BTC_MARKET_IRM=$(get_address ".contracts.cbbtcMarketBatch.marketIrm")
    CB_BTC_MARKET_ORACLE=$(get_address ".contracts.cbbtcMarketBatch.marketOracle")

    ## SUSDE
    SUSDE_MARKET=$(get_address ".contracts.susdeMarketBatch.market")
    SUSDE_MARKET_IMPL=$(get_address ".contracts.susdeMarketBatch.marketImplementation")
    SUSDE_MARKET_IRM=$(get_address ".contracts.susdeMarketBatch.marketIrm")
    SUSDE_MARKET_ORACLE=$(get_address ".contracts.susdeMarketBatch.marketOracle")

    # Rewards batch addresses
	# Read paymentOracles array
	readarray -t PAYMENT_ORACLES < <(jq -r '.contracts.rewardsBatch.paymentOracles[]? // empty' "$ADDRESSES_FILE")
    REWARD_ORACLE=$(get_address ".contracts.rewardsBatch.rewardOracle")
    REWARDS_DISTRIBUTOR=$(get_address ".contracts.rewardsBatch.rewardsDistributor")
    
    # Staking batch addresses
    STAKING_CONTRACT=$(get_address ".contracts.stakingBatch.stakingContract")
    UNIVERSAL_REWARDS_DISTRIBUTOR=$(get_address ".contracts.stakingBatch.universalRewardsDistributor")
    
    # Token addresses
    ALTO_TOKEN=$(get_address ".tokens.alto")
    USDC_TOKEN=$(get_address ".tokens.usdc")
    DUSD_TOKEN=$(get_address ".tokens.dusd")
    WETH_TOKEN=$(get_address ".tokens.weth")
    WSTETH_TOKEN=$(get_address ".tokens.wsteth")
    RETH_TOKEN=$(get_address ".tokens.reth")
    METH_TOKEN=$(get_address ".tokens.meth")
    TBTC_TOKEN=$(get_address ".tokens.tbtc")
    WBTC_TOKEN=$(get_address ".tokens.wbtc")
    CB_BTC_TOKEN=$(get_address ".tokens.cbbtc")
    SUSDE_TOKEN=$(get_address ".tokens.susde")
else
    # Use fallback grep/sed paths
    ALTO_MULTICALL=$(get_address "altoMulticall")
    ALTO_ADAPTER=$(get_address "altoAdapter")
    ALTO_LEVERAGE=$(get_address "altoLeverage")
    BUNDLER3=$(get_address "bundler3")
    MOCK_SWAPPER=$(get_address "mockSwapper")
    MULTI_TOKEN_SENDER=$(get_address "multiTokenSender")
    
    # Mint market addresses
    ## WETH
    WETH_MARKET=$(get_address "wethMarketBatch.market")
    WETH_MARKET_IMPL=$(get_address "wethMarketBatch.marketImplementation")
    WETH_MARKET_IRM=$(get_address "wethMarketBatch.marketIrm")
    WETH_MARKET_ORACLE=$(get_address "wethMarketBatch.marketOracle")

    ## WSTETH
    WSTETH_MARKET=$(get_address "wstethMarketBatch.market")
    WSTETH_MARKET_IMPL=$(get_address "wstethMarketBatch.marketImplementation")
    WSTETH_MARKET_IRM=$(get_address "wstethMarketBatch.marketIrm")
    WSTETH_MARKET_ORACLE=$(get_address "wstethMarketBatch.marketOracle")

    ## RETH
    RETH_MARKET=$(get_address "rethMarketBatch.market")
    RETH_MARKET_IMPL=$(get_address "rethMarketBatch.marketImplementation")
    RETH_MARKET_IRM=$(get_address "rethMarketBatch.marketIrm")
    RETH_MARKET_ORACLE=$(get_address "rethMarketBatch.marketOracle")

    ## METH
    METH_MARKET=$(get_address "methMarketBatch.market")
    METH_MARKET_IMPL=$(get_address "methMarketBatch.marketImplementation")
    METH_MARKET_IRM=$(get_address "methMarketBatch.marketIrm")
    METH_MARKET_ORACLE=$(get_address "methMarketBatch.marketOracle")

    ## TBTC
    TBTC_MARKET=$(get_address "tbtcMarketBatch.market")
    TBTC_MARKET_IMPL=$(get_address "tbtcMarketBatch.marketImplementation")
    TBTC_MARKET_IRM=$(get_address "tbtcMarketBatch.marketIrm")
    TBTC_MARKET_ORACLE=$(get_address "tbtcMarketBatch.marketOracle")

    # Borrow Market Addresses
    ## WBTC
    WBTC_MARKET=$(get_address "wbtcMarketBatch.market")
    WBTC_MARKET_IMPL=$(get_address "wbtcMarketBatch.marketImplementation")
    WBTC_MARKET_IRM=$(get_address "wbtcMarketBatch.marketIrm")
    WBTC_MARKET_ORACLE=$(get_address "wbtcMarketBatch.marketOracle")

    ## CB-BTC
    CB_BTC_MARKET=$(get_address "cbbtcMarketBatch.market")
    CB_BTC_MARKET_IMPL=$(get_address "cbbtcMarketBatch.marketImplementation")
    CB_BTC_MARKET_IRM=$(get_address "cbbtcMarketBatch.marketIrm")
    CB_BTC_MARKET_ORACLE=$(get_address "cbbtcMarketBatch.marketOracle")

    ## SUSDE
    SUSDE_MARKET=$(get_address "susdeMarketBatch.market")
    SUSDE_MARKET_IMPL=$(get_address "susdeMarketBatch.marketImplementation")
    SUSDE_MARKET_IRM=$(get_address "susdeMarketBatch.marketIrm")
    SUSDE_MARKET_ORACLE=$(get_address "susdeMarketBatch.marketOracle")

    # Rewards batch addresses
	# Fallback parse for paymentOracles array
	PAYMENT_ORACLES=($(sed -n '/"rewardsBatch"/,/}/p' "$ADDRESSES_FILE" | sed -n '/"paymentOracles"/,$p' | sed -n '1,/]/p' | grep -o '0x[0-9a-fA-F]\{40\}'))
    REWARD_ORACLE=$(get_address "rewardsBatch.rewardOracle")
    REWARDS_DISTRIBUTOR=$(get_address "rewardsBatch.rewardsDistributor")
    
    # Staking batch addresses
    STAKING_CONTRACT=$(get_address "stakingBatch.stakingContract")
    UNIVERSAL_REWARDS_DISTRIBUTOR=$(get_address "stakingBatch.universalRewardsDistributor")
    
    # Token addresses
    ALTO_TOKEN=$(get_address "tokens.alto")
    USDC_TOKEN=$(get_address "tokens.usdc")
    DUSD_TOKEN=$(get_address "tokens.dusd")
    WETH_TOKEN=$(get_address "tokens.weth")
    WSTETH_TOKEN=$(get_address "tokens.wsteth")
    RETH_TOKEN=$(get_address "tokens.reth")
    METH_TOKEN=$(get_address "tokens.meth")
    TBTC_TOKEN=$(get_address "tokens.tbtc")
    WBTC_TOKEN=$(get_address "tokens.wbtc")
    CB_BTC_TOKEN=$(get_address "tokens.cbbtc")
    SUSDE_TOKEN=$(get_address "tokens.susde")
fi

echo "📋 Contract verification plan:"
echo "- Alto Adapter: $ALTO_ADAPTER"
echo "- Alto Leverage: $ALTO_LEVERAGE"
echo "- Bundler3: $BUNDLER3"
echo "- Mock Swapper: $MOCK_SWAPPER"
echo "- Multi Token Sender: $MULTI_TOKEN_SENDER"
echo "- WETH Market: $WETH_MARKET"
echo "- WETH Market Implementation: $WETH_MARKET_IMPL"
echo "- WETH Market IRM: $WETH_MARKET_IRM"
echo "- WETH Market Oracle: $WETH_MARKET_ORACLE"
echo "- WSTETH Market: $WSTETH_MARKET"
echo "- WSTETH Market Implementation: $WSTETH_MARKET_IMPL"
echo "- WSTETH Market IRM: $WSTETH_MARKET_IRM"
echo "- WSTETH Market Oracle: $WSTETH_MARKET_ORACLE"
echo "- RETH Market: $RETH_MARKET"
echo "- RETH Market Implementation: $RETH_MARKET_IMPL"
echo "- RETH Market IRM: $RETH_MARKET_IRM"
echo "- RETH Market Oracle: $RETH_MARKET_ORACLE"
echo "- METH Market: $METH_MARKET"
echo "- METH Market Implementation: $METH_MARKET_IMPL"
echo "- METH Market IRM: $METH_MARKET_IRM"
echo "- METH Market Oracle: $METH_MARKET_ORACLE"
echo "- TBTC Market: $TBTC_MARKET"
echo "- TBTC Market Implementation: $TBTC_MARKET_IMPL"
echo "- TBTC Market IRM: $TBTC_MARKET_IRM"
echo "- TBTC Market Oracle: $TBTC_MARKET_ORACLE"
echo "- WBTC Market: $WBTC_MARKET"
echo "- WBTC Market Implementation: $WBTC_MARKET_IMPL"
echo "- WBTC Market IRM: $WBTC_MARKET_IRM"
echo "- WBTC Market Oracle: $WBTC_MARKET_ORACLE"
echo "- CB-BTC Market: $CB_BTC_MARKET"
echo "- CB-BTC Market Implementation: $CB_BTC_MARKET_IMPL"
echo "- CB-BTC Market IRM: $CB_BTC_MARKET_IRM"
echo "- CB-BTC Market Oracle: $CB_BTC_MARKET_ORACLE"
echo "- SUSDE Market Implementation: $SUSDE_MARKET_IMPL"
echo "- SUSDE Market IRM: $SUSDE_MARKET_IRM"
echo "- SUSDE Market Oracle: $SUSDE_MARKET_ORACLE"
echo "- Payment Oracles:"
for addr in "${PAYMENT_ORACLES[@]}"; do
    echo "  - $addr"
done
echo "- Reward Oracle: $REWARD_ORACLE"
echo "- Rewards Distributor: $REWARDS_DISTRIBUTOR"
echo "- Staking Contract: $STAKING_CONTRACT"
echo "- Universal Rewards Distributor: $UNIVERSAL_REWARDS_DISTRIBUTOR"
echo "- Alto Token: $ALTO_TOKEN"
echo "- USDC Token: $USDC_TOKEN"
echo "- DUSD Token: $DUSD_TOKEN"
echo "- WETH Token: $WETH_TOKEN"
echo "- WSTETH Token: $WSTETH_TOKEN"
echo "- RETH Token: $RETH_TOKEN"
echo "- METH Token: $METH_TOKEN"
echo "- TBTC Token: $TBTC_TOKEN"
echo "- WBTC Token: $WBTC_TOKEN"
echo "- CB-BTC Token: $CB_BTC_TOKEN"
echo "- SUSDE Token: $SUSDE_TOKEN"
echo ""

read -p "Do you want to proceed with verification? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Verification cancelled."
    exit 0
fi

echo "🚀 Starting verification process..."
echo "⏰ This process will take approximately 1-2 minutes due to rate limiting..."
echo ""

# Initialize progress tracking (base excludes payment oracles)
BASE_CONTRACTS=43
TOTAL_CONTRACTS=$((BASE_CONTRACTS + ${#PAYMENT_ORACLES[@]}))
CURRENT_CONTRACT=0

# Function to show progress
show_progress() {
    CURRENT_CONTRACT=$((CURRENT_CONTRACT + 1))
    echo "📊 Progress: $CURRENT_CONTRACT/$TOTAL_CONTRACTS contracts processed"
}

# Verify contracts
verify_contract "AltoMulticall" "$ALTO_MULTICALL" "contracts/deployments/testnet/contracts/AltoMulticallTestnet.sol:AltoMulticallTestnet"
show_progress
verify_contract "AltoAdapter" "$ALTO_ADAPTER" "contracts/utils/AltoAdapter.sol:AltoAdapter"
show_progress
verify_contract "AltoLeverage" "$ALTO_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"
show_progress
verify_contract "Bundler3" "$BUNDLER3" "lib/bundler3/src/Bundler3.sol:Bundler3"
show_progress
verify_contract "MockSwapper" "$MOCK_SWAPPER" "contracts/lending/mocks/SwapperSimpleMock.sol:SwapperSimpleMock"
show_progress
verify_contract "MultiTokenSender" "$MULTI_TOKEN_SENDER" "contracts/deployments/testnet/contracts/MultiTokenSender.sol:MultiTokenSender"
show_progress

# Verify market contracts (these might be proxy contracts, so we verify the implementation)
verify_contract "WethMarket" "$WETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "WethMarketImplementation" "$WETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "WethMarketIRM" "$WETH_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "WethMarketOracle" "$WETH_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "WstethMarket" "$WSTETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "WstethMarketImplementation" "$WSTETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "WstethMarketIRM" "$WSTETH_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "WstethMarketOracle" "$WSTETH_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "TbtcMarket" "$TBTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "TbtcMarketImplementation" "$TBTC_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "TbtcMarketIRM" "$TBTC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "TbtcMarketOracle" "$TBTC_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "RethMarket" "$RETH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "RethMarketImplementation" "$RETH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "RethMarketIRM" "$RETH_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "RethMarketOracle" "$RETH_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "MethMarket" "$METH_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "MethMarketImplementation" "$METH_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "MethMarketIRM" "$METH_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "MethMarketOracle" "$METH_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "WbtcMarket" "$WBTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "WbtcMarketImplementation" "$WBTC_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
show_progress
verify_contract "WbtcMarketIRM" "$WBTC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "WbtcMarketOracle" "$WBTC_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "Cbb" "$CB_BTC_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "CbbMarketImplementation" "$CB_BTC_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
show_progress
verify_contract "CbbMarketIRM" "$CB_BTC_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "CbbMarketOracle" "$CB_BTC_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "SusdeMarket" "$SUSDE_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "SusdeMarketImplementation" "$SUSDE_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
show_progress
verify_contract "SusdeMarketIRM" "$SUSDE_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "SusdeMarketOracle" "$SUSDE_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress


# Verify rewards contracts
for addr in "${PAYMENT_ORACLES[@]}"; do
    verify_contract "PaymentOracle" "$addr" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
    show_progress
done
verify_contract "RewardOracle" "$REWARD_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress
verify_contract "RewardsDistributor" "$REWARDS_DISTRIBUTOR" "contracts/rewards/AltoRewardsDistributor.sol:AltoRewardsDistributor"
show_progress

# Verify staking contracts
verify_contract "StakingContract" "$STAKING_CONTRACT" "contracts/staking/AltoStaking.sol:AltoStaking"
show_progress
verify_contract "UniversalRewardsDistributor" "$UNIVERSAL_REWARDS_DISTRIBUTOR" "contracts/utils/UniversalRewardsDistributor.sol:UniversalRewardsDistributor"
show_progress

# Verify token contracts
verify_contract "AltoToken" "$ALTO_TOKEN" "contracts/tokens/AltoToken.sol:AltoToken"
show_progress
verify_contract "USDCToken" "$USDC_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "DUSDToken" "$DUSD_TOKEN" "contracts/tokens/DUSD.sol:DUSD"
show_progress
verify_contract "WETHToken" "$WETH_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "WSTETHToken" "$WSTETH_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "RETHToken" "$RETH_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "METHToken" "$METH_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "TBTCToken" "$TBTC_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "WBTCToken" "$WBTC_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "CB_BTC_TOKEN" "$CB_BTC_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress
verify_contract "SUSDEToken" "$SUSDE_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
show_progress

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

echo "🔗 Check the Etherscan explorer to see the verification status:"
echo "$VERIFIER_URL"
echo ""
echo "💡 Tip: You can also run individual verifications using:"
echo "forge verify-contract --chain-id $CHAIN_ID --verifier-url $VERIFIER_URL --etherscan-api-key \$ETHERSCAN_API_KEY <address> <contract_path>"
