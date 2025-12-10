// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IStableTokenFacilitator} from "./interfaces/IStableTokenFacilitator.sol";
import {IUsmPriceStrategy} from "./interfaces/IUsmPriceStrategy.sol";
import {IUsmFeeStrategy} from "./interfaces/IUsmFeeStrategy.sol";
import {IUsm, AccessMode} from "./interfaces/IUsm.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Usm
 * @author Pearl Labs
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Universal Stability Module. It provides buy/sell facilities to go to/from an underlying asset to/from stability token.
 * @dev To be covered by a proxy contract.
 */
abstract contract Usm is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IUsm {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @inheritdoc IUsm
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @inheritdoc IUsm
    bytes32 public constant TOKEN_RESCUER_ROLE = keccak256("TOKEN_RESCUER_ROLE");

    /// @inheritdoc IUsm
    bytes32 public constant SWAP_FREEZER_ROLE = keccak256("SWAP_FREEZER_ROLE");

    /// @inheritdoc IUsm
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @inheritdoc IUsm
    bytes32 public constant SWAPPER_ROLE = keccak256("SWAPPER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable STABLE_TOKEN;

    /// @inheritdoc IUsm
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable UNDERLYING_ASSET;

    /// @inheritdoc IUsm
    address public priceStrategy;

    address internal _stableTokenTreasury;
    address internal _feeStrategy;
    bool internal _isFrozen;
    bool internal _isSeized;
    uint128 internal _exposureCap;
    uint128 internal _currentExposure;
    uint128 internal _accruedFees;
    AccessMode internal _accessMode;
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
     * @dev Require caller to have access to the USM for
     * For Permissioned USMs, the caller must have the SWAPPER_ROLE
     * For Permissionless USMs, the caller can be any address
     * @param caller The address of the caller
     */
    modifier hasAccess(address caller) {
        if (_accessMode == AccessMode.PERMISSIONED) {
            require(hasRole(SWAPPER_ROLE, caller), "NOT PERMISSIONED");
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
     * @notice USM initializer
     * @param admin The address of the default admin role
     * @param stableTokenTreasury The address of the stable token treasury
     * @param exposureCap Maximum amount of user-supplied underlying asset in USM
     * @param priceStrategy The address of the price strategy
     * @param accessMode The access mode of the USM
     */
    function __Usm_init(
        address admin,
        address stableTokenTreasury,
        uint128 exposureCap,
        address priceStrategy,
        AccessMode accessMode
    ) internal onlyInitializing {
        require(admin != address(0), "ZERO_ADDRESS_NOT_VALID");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIGURATOR_ROLE, admin);
        _updateStableTokenTreasury(stableTokenTreasury);
        _updateExposureCap(exposureCap);
        _updatePriceStrategy(priceStrategy);
        _updateAccessMode(accessMode);
    }

    /// @inheritdoc IUsm
    function buyAsset(uint256 minAmount, address receiver)
        external
        notFrozen
        notSeized
        hasAccess(msg.sender)
        returns (uint256, uint256)
    {
        return _buyAsset(msg.sender, minAmount, receiver);
    }

    /// @inheritdoc IUsm
    function sellAsset(uint256 maxAmount, address receiver)
        external
        notFrozen
        notSeized
        hasAccess(msg.sender)
        returns (uint256, uint256)
    {
        return _sellAsset(msg.sender, maxAmount, receiver);
    }

    /// @inheritdoc IUsm
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

    /// @inheritdoc IUsm
    function setSwapFreeze(bool enable) external onlyRole(SWAP_FREEZER_ROLE) {
        if (enable) {
            require(!_isFrozen, "USM_ALREADY_FROZEN");
        } else {
            require(_isFrozen, "USM_ALREADY_UNFROZEN");
        }
        _isFrozen = enable;
        emit SwapFreeze(msg.sender, enable);
    }

    /// @inheritdoc IUsm
    function seize() external notSeized onlyRole(LIQUIDATOR_ROLE) returns (uint256) {
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

    /// @inheritdoc IUsm
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

    /// @inheritdoc IUsm
    function updateFeeStrategy(address feeStrategy) external onlyRole(CONFIGURATOR_ROLE) {
        _updateFeeStrategy(feeStrategy);
    }

    /// @inheritdoc IUsm
    function updatePriceStrategy(address priceStrategy) external onlyRole(CONFIGURATOR_ROLE) {
        _updatePriceStrategy(priceStrategy);
    }

    /// @inheritdoc IUsm
    function updateExposureCap(uint128 exposureCap) external onlyRole(CONFIGURATOR_ROLE) {
        _updateExposureCap(exposureCap);
    }

    /// @inheritdoc IUsm
    function updateAccessMode(AccessMode accessMode) external onlyRole(CONFIGURATOR_ROLE) {
        _updateAccessMode(accessMode);
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

    /// @inheritdoc IUsm
    function updateStableTokenTreasury(address newStableTokenTreasury) external override onlyRole(CONFIGURATOR_ROLE) {
        _updateStableTokenTreasury(newStableTokenTreasury);
    }

    /// @inheritdoc IStableTokenFacilitator
    function updateFeeRecipient(address newFeeRecipient) external override onlyRole(CONFIGURATOR_ROLE) {
        _updateFeeRecipient(newFeeRecipient);
    }

    /// @inheritdoc IUsm
    function getStableTokenAmountForBuyAsset(uint256 minAssetAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return _calculateStableTokenAmountForBuyAsset(minAssetAmount);
    }

    /// @inheritdoc IUsm
    function getStableTokenAmountForSellAsset(uint256 maxAssetAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return _calculateStableTokenAmountForSellAsset(maxAssetAmount);
    }

    /// @inheritdoc IUsm
    function getAssetAmountForBuyAsset(uint256 maxStableTokenAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        uint256 grossAmount = withFee
            ? IUsmFeeStrategy(_feeStrategy).getGrossAmountFromTotalBought(maxStableTokenAmount)
            : maxStableTokenAmount;
        // round down so maxStableTokenAmount is guaranteed
        uint256 assetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(grossAmount, false);
        uint256 finalGrossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, true);
        uint256 finalFee = withFee ? IUsmFeeStrategy(_feeStrategy).getBuyFee(finalGrossAmount) : 0;
        return (assetAmount, finalGrossAmount + finalFee, finalGrossAmount, finalFee);
    }

    /// @inheritdoc IUsm
    function getAssetAmountForSellAsset(uint256 minStableTokenAmount)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        uint256 grossAmount = withFee
            ? IUsmFeeStrategy(_feeStrategy).getGrossAmountFromTotalSold(minStableTokenAmount)
            : minStableTokenAmount;
        // round up so minStableTokenAmount is guaranteed
        uint256 assetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(grossAmount, true);
        uint256 finalGrossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, false);
        uint256 finalFee = withFee ? IUsmFeeStrategy(_feeStrategy).getSellFee(finalGrossAmount) : 0;
        return (assetAmount, finalGrossAmount - finalFee, finalGrossAmount, finalFee);
    }

    /// @inheritdoc IUsm
    function getAvailableUnderlyingExposure() external view returns (uint256) {
        return _exposureCap > _currentExposure ? _exposureCap - _currentExposure : 0;
    }

    /// @inheritdoc IUsm
    function getExposureCap() external view returns (uint128) {
        return _exposureCap;
    }

    /// @inheritdoc IUsm
    function getAvailableLiquidity() external view returns (uint256) {
        return _currentExposure;
    }

    /// @inheritdoc IUsm
    function getFeeStrategy() external view returns (address) {
        return _feeStrategy;
    }

    /// @inheritdoc IStableTokenFacilitator
    function getFeeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    /// @inheritdoc IUsm
    function getAccruedFees() external view returns (uint256) {
        return _accruedFees;
    }

    /// @inheritdoc IUsm
    function getIsFrozen() external view returns (bool) {
        return _isFrozen;
    }

    /// @inheritdoc IUsm
    function getIsSeized() external view returns (bool) {
        return _isSeized;
    }

    /// @inheritdoc IUsm
    function canSwap() external view returns (bool) {
        return !_isFrozen && !_isSeized;
    }

    /// @inheritdoc IUsm
    function getAccessMode() external view returns (AccessMode) {
        return _accessMode;
    }

    /// @inheritdoc IUsm
    function getStableTokenTreasury() external view override returns (address) {
        return _stableTokenTreasury;
    }

    /// @inheritdoc IUsm
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
            _calculateStableTokenAmountForBuyAsset(minAmount);

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
            _calculateStableTokenAmountForSellAsset(maxAmount);

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
     * @return The exact amount of asset the user purchases
     * @return The total amount of Stable Token the user sells (gross amount in Stable Token plus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied on top of gross amount of Stable Token
     */
    function _calculateStableTokenAmountForBuyAsset(uint256 assetAmount)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        // pick the highest Stable Token amount possible for given asset amount
        uint256 grossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, true);
        uint256 fee = withFee ? IUsmFeeStrategy(_feeStrategy).getBuyFee(grossAmount) : 0;
        uint256 stableTokenSold = grossAmount + fee;
        uint256 finalGrossAmount =
            withFee ? IUsmFeeStrategy(_feeStrategy).getGrossAmountFromTotalBought(stableTokenSold) : stableTokenSold;
        // pick the lowest asset amount possible for given Stable Token amount
        uint256 finalAssetAmount = IUsmPriceStrategy(priceStrategy).getStableTokenPriceInAsset(finalGrossAmount, false);
        uint256 finalFee = stableTokenSold - finalGrossAmount;
        return (finalAssetAmount, finalGrossAmount + finalFee, finalGrossAmount, finalFee);
    }

    /**
     * @dev Returns the amount of Stable Token bought in exchange of a given amount of underlying asset
     * @param assetAmount The amount of underlying asset to sell
     * @return The exact amount of asset the user sells
     * @return The total amount of Stable Token the user buys (gross amount in Stable Token minus fee)
     * @return The gross amount of Stable Token
     * @return The fee amount in Stable Token, applied to the gross amount of Stable Token
     */
    function _calculateStableTokenAmountForSellAsset(uint256 assetAmount)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        bool withFee = _feeStrategy != address(0);
        // pick the lowest Stable Token amount possible for given asset amount
        uint256 grossAmount = IUsmPriceStrategy(priceStrategy).getAssetPriceInStableToken(assetAmount, false);
        uint256 fee = withFee ? IUsmFeeStrategy(_feeStrategy).getSellFee(grossAmount) : 0;
        uint256 stableTokenBought = grossAmount - fee;
        uint256 finalGrossAmount =
            withFee ? IUsmFeeStrategy(_feeStrategy).getGrossAmountFromTotalSold(stableTokenBought) : stableTokenBought;
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
     * @dev Updates Access Mode
     * @param accessMode The new access mode
     */
    function _updateAccessMode(AccessMode accessMode) internal {
        _accessMode = accessMode;
        emit AccessModeUpdated(accessMode);
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
