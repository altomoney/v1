source .env.contracts
COMPILER_VERSION="0.8.28"
WATCH_VERIFICATION=true
SEPARATOR='\n--------------------------------------------------------------------------------\n'
EXPLORER_URL_BASE="https://holesky.etherscan.io/address/CONTRACT_ADDRESS#code"


if [ "$WATCH_VERIFICATION" = "true" ]; then
    WATCH_FLAG="--watch"
else
    WATCH_FLAG=""
fi

# Function to replace CONTRACT_ADDRESS with actual contract address
get_explorer_url() {
  local contract_address=$1
  echo "${EXPLORER_URL_BASE/CONTRACT_ADDRESS/$contract_address}"
}

echo 'WATCH_FLAG: '$WATCH_FLAG
echo 'COMPILER_VERSION: '$COMPILER_VERSION
echo 'CHAIN_ID: '$CHAIN_ID
echo 'IsTestnet: '$IsTestnet
echo 'Deployer: '$Deployer
echo 'LzChainId: '$LzChainId
echo 'MagnetarCollateralModule: '$MagnetarCollateralModule
echo 'MagnetarMintModule: '$MagnetarMintModule
echo 'MagnetarOptionModule: '$MagnetarOptionModule
echo 'MagnetarLeverageModule: '$MagnetarLeverageModule
echo 'ToeHelper: '$ToeHelper
echo 'Cluster: '$Cluster
echo 'MagnetarHelper: '$MagnetarHelper
echo 'TapToken: '$TapToken
echo 'WrappedNativeToken: '$WrappedNativeToken
echo 'BarProcedure: '$BarProcedure
echo 'Penrose: '$Penrose
echo 'ZeroXSwapper: '$ZeroXSwapper
echo 'SimpleLeverageExecutor: '$SimpleLeverageExecutor
echo 'Magnetar: '$Magnetar
echo 'Usdo: '$Usdo
echo 'SGLInit: '$SGLInit
echo 'SGLInterestHelper: '$SGLInterestHelper
echo 'SGLLiquidation: '$SGLLiquidation
echo 'SGLBorrow: '$SGLBorrow
echo 'SGLCollateral: '$SGLCollateral

export COMPILER_VERSION=$COMPILER_VERSION
export CHAIN_ID=$CHAIN_ID
export IsTestnet=$IsTestnet
export Deployer=$Deployer
export LzChainId=$LzChainId
export MagnetarCollateralModule=$MagnetarCollateralModule
export MagnetarMintModule=$MagnetarMintModule
export MagnetarOptionModule=$MagnetarOptionModule
export MagnetarLeverageModule=$MagnetarLeverageModule
export ToeHelper=$ToeHelper
export Cluster=$Cluster
export MagnetarHelper=$MagnetarHelper
export TapToken=$TapToken
export WrappedNativeToken=$WrappedNativeToken
export BarProcedure=$BarProcedure
export Penrose=$Penrose
export ZeroXSwapper=$ZeroXSwapper
export SimpleLeverageExecutor=$SimpleLeverageExecutor
export Magnetar=$Magnetar
export Usdo=$Usdo
export SGLInit=$SGLInit
export SGLInterestHelper=$SGLInterestHelper
export SGLLiquidation=$SGLLiquidation
export SGLBorrow=$SGLBorrow
export SGLCollateral=$SGLCollateral

## Magnetar modules

echo -e $SEPARATOR

# MagnetarCollateralModule
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $MagnetarCollateralModule ./contracts/periph/Magnetar/modules/MagnetarCollateralModule.sol:MagnetarCollateralModule --constructor-args $(cast abi-encode "constructor(address _tokenHelper, address _magnetarHelper)" $ToeHelper $MagnetarHelper)

MODULE_EXPLORER_URL=$(get_explorer_url $MagnetarCollateralModule)
echo "Etherscan URL for MagnetarCollateralModule: $MODULE_EXPLORER_URL"

echo -e $SEPARATOR

# MagnetarMintModule
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $MagnetarMintModule ./contracts/periph/Magnetar/modules/MagnetarMintModule.sol:MagnetarMintModule --constructor-args $(cast abi-encode "constructor(address _tokenHelper, address _magnetarHelper)" $ToeHelper $MagnetarHelper)

