// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AltoMulticallTestnet {
    mapping(address => bool) public _owners;

    constructor(address[] memory owners) {
        for (uint256 i = 0; i < owners.length; i++) {
            _owners[owners[i]] = true;
        }
    }

    struct Call {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct CallValue {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function multicall(Call[] calldata calls) public payable onlyOwner returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call memory calli;
        for (uint256 i; i < length;) {
            Result memory result = returnData[i];
            calli = calls[i];

            require(calli.target.code.length > 0, "Multicall: no contract");
            (result.success, result.returnData) = calli.target.call(calli.callData);
            if (!result.success) {
                _getRevertMsg(calli.target, result.returnData);
            }
            unchecked {
                ++i;
            }
        }
    }

    function performDelegateCall(address target, bytes memory data)
        public
        payable
        onlyOwner
        returns (bytes memory returnData)
    {
        (bool success, bytes memory result) = target.delegatecall(data);
        if (!success) {
            _getRevertMsg(target, result);
        }
        return result;
    }

    function multicallValue(CallValue[] calldata calls) public payable onlyOwner returns (Result[] memory returnData) {
        uint256 valAccumulator;
        uint256 length = calls.length;
        returnData = new Result[](length);
        CallValue memory calli;
        for (uint256 i; i < length;) {
            Result memory result = returnData[i];
            calli = calls[i];
            uint256 val = calli.value;
            // Humanity will be a Type V Kardashev Civilization before this overflows - andreas
            // ~ 10^25 Wei in existence << ~ 10^76 size uint fits in a uint256
            unchecked {
                valAccumulator += val;
            }
            (result.success, result.returnData) = calli.target.call{value: val}(calli.callData);
            if (!result.success) {
                _getRevertMsg(calli.target, result.returnData);
            }
            unchecked {
                ++i;
            }
        }
        // Finally, make sure the msg.value = SUM(call[0...i].value)
        require(msg.value == valAccumulator, "Multicall3: value mismatch");
    }

    function _getRevertMsg(address _target, bytes memory _returnData) private pure {
        // If the _res length is less than 68, then
        // the transaction failed with custom error or silently (without a revert message)
        // Comment this because of custom errors
        // if (_returnData.length < 68) revert("Reason unknown");

        bytes memory _withoutSelector;
        assembly {
            // Slice the sighash.
            _withoutSelector := add(_returnData, 0x04)
        }
        revert(
            abi.decode(
                abi.encode(_target, abi.decode(_withoutSelector, (string)), " Return data: ", _returnData), (string)
            )
        ); // All that remains is the revert string
    }

    function transferERC20(address token, address to, uint256 amount) public payable onlyOwner {
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(token).transfer(to, amount);
    }

    function transferNative(address to, uint256 amount) public payable onlyOwner {
        payable(to).transfer(amount);
    }

    function approveERC20(address token, address spender, uint256 amount) public payable onlyOwner {
        IERC20(token).approve(spender, amount);
    }

    receive() external payable {}

    function setOwner(address owner, bool status) public onlyOwner {
        _owners[owner] = status;
    }

    function isOwner(address owner) public view returns (bool) {
        return _owners[owner];
    }

    modifier onlyOwner() {
        require(_owners[msg.sender], "Not an owner");
        _;
    }
}
