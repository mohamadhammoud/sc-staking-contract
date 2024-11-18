// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/FixedStakingPool.sol";
import "../src/MockERC20.sol";

contract FixedStakingPoolTest is Test {
    FixedStakingPool public pool;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    address user1 = address(0x1);
    address user2 = address(0x2);
    address owner = address(this);

    uint256 initialSupply = 1_000_000 ether;

    function setUp() public {
        stakingToken = new MockERC20("StakingToken", "STK");
        rewardToken = new MockERC20("RewardToken", "RWD");

        // transfer tokens for testing
        stakingToken.transfer(user1, 100_000 ether);
        stakingToken.transfer(user2, 50_000 ether);
        rewardToken.transfer(owner, 100_000 ether);

        // Deploy the staking pool contract
        pool = new FixedStakingPool(
            address(stakingToken),
            address(rewardToken),
            10, // Fixed APR = 10%
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            7 days, // Lock-in period
            500_000 ether, // Max pool size
            owner
        );

        rewardToken.approve(address(pool), 100_000 ether);
    }

    // ============ Tests for Staking ============

    function testStakeSuccess() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 10_000 ether);
        pool.stake(10_000 ether);
        vm.stopPrank();

        (uint256 stakedAmount, , ) = pool.getStake(user1);
        assertEq(stakedAmount, 10_000 ether);
    }

    function testStakeFailsIfPoolFull() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 500_001 ether);
        vm.expectRevert("Max pool size reached");
        pool.stake(500_001 ether);
        vm.stopPrank();
    }

    function testStakeFailsAfterInterestStart() public {
        vm.warp(block.timestamp + 2 days); // Warp to after interest start
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 1_000 ether);
        vm.expectRevert("Staking period closed");
        pool.stake(1_000 ether);
        vm.stopPrank();
    }

    function testStakeFailsWithoutAllowance() public {
        vm.startPrank(user1);
        vm.expectRevert("Allowance not sufficient");
        pool.stake(1_000 ether);
        vm.stopPrank();
    }

    function testStakeFailsWithInsufficientBalance() public {
        vm.startPrank(user2);
        stakingToken.approve(address(pool), 100_000 ether); // Approve more than balance
        vm.expectRevert("Insufficient balance");
        pool.stake(100_000 ether);
        vm.stopPrank();
    }

    function testStakeExactPoolLimit() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 500_000 ether);
        pool.stake(500_000 ether); // Stake maximum allowed
        vm.stopPrank();

        assertEq(pool.totalStaked(), 500_000 ether);
    }

    function testStakeFailsOnOverflow() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 490_000 ether);
        pool.stake(490_000 ether); // Stake almost max
        vm.expectRevert("Max pool size reached");
        pool.stake(20_000 ether); // Exceeds remaining capacity
        vm.stopPrank();
    }

    function testStakeZeroTokensFails() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 0);
        vm.expectRevert("Cannot stake 0");
        pool.stake(0);
        vm.stopPrank();
    }

    // ============ Tests for Rewards ============

    // function testClaimRewardSuccess() public {
    //     vm.startPrank(user1);
    //     stakingToken.approve(address(pool), 10_000 ether);
    //     pool.stake(10_000 ether);
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 8 days); // After lock-in period
    //     vm.startPrank(user1);
    //     pool.claimReward();
    //     vm.stopPrank();

    //     uint256 reward = (10_000 ether * 10 * 8 days) / (365 days * 100);
    //     assertEq(rewardToken.balanceOf(user1), reward);
    // }

    function testClaimRewardFailsIfDisabled() public {
        pool.enableClaim(false);
        vm.startPrank(user1);
        vm.expectRevert("Claiming disabled");
        pool.claimReward();
        vm.stopPrank();
    }

    function testClaimRewardFailsWithoutAccruedRewards() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 1_000 ether);
        pool.stake(1_000 ether);
        vm.warp(block.timestamp + 1 hours); // Minimal time passed
        vm.expectRevert("No rewards to claim");
        pool.claimReward();
        vm.stopPrank();
    }

    // ============ Tests for Withdrawals ============

    // function testWithdrawAllSuccess() public {
    //     vm.startPrank(user1);
    //     stakingToken.approve(address(pool), 5_000 ether);
    //     pool.stake(5_000 ether);
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 8 days); // After lock-in period
    //     vm.startPrank(user1);
    //     pool.withdrawAll();
    //     vm.stopPrank();

    //     uint256 reward = (5_000 ether * 10 * 8 days) / (365 days * 100);
    //     assertEq(stakingToken.balanceOf(user1), 100_000 ether); // Refund stake
    //     assertEq(rewardToken.balanceOf(user1), reward); // Accrued rewards
    // }

    function testWithdrawFailsBeforeLockIn() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 5_000 ether);
        pool.stake(5_000 ether);
        vm.warp(block.timestamp + 6 days); // Before lock-in ends
        vm.expectRevert("Lock-in period active");
        pool.withdrawAll();
        vm.stopPrank();
    }

    function testWithdrawFailsWithoutStake() public {
        vm.startPrank(user1);
        vm.expectRevert("No stake found");
        pool.withdrawAll();
        vm.stopPrank();
    }

    // ============ Tests for Admin Functions ============

    function testEnableAndDisableClaim() public {
        assertTrue(pool.claimEnabled());
        pool.enableClaim(false);
        assertFalse(pool.claimEnabled());
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 10_000 ether);
        pool.stake(10_000 ether);
        vm.stopPrank();

        pool.emergencyWithdraw();
        assertEq(stakingToken.balanceOf(owner), 10_000 ether);
        assertEq(pool.totalStaked(), 0);
    }

    function testEmergencyWithdrawFailsForNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        pool.emergencyWithdraw();
        vm.stopPrank();
    }

    // ============ Edge Case Tests ============

    // function testClaimRewardAfterPoolEnds() public {
    //     vm.startPrank(user1);
    //     stakingToken.approve(address(pool), 10_000 ether);
    //     pool.stake(10_000 ether);
    //     vm.warp(pool.poolEndTime()); // At pool end time
    //     pool.claimReward();
    //     vm.stopPrank();

    //     uint256 reward = (10_000 ether * 10 * 30 days) / (365 days * 100);
    //     assertEq(rewardToken.balanceOf(user1), reward);
    // }

    function testNoRewardsAccruedAfterPoolEnds() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 10_000 ether);
        pool.stake(10_000 ether);
        vm.warp(block.timestamp + 31 days); // After pool end time
        pool.claimReward();
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(user1), 0); // No further rewards accrued
    }

    // function testRewardCalculationPrecision() public {
    //     vm.startPrank(user1);
    //     stakingToken.approve(address(pool), 1 wei); // Minimal stake
    //     pool.stake(1 wei);
    //     vm.warp(block.timestamp + 365 days); // Full year
    //     pool.claimReward();
    //     vm.stopPrank();

    //     uint256 reward = (1 wei * 10 * 365 days) / (365 days * 100);
    //     assertEq(rewardToken.balanceOf(user1), reward);
    // }
}
