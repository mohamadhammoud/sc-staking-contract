// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

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
        stakingToken.transfer(user1, 500_000 ether);
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
        rewardToken.transfer(address(pool), 100_000 ether);
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

    function testClaimRewardSuccess() public {
        stakingToken.transfer(user1, 10_000 ether);

        uint256 stakingAmount = 10_000 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakingAmount);
        pool.stake(stakingAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days); // After lock-in period

        vm.startPrank(user1);
        pool.claimReward();
        vm.stopPrank();

        // Break down the calculation to avoid rational constants
        uint256 apr = 10; // 10%
        uint256 durationInSeconds = 8 * 86400; // 8 days in seconds
        uint256 reward = (stakingAmount * apr * durationInSeconds) /
            (365 * 86400 * 100);

        assertEq(rewardToken.balanceOf(user1), reward);
    }

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

    function testWithdrawAllSuccess() public {
        uint256 oldBalance = stakingToken.balanceOf(user1);
        uint256 stakingAmount = 5_000 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakingAmount);
        pool.stake(stakingAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days); // After lock-in period
        vm.startPrank(user1);
        pool.withdrawAll();
        vm.stopPrank();

        // Declare and initialize intermediate variables
        uint256 apr = 10; // 10% APR
        uint256 durationInSeconds = 8 * 86400; // 8 days in seconds

        // Calculate reward
        uint256 reward = (stakingAmount * apr * durationInSeconds) /
            (365 * 86400 * 100);

        // Assert the results
        assertEq(stakingToken.balanceOf(user1), oldBalance); // Refund stake
        assertEq(rewardToken.balanceOf(user1), reward); // Accrued rewards
    }

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

        vm.warp(block.timestamp + 8 days); // After lock-in period
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
        uint256 ownerBalance = stakingToken.balanceOf(address(this));
        uint256 stakedAmount = 10_000 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(pool), stakedAmount);
        pool.stake(stakedAmount);
        vm.stopPrank();

        pool.emergencyWithdraw();
        assertEq(
            stakingToken.balanceOf(address(this)),
            ownerBalance + stakedAmount
        );
        assertEq(pool.totalStaked(), 0);
    }

    function testEmergencyWithdrawFailsForNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );

        pool.emergencyWithdraw();
        vm.stopPrank();
    }

    // ============ Edge Case Tests ============

    // function testClaimRewardAfterPoolEnds() public {
    //     uint256 stakingAmount = 10_000 ether;

    //     vm.startPrank(user1);
    //     stakingToken.approve(address(pool), stakingAmount);
    //     pool.stake(stakingAmount);
    //     vm.stopPrank();

    //     // Move to pool end time
    //     vm.warp(pool.poolEndTime());

    //     vm.startPrank(user1);
    //     pool.claimReward();
    //     vm.stopPrank();

    //     // Reflect contract logic for reward calculation
    //     uint256 apr = 10; // 10% APR
    //     uint256 interestStart = pool.interestStartTime();
    //     uint256 lastUpdated = pool.interestStartTime(); // When user staked
    //     uint256 lockinEnd = interestStart + pool.lockinPeriod();
    //     uint256 effectiveEndTime = pool.poolEndTime() < lockinEnd
    //         ? pool.poolEndTime()
    //         : lockinEnd;
    //     uint256 durationInSeconds = effectiveEndTime - lastUpdated;

    //     uint256 reward = (stakingAmount * apr * durationInSeconds) /
    //         (365 * 86400 * 100);

    //     console.log("Interest Start:", interestStart);
    //     console.log("Lock-In End:", lockinEnd);
    //     console.log("Effective End Time:", effectiveEndTime);
    //     console.log("Duration in Seconds:", durationInSeconds);
    //     console.log("Reward Calculated:", reward);
    //     console.log("Reward from Contract:", rewardToken.balanceOf(user1));

    //     assertEq(rewardToken.balanceOf(user1), reward);
    // }

    function testRewardCalculationPrecision() public {
        vm.startPrank(user1);
        stakingToken.approve(address(pool), 1 wei); // Minimal stake
        pool.stake(1 wei);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days); // Full year

        vm.startPrank(user1);
        vm.expectRevert("No rewards to claim"); // Expect no rewards for minimal stake
        pool.claimReward();
        vm.stopPrank();
    }
}
