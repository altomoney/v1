// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoLeverageSwapperMultiTarget} from "@alto/lending/leverage/AltoLeverageSwapperMultiTarget.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

struct LeverageSwapperMultiTargetBatchParams {
    address owner;
    address[] leverageContracts;
    address[] validSwapTargets;
}

/// @notice Deploys one AltoLeverageSwapperMultiTarget per leverage contract in a single transaction
contract LeverageSwapperMultiTargetBatch {
    address[] internal _swappers;

    constructor(LeverageSwapperMultiTargetBatchParams memory _params) {
        uint256 count = _params.leverageContracts.length;
        require(count > 0, "No leverage contracts");
        require(_params.validSwapTargets.length > 0, "No valid swap targets");

        _swappers = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            address leverage = _params.leverageContracts[i];
            require(leverage != address(0), "Invalid leverage contract");

            address swapper =
                address(new AltoLeverageSwapperMultiTarget(address(this), _params.validSwapTargets));

            AltoLeverageSwapperMultiTarget(swapper).setWhitelisted(leverage, true);

            Ownable(swapper).transferOwnership(_params.owner);

            _swappers[i] = swapper;
        }
    }

    function getSwappers() external view returns (address[] memory) {
        return _swappers;
    }
}
