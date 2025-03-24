// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ITapiocaOracle} from "src/tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestnetOracle is ITapiocaOracle, Ownable {
    uint256 public rate;
    bool public success;
    string public __name;
    string public __symbol;
    uint8 public __decimals;

    constructor(string memory _name, string memory _symbol, uint256 _rate, address owner, uint256 _decimals) {
        success = true;
        rate = _rate;
        __name = _name;
        __symbol = _symbol;
        __decimals = uint8(_decimals);
        _transferOwnership(owner);
    }

    function decimals() external view override returns (uint8) {
        return __decimals;
    }

    function set(uint256 rate_) public onlyOwner {
        // The rate can be updated.
        rate = rate_;
    }

    function setSuccess(bool val) public onlyOwner {
        success = val;
    }

    function getDataParameter() public pure returns (bytes memory) {
        return abi.encode("0x0");
    }

    // Get the latest exchange rate
    function get(bytes calldata) public view returns (bool, uint256) {
        return (success, rate);
    }

    // Check the last exchange rate without any state changes
    function peek(bytes calldata) public view returns (bool, uint256) {
        return (success, rate);
    }

    function peekSpot(bytes calldata) public view returns (uint256) {
        return rate;
    }

    function name(bytes calldata) public view returns (string memory) {
        return __name;
    }

    function symbol(bytes calldata) public view returns (string memory) {
        return __symbol;
    }
}
