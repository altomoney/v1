#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"


# Check required environment variables
if [ -z "$ETHERSCAN_API_KEY" ] || [ -z "$ETHERSCAN_API_URL" ] || [ -z "$CHAIN_ID" ] || [ -z "$DEPLOYMENT_TIMESTAMP" ]; then
    echo "Error: Missing required environment variables for verification. Please check your .env file."
    echo "Required: ETHERSCAN_API_KEY, ETHERSCAN_API_URL, CHAIN_ID, DEPLOYMENT_TIMESTAMP"
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



echo "🔍 Starting contract verification on Holesky testnet..."
echo "📁 Using addresses from: $ADDRESSES_FILE"
echo ""

# Function to verify contract
verify_contract() {
    local name=$1
    local address=$2
    local contract_path=$3
    local extra_args=${4:-""}
    
    if [ -z "$address" ] || [ "$address" == "null" ]; then
        echo "⚠️  Skipping $name - no address found"
        return
    fi
    
    echo "🔍 Verifying $name at $address..."
    
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
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully verified $name"
    else
        echo "❌ Failed to verify $name"
    fi
    echo ""
}

# Extract addresses
if command -v jq >/dev/null 2>&1; then
    # Use jq paths for precise extraction
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
    USDO_TOKEN=$(get_address ".tokens.usdo")
    WETH_TOKEN=$(get_address ".tokens.weth")
else
    # Use fallback grep/sed paths
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
    USDO_TOKEN=$(get_address "tokens.usdo")
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
echo "- USDO Token: $USDO_TOKEN"
echo "- WETH Token: $WETH_TOKEN"
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
verify_contract "AltoAdapter" "$ALTO_ADAPTER" "contracts/utils/AltoAdapter.sol:AltoAdapter"
verify_contract "AltoLeverage" "$ALTO_LEVERAGE" "contracts/lending/leverage/AltoLeverage.sol:AltoLeverage"
verify_contract "Bundler3" "$BUNDLER3" "lib/bundler3/src/Bundler3.sol:Bundler3"
verify_contract "MockSwapper" "$MOCK_SWAPPER" "contracts/lending/mocks/SwapperSimpleMock.sol:SwapperSimpleMock"
verify_contract "MultiTokenSender" "$MULTI_TOKEN_SENDER" "contracts/deployments/testnet/contracts/MultiTokenSender.sol:MultiTokenSender"

# Verify market contracts (these might be proxy contracts, so we verify the implementation)
verify_contract "BorrowMarket" "$BORROW_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "BorrowMarketImplementation" "$BORROW_MARKET_IMPL" "contracts/lending/AltoBorrowMarket.sol:AltoBorrowMarket"
verify_contract "BorrowMarketIRM" "$BORROW_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "BorrowMarketOracle" "$BORROW_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"

verify_contract "MintMarket" "$MINT_MARKET" "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
verify_contract "MintMarketImplementation" "$MINT_MARKET_IMPL" "contracts/lending/AltoMintMarket.sol:AltoMintMarket"
verify_contract "MintMarketIRM" "$MINT_MARKET_IRM" "contracts/lending/irm/AdaptiveCurveIrm.sol:AdaptiveCurveIrm"
verify_contract "MintMarketOracle" "$MINT_MARKET_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"

# Verify rewards contracts
verify_contract "PaymentOracle" "$PAYMENT_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
verify_contract "RewardOracle" "$REWARD_ORACLE" "contracts/deployments/testnet/contracts/OracleTestnet.sol:OracleTestnet"
verify_contract "RewardsDistributor" "$REWARDS_DISTRIBUTOR" "contracts/rewards/AltoRewardsDistributor.sol:AltoRewardsDistributor"

# Verify staking contracts
verify_contract "StakingContract" "$STAKING_CONTRACT" "contracts/staking/AltoStaking.sol:AltoStaking"
verify_contract "UniversalRewardsDistributor" "$UNIVERSAL_REWARDS_DISTRIBUTOR" "lib/universal-rewards-distributor/src/UniversalRewardsDistributor.sol:UniversalRewardsDistributor" "--compiler-version 0.8.19"

# Verify token contracts
verify_contract "AltoToken" "$ALTO_TOKEN" "contracts/tokens/AltoToken.sol:AltoToken"
verify_contract "USDCToken" "$USDC_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"
verify_contract "USDOToken" "$USDO_TOKEN" "contracts/tokens/USDO.sol:USDO"
verify_contract "WETHToken" "$WETH_TOKEN" "contracts/deployments/testnet/contracts/ERC20Testnet.sol:ERC20Testnet"

echo "🎉 Contract verification process completed!"
echo "Check the Holesky Etherscan explorer to see the verification status:"
echo "https://holesky.etherscan.io/"
