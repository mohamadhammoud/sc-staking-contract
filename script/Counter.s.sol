// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {FixedStakingPool} from "../src/FixedStakingPool.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract FixedStakingPoolScript is Script {
    FixedStakingPool public pool;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    // Deployment configuration
    uint256 public constant FIXED_APR = 10; // 10% APR
    uint256 public INTEREST_START_TIME = block.timestamp + 1 days; // Start in 1 day
    uint256 public POOL_END_TIME = block.timestamp + 30 days; // End in 30 days
    uint256 public constant LOCKIN_PERIOD = 7 days; // 7 days lock-in
    uint256 public constant MAX_POOL_SIZE = 500_000 ether; // 500,000 tokens max staking pool size

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy mock tokens
        stakingToken = new MockERC20("StakingToken", "STK");
        rewardToken = new MockERC20("RewardToken", "RWD");

        console.log("Deployed Staking Token (STK) at:", address(stakingToken));
        console.log("Deployed Reward Token (RWD) at:", address(rewardToken));

        // Deploy the staking pool contract
        pool = new FixedStakingPool(
            address(stakingToken),
            address(rewardToken),
            FIXED_APR,
            INTEREST_START_TIME,
            POOL_END_TIME,
            LOCKIN_PERIOD,
            MAX_POOL_SIZE,
            msg.sender // Owner of the contract
        );

        console.log("Deployed FixedStakingPool at:", address(pool));

        vm.stopBroadcast();
    }
}
