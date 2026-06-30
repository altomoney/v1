// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IStableTokenFacilitator} from "./interfaces/IStableTokenFacilitator.sol";
import {IUsmPriceStrategy} from "./interfaces/IUsmPriceStrategy.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "./interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {IAdvancedPermissionsUsm, DirectionAccess} from "./interfaces/IAdvancedPermissionsUsm.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title AdvancedPermissionsUsm
 * @author GPM
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Universal Stability Module with independent buy and sell access control.
 * @dev Lets the protocol configure who may swap in each direction: buy and sell
 *      each use `DirectionAccess` (`PERMISSIONED`, `PERMISSIONLESS`).
 *      In `PERMISSIONED` mode, `BUY_SWAPPER_ROLE` gates buys and `SELL_SWAPPER_ROLE` gates sells; in
 *      `PERMISSIONLESS` mode anyone may call that direction.
 * @dev Fee quotes and settlement use `IAdvancedPermissionsUsmFeeStrategy` with an `originator` so per-user fee
 *      tiers can differ from access roles
 * @dev `canSwap()` reflects only freeze/seize state; it does not encode direction access—use `getBuyAccess` /
 *      `getSellAccess` for that.
 * @custom:audit Pending
 */
abstract contract AdvancedPermissionsUsm is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IAdvancedPermissionsUsm
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant SWAP_FREEZER_ROLE = keccak256("SWAP_FREEZER_ROLE");

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant BUY_SWAPPER_ROLE = keccak256("BUY_SWAPPER_ROLE");

    /// @inheritdoc IAdvancedPermissionsUsm
    bytes32 public constant SELL_SWAPPER_ROLE = keccak256("SELL_SWAPPER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable STABLE_TOKEN;

    /// @inheritdoc IAdvancedPermissionsUsm
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable UNDERLYING_ASSET;

    /// @inheritdoc IAdvancedPermissionsUsm
    address public priceStrategy;

    address internal _stableTokenTreasury;
    address internal _feeStrategy;
    bool internal _isFrozen;
    bool internal _isSeized;
    uint128 internal _exposureCap;
    uint128 internal _currentExposure;
    uint128 internal _accruedFees;
    DirectionAccess internal _buyDirectionAccess;
    DirectionAccess internal _sellDirectionAccess;
    address internal _feeRecipient;

    /// upgrade gap
    uint256[44] private __gap_usm;

    /**
     * @dev Require USM to not be frozen for functions marked by this modifier
     */
    modifier notFrozen() {
        require(!_isFrozen, "USM_FROZEN");
        _;
    }

    /**
     * @dev Require USM to not be seized for functions marked by this modifier
     */
    modifier notSeized() {
        require(!_isSeized, "USM_SEIZED");
        _;
    }

    /**
     * @dev Require caller to have buy access to the USM
     * For PERMISSIONED: the caller must have the BUY_SWAPPER_ROLE
     * For PERMISSIONLESS: the caller can be any address
     * @param caller The address of the caller
     */
    modifier canBuyAsset(address caller) {
        if (_buyDirectionAccess == DirectionAccess.PERMISSIONED) {
            require(hasRole(BUY_SWAPPER_ROLE, caller), "NOT PERMISSIONED");
        }
        _;
    }

    /**
     * @dev Require caller to have sell access to the USM
     * For PERMISSIONED: the caller must have the SELL_SWAPPER_ROLE
     * For PERMISSIONLESS: the caller can be any address
     * @param caller The address of the caller
     */
    modifier canSellAsset(address caller) {
        if (_sellDirectionAccess == DirectionAccess.PERMISSIONED) {
            require(hasRole(SELL_SWAPPER_ROLE, caller), "NOT PERMISSIONED");
        }
        _;
    }

    /**
     * @dev Constructor
     * @param stableToken The address of the stable token contract
     * @param underlyingAsset The address of the collateral asset
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address stableToken, address underlyingAsset) {
        require(stableToken != address(0), "ZERO_ADDRESS_NOT_VALID");
        require(underlyingAsset != address(0), "ZERO_ADDRESS_NOT_VALID");
        STABLE_TOKEN = stableToken;
        UNDERLYING_ASSET = underlyingAsset;
    }

    /**
     * @notice AdvancedPermissionsUsm initializer
     * @param admin The address of the default admin role
     * @param stableTokenTreasury The address of the stable token treasury
     * @param exposureCap Maximum amount of user-supplied underlying asset in USM
     * @param priceStrategy The address of the price strategy
     * @param buyAccess The buy direction access of the USM
     * @param sellAccess The sell direction access of the USM
     */
    function __AdvancedPermissionsUsm_init(
        address admin,
        address stableTokenTreasury,
        uint128 exposureCap,
        address priceStrategy,
        DirectionAccess buyAccess,
        DirectionAccess sellAccess
    ) internal onlyInitializing {
        require(admin != address(0), "ZERO_ADDRESS_NOT_VALID");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIGURATOR_ROLE, admin);
        _updateStableTokenTreasury(stableTokenTreasury);
        _updateExposureCap(exposureCap);
        _updatePriceStrategy(priceStrategy);
        _updateAccessConfig(buyAccess, sellAccess);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function buyAsset(uint256 minAmount, address receiver)
        external
        notFrozen
        notSeized
        canBuyAsset(msg.sender)
        returns (uint256, uint256)
    {
        return _buyAsset(msg.sender, minAmount, receiver);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function sellAsset(uint256 maxAmount, address receiver)
        external
        notFrozen
        notSeized
        canSellAsset(msg.sender)
        returns (uint256, uint256)
    {
        return _sellAsset(msg.sender, maxAmount, receiver);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(TOKEN_RESCUER_ROLE) {
        require(amount > 0, "INVALID_AMOUNT");
        if (token == STABLE_TOKEN) {
            uint256 rescuableBalance = IERC20(token).balanceOf(address(this)) - _accruedFees;
            require(rescuableBalance >= amount, "INSUFFICIENT_STABLE_TOKEN_TO_RESCUE");
        }
        if (token == UNDERLYING_ASSET) {
            uint256 rescuableBalance = IERC20(token).balanceOf(address(this)) - _currentExposure;
            require(rescuableBalance >= amount, "INSUFFICIENT_EXOGENOUS_ASSET_TO_RESCUE");
        }
        IERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function setSwapFreeze(bool enable) external onlyRole(SWAP_FREEZER_ROLE) {
        if (enable) {
            require(!_isFrozen, "USM_ALREADY_FROZEN");
        } else {
            require(_isFrozen, "USM_ALREADY_UNFROZEN");
        }
        _isFrozen = enable;
        emit SwapFreeze(msg.sender, enable);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function seize() external notSeized onlyRole(LIQUIDATOR_ROLE) returns (uint256) {
        distributeFeesToFeeRecipient();
        _isSeized = true;
        _currentExposure = 0;
        _accruedFees = 0;
        _updateExposureCap(0);

        uint256 stableTokenMinted = _getCurrentlyMintedStableTokenByUsm();
        uint256 underlyingBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(UNDERLYING_ASSET).safeTransfer(_stableTokenTreasury, underlyingBalance);
        }

        emit Seized(msg.sender, _stableTokenTreasury, underlyingBalance, stableTokenMinted);
        return underlyingBalance;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function burnAfterSeize(uint256 amount) external onlyRole(LIQUIDATOR_ROLE) returns (uint256) {
        require(_isSeized, "USM_NOT_SEIZED");
        require(amount > 0, "INVALID_AMOUNT");

        uint256 stableTokenMinted = _getCurrentlyMintedStableTokenByUsm();
        if (amount > stableTokenMinted) {
            amount = stableTokenMinted;
        }
        IERC20(STABLE_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
        _burnStableToken(address(this), amount);

        emit BurnAfterSeize(msg.sender, amount, (stableTokenMinted - amount));
        return amount;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updateFeeStrategy(address feeStrategy) external onlyRole(CONFIGURATOR_ROLE) {
        _updateFeeStrategy(feeStrategy);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updatePriceStrategy(address priceStrategy) external onlyRole(CONFIGURATOR_ROLE) {
        _updatePriceStrategy(priceStrategy);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updateExposureCap(uint128 exposureCap) external onlyRole(CONFIGURATOR_ROLE) {
        _updateExposureCap(exposureCap);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updateBuyAccess(DirectionAccess buyAccess) external onlyRole(CONFIGURATOR_ROLE) {
        require(buyAccess != _buyDirectionAccess, "SAME_ACCESS");
        _updateAccessConfig(buyAccess, _sellDirectionAccess);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updateSellAccess(DirectionAccess sellAccess) external onlyRole(CONFIGURATOR_ROLE) {
        require(sellAccess != _sellDirectionAccess, "SAME_ACCESS");
        _updateAccessConfig(_buyDirectionAccess, sellAccess);
    }

    /// @inheritdoc IStableTokenFacilitator
    function distributeFeesToFeeRecipient() public virtual override {
        uint256 accruedFees = _accruedFees;
        if (accruedFees > 0 && _feeRecipient != address(0)) {
            _accruedFees = 0;
            IERC20(STABLE_TOKEN).safeTransfer(_feeRecipient, accruedFees);
            emit FeesDistributedToFeeRecipient(_feeRecipient, STABLE_TOKEN, accruedFees);
        }
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function updateStableTokenTreasury(address newStableTokenTreasury) external override onlyRole(CONFIGURATOR_ROLE) {
        _updateStableTokenTreasury(newStableTokenTreasury);
    }

    /// @inheritdoc IStableTokenFacilitator
    function updateFeeRecipient(address newFeeRecipient) external override onlyRole(CONFIGURATOR_ROLE) {
        _updateFeeRecipient(newFeeRecipient);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getStableTokenAmountForBuyAsset(uint256 minAssetAmount, address originator)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return _calculateStableTokenAmountForBuyAsset(minAssetAmount, originator);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getStableTokenAmountForSellAsset(uint256 maxAssetAmount, address originator)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return _calculateStableTokenAmountForSellAsset(maxAssetAmount, originator);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getAssetAmountForBuyAsset(uint256 maxStableTokenAmount, address originator)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        uint256 grossAmount = withFee
            ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy)
                .getGrossAmountFromTotalBought(maxStableTokenAmount, originator)
            : maxStableTokenAmount;
        // round down so maxStableTokenAmount is guaranteed
        uint256 assetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(grossAmount, false);
        uint256 finalGrossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, true);
        uint256 finalFee =
            withFee ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy).getBuyFee(finalGrossAmount, originator) : 0;
        return (assetAmount, finalGrossAmount + finalFee, finalGrossAmount, finalFee);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getAssetAmountForSellAsset(uint256 minStableTokenAmount, address originator)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        uint256 grossAmount = withFee
            ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy)
                .getGrossAmountFromTotalSold(minStableTokenAmount, originator)
            : minStableTokenAmount;
        // round up so minStableTokenAmount is guaranteed
        uint256 assetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(grossAmount, true);
        uint256 finalGrossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, false);
        uint256 finalFee =
            withFee ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy).getSellFee(finalGrossAmount, originator) : 0;
        return (assetAmount, finalGrossAmount - finalFee, finalGrossAmount, finalFee);
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getAvailableUnderlyingExposure() external view returns (uint256) {
        return _exposureCap > _currentExposure ? _exposureCap - _currentExposure : 0;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getExposureCap() external view returns (uint128) {
        return _exposureCap;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getAvailableLiquidity() external view returns (uint256) {
        return _currentExposure;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getFeeStrategy() external view returns (address) {
        return _feeStrategy;
    }

    /// @inheritdoc IStableTokenFacilitator
    function getFeeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getAccruedFees() external view returns (uint256) {
        return _accruedFees;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getIsFrozen() external view returns (bool) {
        return _isFrozen;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getIsSeized() external view returns (bool) {
        return _isSeized;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function canSwap() external view returns (bool) {
        return !_isFrozen && !_isSeized;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getBuyAccess() external view returns (DirectionAccess) {
        return _buyDirectionAccess;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getSellAccess() external view returns (DirectionAccess) {
        return _sellDirectionAccess;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function getStableTokenTreasury() external view override returns (address) {
        return _stableTokenTreasury;
    }

    /// @inheritdoc IAdvancedPermissionsUsm
    function USM_REVISION() public pure virtual override returns (uint256) {
        return 1;
    }

    /**
     * @dev Buys an underlying asset with Stable Token
     * @param originator The originator of the request
     * @param minAmount The minimum amount of the underlying asset desired for purchase
     * @param receiver The recipient address of the underlying asset being purchased
     * @return The amount of underlying asset bought
     * @return The amount of Stable Token sold by the user
     */
    function _buyAsset(address originator, uint256 minAmount, address receiver) internal returns (uint256, uint256) {
        (uint256 assetAmount, uint256 stableTokenSold, uint256 grossAmount, uint256 fee) =
            _calculateStableTokenAmountForBuyAsset(minAmount, originator);

        _beforeBuyAsset(originator, assetAmount, receiver);

        require(assetAmount > 0, "INVALID_AMOUNT");
        require(assetAmount >= minAmount, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(_currentExposure >= assetAmount, "INSUFFICIENT_AVAILABLE_EXOGENOUS_ASSET_LIQUIDITY");

        _currentExposure -= uint128(assetAmount);
        _accruedFees += fee.toUint128();
        IERC20(STABLE_TOKEN).safeTransferFrom(originator, address(this), stableTokenSold);
        _burnStableToken(address(this), grossAmount);
        IERC20(UNDERLYING_ASSET).safeTransfer(receiver, assetAmount);

        emit BuyAsset(originator, receiver, assetAmount, stableTokenSold, fee);
        return (assetAmount, stableTokenSold);
    }

    /**
     * @dev Hook that is called before `buyAsset`.
     * @dev This can be used to add custom logic
     * @param originator Originator of the request
     * @param amount The amount of the underlying asset desired for purchase
     * @param receiver Recipient address of the underlying asset being purchased
     */
    function _beforeBuyAsset(address originator, uint256 amount, address receiver) internal virtual {}

    /**
     * @dev Sells an underlying asset for Stable Token
     * @param originator The originator of the request
     * @param maxAmount The maximum amount of the underlying asset desired to sell
     * @param receiver The recipient address of the Stable Token being purchased
     * @return The amount of underlying asset sold
     * @return The amount of Stable Token bought by the user
     */
    function _sellAsset(address originator, uint256 maxAmount, address receiver) internal returns (uint256, uint256) {
        (uint256 assetAmount, uint256 stableTokenBought, uint256 grossAmount, uint256 fee) =
            _calculateStableTokenAmountForSellAsset(maxAmount, originator);

        _beforeSellAsset(originator, assetAmount, receiver);

        require(assetAmount > 0, "INVALID_AMOUNT");
        require(_currentExposure + assetAmount <= _exposureCap, "EXOGENOUS_ASSET_EXPOSURE_TOO_HIGH");

        _currentExposure += uint128(assetAmount);
        _accruedFees += fee.toUint128();
        IERC20(UNDERLYING_ASSET).safeTransferFrom(originator, address(this), assetAmount);

        _mintStableToken(address(this), grossAmount);
        IERC20(STABLE_TOKEN).safeTransfer(receiver, stableTokenBought);

        emit SellAsset(originator, receiver, assetAmount, grossAmount, fee);
        return (assetAmount, stableTokenBought);
    }

    /**
     * @dev Hook that is called before `sellAsset`.
     * @dev This can be used to add custom logic
     * @param originator Originator of the request
     * @param amount The amount of the underlying asset desired to sell
     * @param receiver Recipient address of the Stable Token being purchased
     */
    function _beforeSellAsset(address originator, uint256 amount, address receiver) internal virtual {}

    /**
     * @dev Returns the amount of Stable Token sold in exchange of buying underlying asset
     * @param assetAmount The amount of underlying asset to buy
     * @param originator The originator of the request
     * @return The exact amount of asset the user purchases
     * @return The total amount of Stable Token the user sells (gross amount in Stable Token plus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied on top of gross amount of Stable Token
     */
    function _calculateStableTokenAmountForBuyAsset(uint256 assetAmount, address originator)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        // pick the highest Stable Token amount possible for given asset amount
        uint256 grossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, true);
        uint256 fee = withFee ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy).getBuyFee(grossAmount, originator) : 0;
        uint256 stableTokenSold = grossAmount + fee;
        uint256 finalGrossAmount = withFee
            ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy)
                .getGrossAmountFromTotalBought(stableTokenSold, originator)
            : stableTokenSold;
        // pick the lowest asset amount possible for given Stable Token amount
        uint256 finalAssetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(finalGrossAmount, false);
        uint256 finalFee = stableTokenSold - finalGrossAmount;
        return (finalAssetAmount, finalGrossAmount + finalFee, finalGrossAmount, finalFee);
    }

    /**
     * @dev Returns the amount of Stable Token bought in exchange of a given amount of underlying asset
     * @param assetAmount The amount of underlying asset to sell
     * @param originator The originator of the request
     * @return The exact amount of asset the user sells
     * @return The total amount of Stable Token the user buys (gross amount in Stable Token minus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied to the gross amount of Stable Token
     */
    function _calculateStableTokenAmountForSellAsset(uint256 assetAmount, address originator)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        // pick the lowest Stable Token amount possible for given asset amount
        uint256 grossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, false);
        uint256 fee = withFee ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy).getSellFee(grossAmount, originator) : 0;
        uint256 stableTokenBought = grossAmount - fee;
        uint256 finalGrossAmount = withFee
            ? IAdvancedPermissionsUsmFeeStrategy(_feeStrategy)
                .getGrossAmountFromTotalSold(stableTokenBought, originator)
            : stableTokenBought;
        // pick the highest asset amount possible for given Stable Token amount
        uint256 finalAssetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(finalGrossAmount, true);
        uint256 finalFee = finalGrossAmount - stableTokenBought;
        return (finalAssetAmount, finalGrossAmount - finalFee, finalGrossAmount, finalFee);
    }

    /**
     * @dev Updates Price Strategy
     * @param newPriceStrategy The address of the new Price Strategy
     */
    function _updatePriceStrategy(address newPriceStrategy) internal {
        require(IUsmPriceStrategy(newPriceStrategy).UNDERLYING_ASSET() == UNDERLYING_ASSET, "INVALID_PRICE_STRATEGY");
        address oldPriceStrategy = priceStrategy;
        priceStrategy = newPriceStrategy;
        emit PriceStrategyUpdated(oldPriceStrategy, newPriceStrategy);
    }

    /**
     * @dev Updates Fee Strategy
     * @param feeStrategy The address of the new Fee Strategy
     */
    function _updateFeeStrategy(address feeStrategy) internal {
        // Setting fee strategy to non-zero should be possible only if fee recipient is non-zero as well
        if (feeStrategy != address(0)) {
            require(_feeRecipient != address(0), "FEE_STRATEGY_REQUIRES_FEE_RECIPIENT");
        }
        address oldFeeStrategy = _feeStrategy;
        _feeStrategy = feeStrategy;
        emit FeeStrategyUpdated(oldFeeStrategy, feeStrategy);
    }

    /**
     * @dev Updates Exposure Cap
     * @param exposureCap The value of the new Exposure Cap
     */
    function _updateExposureCap(uint128 exposureCap) internal {
        uint128 oldExposureCap = _exposureCap;
        _exposureCap = exposureCap;
        emit ExposureCapUpdated(oldExposureCap, exposureCap);
    }

    /**
     * @dev Updates Access Configuration for both directions
     * @param buyAccess The new buy direction access
     * @param sellAccess The new sell direction access
     */
    function _updateAccessConfig(DirectionAccess buyAccess, DirectionAccess sellAccess) internal {
        _buyDirectionAccess = buyAccess;
        _sellDirectionAccess = sellAccess;
        emit AccessConfigUpdated(buyAccess, sellAccess);
    }

    /**
     * @dev Updates Stable Token Treasury Address
     * @param newStableTokenTreasury The address of the new Stable Token Treasury
     */
    function _updateStableTokenTreasury(address newStableTokenTreasury) internal {
        require(newStableTokenTreasury != address(0), "ZERO_ADDRESS_NOT_VALID");
        address oldStableTokenTreasury = _stableTokenTreasury;
        _stableTokenTreasury = newStableTokenTreasury;
        emit StableTokenTreasuryUpdated(oldStableTokenTreasury, newStableTokenTreasury);
    }

    /**
     * @dev Updates Fee Recipient Address
     * @param newFeeRecipient The address of the new Fee Recipient
     */
    function _updateFeeRecipient(address newFeeRecipient) internal {
        // Setting fee recipient to 0 should be possible only if fee strategy is 0 as well
        if (newFeeRecipient == address(0)) {
            require(_feeStrategy == address(0), "FEE_RECIPIENT_CANNOT_BE_ZERO_WITH_FEE_STRATEGY");
        }
        address oldFeeRecipient = _feeRecipient;
        _feeRecipient = newFeeRecipient;
        emit StableTokenFeeRecipientUpdated(oldFeeRecipient, newFeeRecipient);
    }

    /**
     * @dev Returns the amount of Stable Token minted by the USM
     * @return The amount of Stable Token minted by the USM
     */
    function _getCurrentlyMintedStableTokenByUsm() internal view virtual returns (uint256);

    /**
     * @dev Mints Stable Token
     * @param to The address to mint the Stable Token to
     * @param amount The amount of Stable Token to mint
     */
    function _mintStableToken(address to, uint256 amount) internal virtual;

    /**
     * @dev Burns Stable Token
     * @param from The address to burn the Stable Token from
     * @param amount The amount of Stable Token to burn
     */
    function _burnStableToken(address from, uint256 amount) internal virtual;

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
