// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {IERC4626} from "../../utils/interfaces/common/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {EIP712, ECDSA} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Tapioca
import {IPenrose} from "tap-utils/interfaces/bar/IPenrose.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
TODO Do we need IERC1155Receiver?
*/
abstract contract MarketERC4626 is IERC20Permit, ERC4626, IERC1155Receiver {
    bool private constant _IS_ASSET = true;
    bool private constant _IS_BORROW = false;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("PermitBorrow(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_BORROW =
        0xe9685ff6d48c617fe4f692c50e602cce27cbad0290beb93cfa77eac43968d58c;
    // keccak256("PermitCollateral(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_COLLATERAL =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("PermitLiquidity(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 private constant _PERMIT_TYPEHASH_LIQUIDITY =
        0x05ec39b1dbfea40ef9a702d0520c523a29ab686fe4626bd51466caaff3a1d483;

    /// @dev this represents the collateral token (or asset token in ERC4626)
    /// @dev This is used to override ERC4626 asset() function (it is abstract in ERC4626)
    address internal _collateral;

    string internal _name;

    string internal _symbol;

    /// @notice returns Penrose address
    IPenrose internal _penrose;

    /// @notice owner > spender > allowance liquidity mapping.
    mapping(address => mapping(address => uint256)) public allowanceLiquidity;
    /// @notice owner > spender > allowance collateral mapping.
    mapping(address => mapping(address => uint256)) public allowanceCollateral;
    /// @notice owner > spender > allowance collateral mapping.
    mapping(address => mapping(address => uint256)) public allowanceBorrow;

    /// @notice event emitted when borrow approval is performed
    event ApprovalBorrow(address indexed owner, address indexed spender, uint256 indexed value);
    /// @notice event emitted when liquidity approval is performed
    event ApprovalLiquidity(address indexed owner, address indexed spender, uint256 indexed value);
    /// @notice event emitted when collateral approval is performed
    event ApprovalCollateral(address indexed owner, address indexed spender, uint256 indexed value);

    error MarketERC4626__AlreadyInitialized();

    enum PermitActions {
        VAULT_ERC4626_TRANSFER,
        LIQUIDITY,
        COLLATERAL,
        BORROW
    }

    /// Check if msg.sender has right to execute borrow operations
    modifier allowedBorrow(address from, uint256 share) virtual {
        _allowedBorrow(from, share);
        _;
    }

    /// Check if msg.sender has right to execute collateral  operations
    modifier allowedCollateral(address from, uint256 amount) virtual {
        _allowedCollateral(from, amount);
        _;
    }

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     */
    constructor(string memory __name, string memory __symbol) {
        _name = __name;
        _symbol = __symbol;
    }

    function __initialize_MarketERC4626(address __collateral) internal {
        if (_collateral != address(0)) {
            revert MarketERC4626__AlreadyInitialized();
        }
        _collateral = __collateral;
    }

    function collateral() public view returns (address) {
        return _collateral;
    }

    function asset() public view override returns (address) {
        return _collateral;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function _constantNameHash() internal view override returns (bytes32 result) {
        result = keccak256(abi.encodePacked(_name));
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view override(ERC20, IERC20Permit) returns (bytes32) {
        return ERC20.DOMAIN_SEPARATOR();
    }

    function nonces(address owner) public view override(ERC20, IERC20Permit) returns (uint256) {
        return ERC20.nonces(owner);
    }

    function approveBorrow(address spender, uint256 amount) external returns (bool) {
        _approveBorrow(msg.sender, spender, amount);
        return true;
    }

    function approveLiquidity(address spender, uint256 amount) external returns (bool) {
        _approveLiquidity(msg.sender, spender, amount);
        return true;
    }

    function approveCollateral(address spender, uint256 amount) external returns (bool) {
        _approveCollateral(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20Permit-permit}.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override(ERC20, IERC20Permit)
    {
        _permit(PermitActions.VAULT_ERC4626_TRANSFER, owner, spender, value, deadline, v, r, s);
    }

    function permitAction(
        PermitActions action,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual {
        _permit(action, owner, spender, value, deadline, v, r, s);
    }

    /**
     * @notice Checks if the caller is allowed to lend `share` from `from`.
     */
    function _allowedLend(address from, uint256 share) internal virtual {}

    /**
     * @notice Checks if the caller is allowed to borrow `share` from `from`.
     */
    function _allowedBorrow(address from, uint256 share) internal virtual {}

    /// @notice Checks if the caller is allowed to add collateral `amount` from `from`.
    function _allowedCollateral(address from, uint256 amount) internal virtual {}

    function _permit(
        PermitActions action,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
        if (!_cluster().isWhitelisted(0, msg.sender)) {
            require(owner == msg.sender, "MarketERC4626: not authorized");
        }
        bytes32 actionId;
        if (action == PermitActions.VAULT_ERC4626_TRANSFER) {
            actionId = _PERMIT_TYPEHASH;
        } else if (action == PermitActions.LIQUIDITY) {
            actionId = _PERMIT_TYPEHASH_LIQUIDITY;
        } else if (action == PermitActions.COLLATERAL) {
            actionId = _PERMIT_TYPEHASH_COLLATERAL;
        } else if (action == PermitActions.BORROW) {
            actionId = _PERMIT_TYPEHASH_BORROW;
        }
        // TODO What if I use the same data for BigBang and Singularity?
        bytes32 structHash =
            keccak256(abi.encode(actionId, owner, spender, value, nonces(owner), deadline, block.chainid));
        _incrementNonce(owner);

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");

        if (action == PermitActions.VAULT_ERC4626_TRANSFER) {
            _approve(owner, spender, value);
        } else if (action == PermitActions.LIQUIDITY) {
            _approveLiquidity(owner, spender, value);
        } else if (action == PermitActions.COLLATERAL) {
            _approveCollateral(owner, spender, value);
        } else if (action == PermitActions.BORROW) {
            _approveBorrow(owner, spender, value);
        } else {
            revert("MarketERC4626: invalid permit action");
        }
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return ECDSA.toTypedDataHash(DOMAIN_SEPARATOR(), structHash);
    }

    function _approveBorrow(address owner, address spender, uint256 amount) internal {
        allowanceBorrow[owner][spender] = amount;
        emit ApprovalBorrow(owner, spender, amount);
    }

    function _approveLiquidity(address owner, address spender, uint256 amount) internal {
        allowanceLiquidity[owner][spender] = amount;
        emit ApprovalLiquidity(owner, spender, amount);
    }

    function _approveCollateral(address owner, address spender, uint256 amount) internal {
        allowanceCollateral[owner][spender] = amount;
        emit ApprovalCollateral(owner, spender, amount);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC4626).interfaceId
            || interfaceId == type(IERC20Permit).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function _cluster() internal view returns (ICluster) {
        return ICluster(_penrose.cluster());
    }

    function penrose() external view returns (address) {
        return address(_penrose);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }
}