MODULE_EXPLORER_URL=$(get_explorer_url $MagnetarMintModule)
echo "Etherscan URL for MagnetarMintModule: $MODULE_EXPLORER_URL"

echo -e $SEPARATOR

# MagnetarOptionModule
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $MagnetarOptionModule ./contracts/periph/Magnetar/modules/MagnetarOptionModule.sol:MagnetarOptionModule --constructor-args $(cast abi-encode "constructor(address _tokenHelper, address _magnetarHelper)" $ToeHelper $MagnetarHelper)

MODULE_EXPLORER_URL=$(get_explorer_url $MagnetarOptionModule)
echo "Etherscan URL for MagnetarOptionModule: $MODULE_EXPLORER_URL"

echo -e $SEPARATOR

# MagnetarLeverageModule
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $MagnetarLeverageModule ./contracts/periph/Magnetar/modules/MagnetarLeverageModule.sol:MagnetarLeverageModule --constructor-args $(cast abi-encode "constructor(address _tokenHelper, address _magnetarHelper)" $ToeHelper $MagnetarHelper)

MODULE_EXPLORER_URL=$(get_explorer_url $MagnetarLeverageModule)
echo "Etherscan URL for MagnetarLeverageModule: $MODULE_EXPLORER_URL"

echo -e $SEPARATOR

# Cluster
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $Cluster ./contracts/utils/Cluster/Cluster.sol:Cluster --constructor-args $(cast abi-encode "constructor(uint32 _lzChainId, address _owner)" $LzChainId $Deployer)

CLUSTER_EXPLORER_URL=$(get_explorer_url $Cluster)
echo "Etherscan URL for Cluster: $CLUSTER_EXPLORER_URL"

echo -e $SEPARATOR

# MagnetarHelper
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $MagnetarHelper ./contracts/periph/Magnetar/MagnetarHelper.sol:MagnetarHelper

MAGNETAR_HELPER_EXPLORER_URL=$(get_explorer_url $MagnetarHelper)
echo "Etherscan URL for MagnetarHelper: $MAGNETAR_HELPER_EXPLORER_URL"

echo -e $SEPARATOR

# TapToken
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $TapToken ./contracts/tap-token/tokens/TapToken.sol:TapToken

TAP_TOKEN_EXPLORER_URL=$(get_explorer_url $TapToken)
echo "Etherscan URL for TapToken: $TAP_TOKEN_EXPLORER_URL"

echo -e $SEPARATOR

# ToeHelper
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $ToeHelper ./contracts/utils/tapiocaOmnichainEngine/extension/TapiocaOmnichainEngineHelper.sol:TapiocaOmnichainEngineHelper

TOE_HELPER_EXPLORER_URL=$(get_explorer_url $ToeHelper)
echo "Etherscan URL for ToeHelper: $TOE_HELPER_EXPLORER_URL"

echo -e $SEPARATOR

# Penrose
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $Penrose ./contracts/bar/Penrose.sol:Penrose
#--constructor-args $(cast abi-encode "constructor(address _cluster, address tapToken_, address mainToken_, address _owner)" $Cluster $TapToken $WrappedNativeToken $BarProcedure)

PENROSE_EXPLORER_URL=$(get_explorer_url $Penrose)
echo "Etherscan URL for Penrose: $PENROSE_EXPLORER_URL"

echo -e $SEPARATOR

# SimpleLeverageExecutor
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SimpleLeverageExecutor ./contracts/bar/markets/leverage/SimpleLeverageExecutor.sol:SimpleLeverageExecutor --constructor-args $(cast abi-encode "constructor(address _swapper, address _cluster, address _weth)" $Cluster $ZeroXSwapper $Cluster $WrappedNativeToken)

SIMPLE_LEVERAGE_EXECUTOR_EXPLORER_URL=$(get_explorer_url $SimpleLeverageExecutor)
echo "Etherscan URL for SimpleLeverageExecutor: $SIMPLE_LEVERAGE_EXECUTOR_EXPLORER_URL"

echo -e $SEPARATOR

# ZeroXSwapper

