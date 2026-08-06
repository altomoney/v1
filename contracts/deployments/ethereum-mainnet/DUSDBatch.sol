// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DUSD} from "@alto/tokens/DUSD.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

struct DUSDBatchParams {
    address timelock;
    address lzEndpoint;
    address treasury;
    FlashFee flashFee;
    address deployer;
    address freezer;
    uint256 flashMintCeiling;
}

struct DUSDBatchReport {
    address dusd;
    address dusdFlashMinter;
}

/// @notice Deploys DUSD and DUSDFlashMinter in a single transaction
contract DUSDBatch {
    DUSDBatchReport public report;

    constructor(DUSDBatchParams memory _params) {
        // Deploy DUSD with batch contract as owner temporarily to allow configuration
        // owner will be transferred to _params.deployer after configuration
        address dusd = address(new DUSD(_params.lzEndpoint, address(this)));

        // Set freezer as pauser
        DUSD(dusd).setPauser(_params.freezer, PAUSE_TYPE, true);
        DUSD(dusd).setPauser(address(this), PAUSE_TYPE, false);

        // Deploy DUSDFlashMinter
        address dusdFlashMinter =
            address(new DUSDFlashMinter(dusd, _params.treasury, _params.flashFee, _params.timelock));

        // Configure DUSD minter permissions for flash minter (requires ownership)
        IDUSD(dusd).setMinterStatus(dusdFlashMinter, true);
        IDUSD(dusd).setMinterCeiling(dusdFlashMinter, _params.flashMintCeiling);
        IDUSD(dusd).setBurnerStatus(dusdFlashMinter, true);

        // Transfer DUSD ownership to deployer (will be transferred to timelock in POST phase)
        AltoOwnable2Step(dusd).transferOwnershipSkip2Step(_params.deployer);

        report = DUSDBatchReport({dusd: dusd, dusdFlashMinter: dusdFlashMinter});
    }

    function getReport() public view returns (DUSDBatchReport memory) {
        return report;
    }
}

