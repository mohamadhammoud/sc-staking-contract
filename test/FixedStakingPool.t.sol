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
    uint256 fixedAPR = 10; // 10% APR
    uint256 interestStartTime;
    uint256 poolEndTime;
    uint256 maxPoolSize = 500_000 ether;

    function setUp() public {
        stakingToken = new MockERC20("StakingToken", "STK");
        rewardToken = new MockERC20("RewardToken", "RWD");

        // Transfer tokens for testing
        stakingToken.transfer(user1, 500_000 ether);
        stakingToken.transfer(user2, 500_000 ether);
        rewardToken.transfer(owner, 1_000_000 ether);

        interestStartTime = block.timestamp + 1 days;
        poolEndTime = interestStartTime + 30 days;

        // Deploy the staking pool contract
        pool = new FixedStakingPool(
            IERC20(stakingToken),
            IERC20(rewardToken),
            fixedAPR,
            interestStartTime,
            poolEndTime,
            maxPoolSize
        );

        rewardToken.approve(address(pool), 1_000_000 ether);
        rewardToken.transfer(address(pool), 1_000_000 ether);
    }

    /// @notice Successful withdrawal after pool end time
    function testWithdrawAllSuccess() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to after pool end time
        vm.warp(poolEndTime + 1);

        // User1 withdraws
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // Expected reward calculation
        uint256 duration = poolEndTime - interestStartTime; // Full staking duration
        uint256 expectedReward = (stakeAmount * fixedAPR * duration) /
            (365 days * 100);

        // Verify staked amount and rewards are transferred back
        assertEq(stakingToken.balanceOf(user1), 500_000 ether); // Refund full stake
        assertEq(rewardToken.balanceOf(user1), expectedReward); // Correct reward
    }

    /// @notice Multiple users withdraw after pool end time
    function testMultipleUsersWithdrawSuccess() public {
        uint256 stakeAmountUser1 = 100_000 ether;
        uint256 stakeAmountUser2 = 50_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmountUser1);
        pool.stake(stakeAmountUser1);
        vm.stopPrank();

        // User2 stakes
        vm.startPrank(user2);
        stakingToken.approve(address(pool), stakeAmountUser2);
        pool.stake(stakeAmountUser2);
        vm.stopPrank();

        // Warp to after pool end time
        vm.warp(poolEndTime + 1);

        // User1 withdraws
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // User2 withdraws
        vm.startPrank(user2);
        pool.withdrawAll();
        vm.stopPrank();

        // Expected reward calculations
        uint256 duration = poolEndTime - interestStartTime; // Full staking duration
        uint256 expectedRewardUser1 = (stakeAmountUser1 * fixedAPR * duration) /
            (365 days * 100);
        uint256 expectedRewardUser2 = (stakeAmountUser2 * fixedAPR * duration) /
            (365 days * 100);

        // Verify staked amounts and rewards are transferred back
        assertEq(stakingToken.balanceOf(user1), 500_000 ether); // Refund full stake
        assertEq(rewardToken.balanceOf(user1), expectedRewardUser1); // Correct reward for User1

        assertEq(stakingToken.balanceOf(user2), 500_000 ether); // Refund full stake
        assertEq(rewardToken.balanceOf(user2), expectedRewardUser2); // Correct reward for User2
    }

    /// @notice Withdrawal with no rewards (before interest start time)
    function testWithdrawBeforeInterestStart() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to just before interest start time
        vm.warp(interestStartTime - 1);

        // Attempt to withdraw (should fail due to pool end time)
        vm.startPrank(user1);
        vm.expectRevert("Pool period active");
        pool.withdrawAll();
        vm.stopPrank();
    }

    /// @notice Successful withdrawal after late staking
    function testLateStakingAndWithdrawal() public {
        uint256 stakeAmount = 100_000 ether;

        // Warp to just before interest start time
        vm.warp(interestStartTime - 1);

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to after pool end time
        vm.warp(poolEndTime + 1);

        // User1 withdraws
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // Expected reward calculation
        uint256 duration = poolEndTime - interestStartTime; // Full staking duration
        uint256 expectedReward = (stakeAmount * fixedAPR * duration) /
            (365 days * 100);

        // Verify staked amount and rewards are transferred back
        assertEq(stakingToken.balanceOf(user1), 500_000 ether); // Refund full stake
        assertEq(rewardToken.balanceOf(user1), expectedReward); // Correct reward
    }

    /// @notice Partial withdrawals are not allowed
    function testPartialWithdrawNotAllowed() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to after pool end time
        vm.warp(poolEndTime + 1);

        // User1 attempts partial withdrawal (not supported in contract)
        vm.startPrank(user1);
        pool.withdrawAll();

        vm.expectRevert("No stake found");
        pool.withdrawAll();
        vm.stopPrank();
    }

    /// @notice Multiple staking and single withdrawal
    function testMultipleStakingAndSingleWithdrawal() public {
        uint256 firstStake = 50_000 ether;
        uint256 secondStake = 50_000 ether;

        // User1 stakes first amount
        vm.startPrank(user1);
        stakingToken.approve(address(pool), firstStake);
        pool.stake(firstStake);
        vm.stopPrank();

        // User1 stakes additional amount
        vm.startPrank(user1);
        stakingToken.approve(address(pool), secondStake);
        pool.stake(secondStake);
        vm.stopPrank();

        // Warp to after pool end time
        vm.warp(poolEndTime + 1);

        // User1 withdraws
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // Expected reward calculation
        uint256 duration = poolEndTime - interestStartTime;
        uint256 expectedReward = ((firstStake + secondStake) *
            fixedAPR *
            duration) / (365 days * 100);

        // Verify staked amount and rewards
        assertEq(stakingToken.balanceOf(user1), 500_000 ether); // Refund full stake
        assertEq(rewardToken.balanceOf(user1), expectedReward); // Correct reward
    }

    /// @notice Staking fails after the staking period closes
    function testStakingFailsAfterInterestStart() public {
        uint256 stakeAmount = 100_000 ether;

        // Warp to after interest start time
        vm.warp(interestStartTime + 1);

        // User1 attempts to stake (should fail)
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        vm.expectRevert("Staking period closed");
        pool.stake(stakeAmount);
        vm.stopPrank();
    }

    /// @notice Staking beyond max pool size
    function testStakingBeyondMaxPoolSize() public {
        uint256 stakeAmount = 400_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // User2 attempts to stake, exceeding max pool size
        vm.startPrank(user2);
        stakingToken.approve(address(pool), 200_000 ether);
        vm.expectRevert("Max pool size reached");
        pool.stake(200_000 ether);
        vm.stopPrank();
    }

    /// @notice Emergency withdraw clears the pool
    function testEmergencyWithdrawClearsPool() public {
        uint256 stakeAmount = 500_000 ether;
        uint256 ownerOldbalance = stakingToken.balanceOf(owner);

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Owner performs emergency withdraw
        vm.startPrank(owner);
        pool.emergencyWithdraw();
        vm.stopPrank();

        // Verify the pool is emptied
        uint256 poolBalance = stakingToken.balanceOf(address(pool));
        uint256 ownerBalance = stakingToken.balanceOf(owner);

        assertEq(
            poolBalance,
            0,
            "Pool balance should be zero after emergency withdraw"
        );
        assertGt(
            ownerBalance,
            ownerOldbalance,
            "Owner should receive all staked tokens"
        );
    }

    /// @notice Claim rewards after enableClaim toggle
    function testClaimAfterEnableToggle() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to after interest start time
        vm.warp(interestStartTime + 1);

        // Enable claim
        vm.startPrank(owner);
        pool.enableClaim(true);
        vm.stopPrank();

        // User1 claims reward
        vm.startPrank(user1);
        pool.claimReward();
        vm.stopPrank();

        // Expected reward calculation
        uint256 duration = block.timestamp - interestStartTime;
        uint256 expectedReward = (stakeAmount * fixedAPR * duration) /
            (365 days * 100);

        // Verify reward transfer
        assertEq(rewardToken.balanceOf(user1), expectedReward);
    }

    /// @notice Staking before and after interestStartTime with different users
    function testStakingWithMultipleUsers() public {
        uint256 stakeAmountUser1 = 100_000 ether;
        uint256 stakeAmountUser2 = 50_000 ether;

        // User1 stakes before interest start time
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmountUser1);
        pool.stake(stakeAmountUser1);
        vm.stopPrank();

        // Warp to after interest start time
        vm.warp(interestStartTime + 1);

        // User2 stakes after interest start time (should fail)
        vm.startPrank(user2);
        stakingToken.approve(address(pool), stakeAmountUser2);
        vm.expectRevert("Staking period closed");
        pool.stake(stakeAmountUser2);
        vm.stopPrank();
    }

    /// @notice Pool end time validation for rewards
    function testRewardCalculationStopsAtPoolEnd() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to beyond pool end time
        vm.warp(poolEndTime + 10 days);

        // User1 withdraws
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // Expected reward calculation (should stop at poolEndTime)
        uint256 duration = poolEndTime - interestStartTime;
        uint256 expectedReward = (stakeAmount * fixedAPR * duration) /
            (365 days * 100);

        // Verify reward calculation stops at poolEndTime
        assertEq(rewardToken.balanceOf(user1), expectedReward);
    }

    function testClaimWithoutStake() public {
        pool.enableClaim(true);

        // User1 tries to claim rewards without staking
        vm.startPrank(user1);
        vm.expectRevert("No rewards to claim");
        pool.claimReward();
        vm.stopPrank();
    }

    function testEmergencyWithdrawWithoutStake() public {
        // Owner calls emergencyWithdraw when no tokens are staked
        vm.startPrank(owner);
        vm.expectRevert("No tokens to withdraw");
        pool.emergencyWithdraw();
        vm.stopPrank();
    }

    function testEnableClaimToggleConsistency() public {
        // Initially disabled
        assertFalse(pool.claimEnabled());

        // Enable claim
        vm.startPrank(owner);
        pool.enableClaim(true);
        assertTrue(pool.claimEnabled());

        // Disable claim
        pool.enableClaim(false);
        assertFalse(pool.claimEnabled());

        // Enable claim again
        pool.enableClaim(true);
        assertTrue(pool.claimEnabled());
        vm.stopPrank();
    }

    function testStakeZeroTokensFails() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 0);
        vm.expectRevert("Cannot stake 0");
        pool.stake(0);
        vm.stopPrank();
    }

    function testStakeFailsWithInsufficientBalance() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 1_000_000 ether); // Approve more than balance
        vm.expectRevert("Max pool size reached");
        pool.stake(1_000_000 ether);
        vm.stopPrank();
    }
    function testRewardsBeforeInterestStart() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to a time before interest start
        vm.warp(interestStartTime - 1);

        // Call the internal reward calculation function indirectly by accessing accrued rewards
        (, , uint256 accruedReward) = pool.getStake(user1);

        // Rewards should be zero before interest starts
        assertEq(
            accruedReward,
            0,
            "Rewards should not accrue before interestStartTime"
        );
    }

    function testRepeatedEmergencyWithdraw() public {
        uint256 stakeAmount = 500_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Owner performs emergency withdraw
        vm.startPrank(owner);
        pool.emergencyWithdraw();
        vm.stopPrank();

        // Verify pool balance is zero
        uint256 poolBalance = stakingToken.balanceOf(address(pool));
        assertEq(poolBalance, 0, "Pool balance should be zero");

        // Try emergency withdraw again (should revert)
        vm.startPrank(owner);
        vm.expectRevert("No tokens to withdraw");
        pool.emergencyWithdraw();
        vm.stopPrank();
    }

    function testConstructorFailsEndTimeBeforeStartTime() public {
        uint256 validInterestStartTime = block.timestamp + 1 days; // Valid start time
        uint256 invalidPoolEndTime = validInterestStartTime - 1 days; // Invalid end time

        vm.expectRevert("End time before start time");
        new FixedStakingPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken)),
            fixedAPR,
            validInterestStartTime,
            invalidPoolEndTime,
            maxPoolSize
        );
    }

    function testClaimRewardFailsWhenDisabled() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes tokens
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to after interest start time
        vm.warp(interestStartTime + 1);

        // Attempt to claim rewards while claim is disabled
        vm.startPrank(user1);
        vm.expectRevert("Claiming disabled");
        pool.claimReward();
        vm.stopPrank();
    }

    function testDeploymentFailsWithPastInterestStartTime() public {
        uint256 pastInterestStartTime = block.timestamp - 1; // Set a past timestamp

        vm.warp(pastInterestStartTime + 3 days);
        vm.expectRevert("Start time in the past");
        new FixedStakingPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken)),
            fixedAPR,
            pastInterestStartTime,
            poolEndTime,
            maxPoolSize
        );
    }

    function testRewardCalculationStartTimeEqualsEndTime() public {
        uint256 stakeAmount = 100_000 ether;

        // User1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakeAmount);
        pool.stake(stakeAmount);
        vm.stopPrank();

        // Warp to just after interestStartTime and claim reward
        vm.warp(interestStartTime + 1);

        vm.startPrank(owner);
        pool.enableClaim(true); // Enable claim
        vm.stopPrank();

        // User1 claims reward (sets lastUpdatedTime to current time)
        vm.startPrank(user1);
        pool.claimReward();
        vm.stopPrank();

        // Warp back to a time before lastUpdatedTime
        vm.warp(interestStartTime);

        // Access internal reward calculation indirectly via accrued rewards
        (, , uint256 accruedReward) = pool.getStake(user1);

        // Assert that the reward calculation hits the `startTime >= endTime` path
        assertEq(
            accruedReward,
            0,
            "Reward should be zero when startTime >= endTime"
        );
    }
}
