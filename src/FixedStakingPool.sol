// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FixedStakingPool
 * @notice This contract allows users to stake tokens, earn rewards based on a fixed APR, and withdraw after the pool end time.
 */
contract FixedStakingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Struct for user stake details
    struct Stake {
        uint256 amount; // Amount staked
        uint256 accruedReward; // Rewards accrued so far
        uint256 lastUpdatedTime; // Last timestamp when rewards were calculated
    }

    // Public state variables
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    uint256 public immutable fixedAPR; // Annual Percentage Rate in %
    uint256 public immutable interestStartTime; // When rewards start
    uint256 public immutable poolEndTime; // When the pool ends
    uint256 public immutable maxPoolSize; // Maximum staking capacity
    bool public claimEnabled;

    uint256 public totalStaked; // Total staked in the pool

    // Mapping for user stakes
    mapping(address => Stake) private stakes;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 reward);
    event WithdrawAll(address indexed user, uint256 amount, uint256 reward);
    event EmergencyWithdraw(uint256 amount);
    event ClaimEnabled(bool enabled);

    // Modifiers
    modifier beforeInterestStart() {
        require(block.timestamp < interestStartTime, "Staking period closed");
        _;
    }

    modifier afterPoolEndTime() {
        require(block.timestamp >= poolEndTime, "Pool period active");
        _;
    }

    modifier withinPoolLimit(uint256 amount) {
        require(totalStaked + amount <= maxPoolSize, "Max pool size reached");
        _;
    }

    modifier claimAllowed() {
        require(claimEnabled, "Claiming disabled");
        _;
    }

    /**
     * @notice Constructor to initialize the staking pool.
     * @param _stakingToken The token users stake.
     * @param _rewardToken The token users earn as rewards.
     * @param _fixedAPR Fixed Annual Percentage Rate (e.g., 10 for 10%).
     * @param _interestStartTime When interest calculation starts.
     * @param _poolEndTime When the pool ends.
     * @param _maxPoolSize Maximum pool staking capacity.
     */
    constructor(
        IERC20 _stakingToken,
        IERC20 _rewardToken,
        uint256 _fixedAPR,
        uint256 _interestStartTime,
        uint256 _poolEndTime,
        uint256 _maxPoolSize
    ) Ownable(msg.sender) {
        require(_interestStartTime > block.timestamp, "Start time in the past");
        require(
            _poolEndTime > _interestStartTime,
            "End time before start time"
        );

        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        fixedAPR = _fixedAPR;
        interestStartTime = _interestStartTime;
        poolEndTime = _poolEndTime;
        maxPoolSize = _maxPoolSize;

        claimEnabled = false; // Disabled by default
    }

    /**
     * @notice Stake tokens into the pool before the interest start time.
     * @param amount Amount of tokens to stake.
     */
    function stake(
        uint256 amount
    ) external nonReentrant beforeInterestStart withinPoolLimit(amount) {
        require(amount > 0, "Cannot stake 0");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        Stake storage userStake = stakes[msg.sender];
        _updateReward(msg.sender);

        userStake.amount += amount;
        userStake.lastUpdatedTime = block.timestamp;

        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Claim accrued rewards.
     */
    function claimReward() external nonReentrant claimAllowed {
        _updateReward(msg.sender);

        Stake storage userStake = stakes[msg.sender];
        uint256 reward = userStake.accruedReward;
        require(reward > 0, "No rewards to claim");

        userStake.accruedReward = 0;
        rewardToken.safeTransfer(msg.sender, reward);

        emit Claimed(msg.sender, reward);
    }

    /**
     * @notice Withdraw staked tokens and rewards after the pool end time.
     */
    function withdrawAll() external nonReentrant afterPoolEndTime {
        _updateReward(msg.sender);

        Stake memory userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");

        uint256 amountToWithdraw = userStake.amount;
        uint256 reward = userStake.accruedReward;

        delete stakes[msg.sender];
        totalStaked -= amountToWithdraw;

        stakingToken.safeTransfer(msg.sender, amountToWithdraw);
        rewardToken.safeTransfer(msg.sender, reward);

        emit WithdrawAll(msg.sender, amountToWithdraw, reward);
    }

    /**
     * @notice Enable or disable claiming of rewards.
     * @param _status True to enable, false to disable.
     */
    function enableClaim(bool _status) external onlyOwner {
        claimEnabled = _status;
        emit ClaimEnabled(_status);
    }
    /**
     * @notice Get the stake details for a specific user.
     * @param user The address of the user.
     * @return amount The amount staked by the user.
     * @return lastUpdatedTime The last time the user's reward was updated.
     * @return accruedReward The total accrued reward for the user.
     */
    function getStake(
        address user
    )
        external
        view
        returns (uint256 amount, uint256 lastUpdatedTime, uint256 accruedReward)
    {
        Stake memory userStake = stakes[user];
        return (
            userStake.amount,
            userStake.lastUpdatedTime,
            userStake.accruedReward
        );
    }

    /**
     * @notice Emergency withdraw all staked tokens.
     * @dev Can only be called by the owner.
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 totalTokens = stakingToken.balanceOf(address(this));
        require(totalTokens > 0, "No tokens to withdraw");

        stakingToken.safeTransfer(owner(), totalTokens);

        emit EmergencyWithdraw(totalTokens);
    }

    /**
     * @notice Internal function to update rewards for a user.
     * @param user Address of the user.
     */
    function _updateReward(address user) internal {
        Stake storage userStake = stakes[user];

        uint256 pending = _calculateReward(
            userStake.amount,
            userStake.lastUpdatedTime
        );
        userStake.accruedReward += pending;
        userStake.lastUpdatedTime = block.timestamp;
    }

    /**
     * @notice Internal function to calculate rewards.
     * @param amount Staked amount.
     * @param lastUpdatedTime Last timestamp of reward calculation.
     * @return Rewards calculated.
     */
    function _calculateReward(
        uint256 amount,
        uint256 lastUpdatedTime
    ) internal view returns (uint256) {
        if (block.timestamp < interestStartTime || lastUpdatedTime == 0) {
            return 0;
        }

        uint256 startTime = interestStartTime > lastUpdatedTime
            ? interestStartTime
            : lastUpdatedTime;

        uint256 endTime = block.timestamp > poolEndTime
            ? poolEndTime
            : block.timestamp;

        uint256 duration = endTime - startTime;
        return (amount * fixedAPR * duration) / (365 days * 100);
    }
}
