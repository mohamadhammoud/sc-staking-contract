// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "../src/FixedStakingPool.sol";
import "../src/MockERC20.sol";

/**
 * @title DeployFixedStakingPool
 * @notice Script to deploy the FixedStakingPool contract along with mock staking and reward tokens.
 */
contract DeployFixedStakingPool is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Mock Tokens
        MockERC20 stakingToken = new MockERC20("StakingToken", "STK");
        MockERC20 rewardToken = new MockERC20("RewardToken", "RWD");

        // Initialize FixedStakingPool parameters
        uint256 fixedAPR = 10; // 10% APR
        uint256 interestStartTime = block.timestamp + 1 days; // Interest starts tomorrow
        uint256 poolEndTime = interestStartTime + 30 days; // Pool ends in 30 days
        uint256 maxPoolSize = 100_000 ether; // Maximum staking pool size
        address owner = msg.sender; // Assign the deployer as the owner

        // Deploy FixedStakingPool
        FixedStakingPool pool = new FixedStakingPool(
            IERC20(stakingToken),
            IERC20(rewardToken),
            fixedAPR,
            interestStartTime,
            poolEndTime,
            maxPoolSize,
            owner
        );

        // Log deployed contract addresses
        console.log("FixedStakingPool deployed at:", address(pool));
        console.log("Staking Token deployed at:", address(stakingToken));
        console.log("Reward Token deployed at:", address(rewardToken));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
