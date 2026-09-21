// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "erc4626-tests/ERC4626.test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";

/// @dev The generic properties run against SDUSD's durable post-seed state. Positive yield is introduced through
///      notifyRewardAmount instead of raw token minting because raw DUSD transfers are intentionally unaccounted.
contract SDUSDERC4626ComplianceTest is ERC4626Test {
    uint256 internal constant SEED_SHARES = 1 ether;
    uint256 internal constant REWARD_DURATION = 7 days;

    address internal constant PAUSER = address(0xFEEE);
    address internal constant SEED_DEPOSITOR = address(0x5EED);

    ERC20MockMintableDecimals internal dusd;
    SDUSD internal sdusd;

    function setUp() public override {
        dusd = new ERC20MockMintableDecimals("DUSD", "DUSD", 18);
        SDUSD implementation = new SDUSD();
        SDUSDInitParams memory params = SDUSDInitParams({
            admin: address(this),
            pauser: PAUSER,
            dusd: address(dusd),
            rewarder: address(this),
            seedShares: SEED_SHARES,
            depositCap: 115_000 ether,
            rewardDuration: REWARD_DURATION
        });
        sdusd = SDUSD(address(new ERC1967Proxy(address(implementation), abi.encodeCall(SDUSD.initialize, (params)))));
        dusd.mint(address(this), SEED_SHARES);
        dusd.approve(address(sdusd), SEED_SHARES);
        sdusd.deposit(SEED_SHARES, address(1));

        _underlying_ = address(dusd);
        _vault_ = address(sdusd);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }

    function setUpYield(Init memory init) public override {
        // sDUSD has no loss-reporting mechanism, and raw balance changes are intentionally excluded from its
        // accounting. Exercise positive yield through the real reward path, then let it fully unlock so the
        // generic ERC-4626 properties observe the requested realized yield.
        vm.assume(init.yield >= 0);

        uint256 gain = uint256(init.yield);
        if (gain == 0) return;

        // Rewards require shares held outside the permanent lock, including after additional deposits to it.
        vm.assume(sdusd.totalSupply() > sdusd.balanceOf(address(1)));

        // Keep the mock token mint within its arithmetic domain; all other reward-path failures should surface.
        vm.assume(gain <= type(uint256).max - dusd.totalSupply());

        dusd.mint(address(this), gain);
        dusd.approve(address(sdusd), gain);
        sdusd.notifyRewardAmount(gain);
        vm.warp(sdusd.rewardPeriodFinish());
    }
}
