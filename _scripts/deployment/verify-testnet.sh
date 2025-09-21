#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"


# Check required environment variables
if [ -z "$ETHERSCAN_API_KEY" ] || [ -z "$ETHERSCAN_API_URL" ] || [ -z "$CHAIN_ID" ]; then
    echo "Error: Missing required environment variables for verification. Please check your .env file."
    echo "Required: ETHERSCAN_API_KEY, ETHERSCAN_API_URL, CHAIN_ID"
    exit 1
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
            *"borrowMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/borrowMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
                ;;
            *"mintMarketBatch"*)
                cat "$ADDRESSES_FILE" | sed -n '/mintMarketBatch/,/}/p' | grep "${path##*.}" | cut -d'"' -f4
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
    
    # Rate limiting: wait 3 seconds between requests to respect 2/sec limit
    if [ -n "${LAST_VERIFICATION_TIME:-}" ]; then
        local current_time=$(date +%s)
        local time_diff=$((current_time - LAST_VERIFICATION_TIME))
        if [ $time_diff -lt 3 ]; then
            local sleep_time=$((3 - time_diff))
            echo "⏳ Rate limiting: waiting ${sleep_time} seconds..."
            sleep $sleep_time
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
                --verifier-url $ETHERSCAN_API_URL \
                --etherscan-api-key $ETHERSCAN_API_KEY \
                $extra_args \
                $address \
                $contract_path
        else
            forge verify-contract \
                --chain-id $CHAIN_ID \
                --verifier-url $ETHERSCAN_API_URL \
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
    LAST_VERIFICATION_TIME=$(date +%s)
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
    
    # Borrow market addresses
    BORROW_MARKET=$(get_address ".contracts.borrowMarketBatch.market")
    BORROW_MARKET_IMPL=$(get_address ".contracts.borrowMarketBatch.marketImplementation")
    BORROW_MARKET_IRM=$(get_address ".contracts.borrowMarketBatch.marketIrm")
    BORROW_MARKET_ORACLE=$(get_address ".contracts.borrowMarketBatch.marketOracle")
    
    # Mint market addresses
    MINT_MARKET=$(get_address ".contracts.mintMarketBatch.market")
    MINT_MARKET_IMPL=$(get_address ".contracts.mintMarketBatch.marketImplementation")
    MINT_MARKET_IRM=$(get_address ".contracts.mintMarketBatch.marketIrm")
    MINT_MARKET_ORACLE=$(get_address ".contracts.mintMarketBatch.marketOracle")
    
    # Rewards batch addresses
    PAYMENT_ORACLE=$(get_address ".contracts.rewardsBatch.paymentOracle")
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
else
    # Use fallback grep/sed paths
    ALTO_MULTICALL=$(get_address "altoMulticall")
    ALTO_ADAPTER=$(get_address "altoAdapter")
    ALTO_LEVERAGE=$(get_address "altoLeverage")
    BUNDLER3=$(get_address "bundler3")
    MOCK_SWAPPER=$(get_address "mockSwapper")
    MULTI_TOKEN_SENDER=$(get_address "multiTokenSender")
    
    # Borrow market addresses
    BORROW_MARKET=$(get_address "borrowMarketBatch.market")
    BORROW_MARKET_IMPL=$(get_address "borrowMarketBatch.marketImplementation")
    BORROW_MARKET_IRM=$(get_address "borrowMarketBatch.marketIrm")
    BORROW_MARKET_ORACLE=$(get_address "borrowMarketBatch.marketOracle")
    
    # Mint market addresses
    MINT_MARKET=$(get_address "mintMarketBatch.market")
    MINT_MARKET_IMPL=$(get_address "mintMarketBatch.marketImplementation")
    MINT_MARKET_IRM=$(get_address "mintMarketBatch.marketIrm")
    MINT_MARKET_ORACLE=$(get_address "mintMarketBatch.marketOracle")
    
    # Rewards batch addresses
    PAYMENT_ORACLE=$(get_address "rewardsBatch.paymentOracle")
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
fi

echo "📋 Contract verification plan:"
echo "- Alto Adapter: $ALTO_ADAPTER"
echo "- Alto Leverage: $ALTO_LEVERAGE"
echo "- Bundler3: $BUNDLER3"
echo "- Mock Swapper: $MOCK_SWAPPER"
echo "- Multi Token Sender: $MULTI_TOKEN_SENDER"
echo "- Borrow Market: $BORROW_MARKET"
echo "- Borrow Market Implementation: $BORROW_MARKET_IMPL"
echo "- Borrow Market IRM: $BORROW_MARKET_IRM"
echo "- Borrow Market Oracle: $BORROW_MARKET_ORACLE"
echo "- Mint Market: $MINT_MARKET"
echo "- Mint Market Implementation: $MINT_MARKET_IMPL"
echo "- Mint Market IRM: $MINT_MARKET_IRM"
echo "- Mint Market Oracle: $MINT_MARKET_ORACLE"
echo "- Payment Oracle: $PAYMENT_ORACLE"
echo "- Reward Oracle: $REWARD_ORACLE"
echo "- Rewards Distributor: $REWARDS_DISTRIBUTOR"
echo "- Staking Contract: $STAKING_CONTRACT"
echo "- Universal Rewards Distributor: $UNIVERSAL_REWARDS_DISTRIBUTOR"
echo "- Alto Token: $ALTO_TOKEN"
echo "- USDC Token: $USDC_TOKEN"
echo "- DUSD Token: $DUSD_TOKEN"
echo "- WETH Token: $WETH_TOKEN"
echo ""

read -p "Do you want to proceed with verification? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Verification cancelled."
    exit 0
fi

echo "🚀 Starting verification process..."
echo "⏰ This process will take approximately 3-5 minutes due to rate limiting..."
echo ""

# Initialize progress tracking
TOTAL_CONTRACTS=21
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
verify_contract "BorrowMarket" "$BORROW_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "BorrowMarketImplementation" "$BORROW_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
show_progress
verify_contract "BorrowMarketIRM" "$BORROW_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "BorrowMarketOracle" "$BORROW_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

verify_contract "MintMarket" "$MINT_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
show_progress
verify_contract "MintMarketImplementation" "$MINT_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
show_progress
verify_contract "MintMarketIRM" "$MINT_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
show_progress
verify_contract "MintMarketOracle" "$MINT_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress

# Verify rewards contracts
verify_contract "PaymentOracle" "$PAYMENT_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
show_progress
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
echo "$ETHERSCAN_API_URL"
echo ""
echo "💡 Tip: You can also run individual verifications using:"
echo "forge verify-contract --chain-id $CHAIN_ID --verifier-url $ETHERSCAN_API_URL --etherscan-api-key \$ETHERSCAN_API_KEY <address> <contract_path>"