if [ "$IsTestnet" = "true" ]; then
  forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $ZeroXSwapper ./contracts/mocks/ZeroXSwapperMock.sol:ZeroXSwapperMock --constructor-args $(cast abi-encode "constructor(address _cluster, address _owner)" $Cluster $Deployer)

  ZERO_X_SWAPPER_MOCK_EXPLORER_URL=$(get_explorer_url $ZeroXSwapper)
  echo "Etherscan URL for ZeroXSwapperMock: $ZERO_X_SWAPPER_MOCK_EXPLORER_URL"
else
  forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $ZeroXSwapper ./contracts/utils/Swapper/ZeroXSwapper.sol:ZeroXSwapper --constructor-args $(cast abi-encode "constructor(address _zeroProxy, address _cluster, address _owner)" $ZeroXProxy $Cluster $Deployer)

    ZERO_X_SWAPPER_EXPLORER_URL=$(get_explorer_url $ZeroXSwapper)
    echo "Etherscan URL for ZeroXSwapper: $ZERO_X_SWAPPER_EXPLORER_URL"
fi

echo -e $SEPARATOR

# Magnetar
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $Magnetar ./contracts/periph/Magnetar/Magnetar.sol:Magnetar --constructor-args $(cast abi-encode "constructor(address _cluster, address _owner, address _collateralModule, address _mintModule, address _optionModule, address _leverageModule, address _toeHelper, address _magnetarHelper)" $Cluster $Deployer $MagnetarCollateralModule $MagnetarMintModule $MagnetarOptionModule $MagnetarLeverageModule $ToeHelper $MagnetarHelper)

MAGNETAR_EXPLORER_URL=$(get_explorer_url $Magnetar)
echo "Etherscan URL for Magnetar: $MAGNETAR_EXPLORER_URL"

echo -e $SEPARATOR

# Usdo
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $Usdo ./contracts/bar/usdo/Usdo.sol:Usdo 
# --constructor-args $(cast abi-encode "constructor(UsdoInitStruct memory _initData, UsdoModulesInitStruct memory _modulesData)" $UsdoInitStruct $UsdoModulesInitStruct)

USDO_EXPLORER_URL=$(get_explorer_url $Usdo)
echo "Etherscan URL for Usdo: $USDO_EXPLORER_URL"

echo -e $SEPARATOR

# SGLInit
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SGLInit ./contracts/bar/markets/singularity/SGLInit.sol:SGLInit

SGL_INIT_EXPLORER_URL=$(get_explorer_url $SGLInit)
echo "Etherscan URL for SGLInit: $SGL_INIT_EXPLORER_URL"

echo -e $SEPARATOR

# SGLInterestHelper
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SGLInterestHelper ./contracts/bar/markets/singularity/SGLInterestHelper.sol:SGLInterestHelper

SGL_INTEREST_HELPER_EXPLORER_URL=$(get_explorer_url $SGLInterestHelper)
echo "Etherscan URL for SGLInterestHelper: $SGL_INTEREST_HELPER_EXPLORER_URL"

echo -e $SEPARATOR

# SGLLiquidation No Working
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SGLLiquidation ./contracts/bar/markets/singularity/SGLLiquidation.sol:SGLLiquidation

SGL_LIQUIDATION_EXPLORER_URL=$(get_explorer_url $SGLLiquidation)
echo "Etherscan URL for SGLLiquidation: $SGL_LIQUIDATION_EXPLORER_URL"

echo -e $SEPARATOR

# SGLBorrow No Working
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SGLBorrow ./contracts/bar/markets/singularity/SGLBorrow.sol:SGLBorrow

SGL_BORROW_EXPLORER_URL=$(get_explorer_url $SGLBorrow)
echo "Etherscan URL for SGLBorrow: $SGL_BORROW_EXPLORER_URL"

echo -e $SEPARATOR

# SGLCollateral No Working
forge verify-contract --chain-id $CHAIN_ID --compiler-version $COMPILER_VERSION --verifier etherscan $WATCH_FLAG $SGLCollateral ./contracts/bar/markets/singularity/SGLCollateral.sol:SGLCollateral

SGL_COLLATERAL_EXPLORER_URL=$(get_explorer_url $SGLCollateral)
echo "Etherscan URL for SGLCollateral: $SGL_COLLATERAL_EXPLORER_URL"

echo -e $SEPARATOR