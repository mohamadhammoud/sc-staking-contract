// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IFixedStakingPool} from "./interfaces/IFixedStakingPool.sol";
/**
 * @title FixedStakingPool
 * @notice A fixed staking pool contract with APR, maximum pool size, and controlled interest redemption.
 */
contract FixedStakingPool is Ownable, ReentrancyGuard, IFixedStakingPool {
    using SafeERC20 for IERC20;

    /// @notice Struct representing user stake details
    struct Stake {
        uint256 amount; // Amount staked
        uint256 lastUpdatedTime; // Timestamp when rewards were last updated
        uint256 accruedReward; // Pre-calculated rewards for efficiency
    }

    /// @notice Token used for staking
    IERC20 public immutable stakingToken;

    /// @notice Token used for rewards
    IERC20 public immutable rewardToken;

    /// @notice Annual Percentage Rate (APR) in %
    uint256 public immutable fixedAPR;

    /// @notice Epoch time when interest calculation begins
    uint256 public immutable interestStartTime;

    /// @notice Epoch time when the staking pool ends
    uint256 public immutable poolEndTime;

    /// @notice Lock-in period in seconds
    uint256 public immutable lockinPeriod;

    /// @notice Maximum pool capacity for staking
    uint256 public immutable maxPoolSize;

    /// @notice Total amount currently staked in the pool
    uint256 public totalStaked;

    /// @notice Flag indicating whether claiming rewards is enabled
    bool public claimEnabled;

    /// @notice Mapping of user addresses to their stake details
    mapping(address => Stake) private stakes;

    /// @dev Modifier to ensure actions are performed before the interest start time
    modifier beforeInterestStart() {
        require(block.timestamp < interestStartTime, "Staking period closed");
        _;
    }

    /// @dev Modifier to ensure actions are performed after the lock-in period
    modifier afterLockin() {
        require(
            block.timestamp >= interestStartTime + lockinPeriod,
            "Lock-in period active"
        );
        _;
    }

    /// @dev Modifier to ensure staking does not exceed the maximum pool size
    modifier withinPoolLimit(uint256 amount) {
        require(totalStaked + amount <= maxPoolSize, "Max pool size reached");
        _;
    }

    /// @dev Modifier to ensure actions are within the pool duration
    modifier withinPoolDuration() {
        require(block.timestamp <= poolEndTime, "Staking pool has ended");
        _;
    }

    /**
     * @param _stakingToken Address of the staking token
     * @param _rewardToken Address of the reward token
     * @param _fixedAPR Annual Percentage Rate (APR) in %
     * @param _interestStartTime Epoch time when interest calculation begins
     * @param _poolEndTime Epoch time when the staking pool ends
     * @param _lockinPeriod Lock-in period in seconds
     * @param _maxPoolSize Maximum pool capacity for staking
     * @param _owner Address of the owner
     */
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _fixedAPR,
        uint256 _interestStartTime,
        uint256 _poolEndTime,
        uint256 _lockinPeriod,
        uint256 _maxPoolSize,
        address _owner
    ) Ownable(_owner) {
        require(
            _interestStartTime > block.timestamp,
            "Interest start time must be in the future"
        );
        require(
            _poolEndTime > _interestStartTime,
            "Pool end time must be after interest start time"
        );

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        fixedAPR = _fixedAPR;
        interestStartTime = _interestStartTime;
        poolEndTime = _poolEndTime;
        lockinPeriod = _lockinPeriod;
        maxPoolSize = _maxPoolSize;
        claimEnabled = true;
    }

    /**
     * @notice Stake tokens into the pool before the interest start date.
     * @param amount Amount of tokens to stake.
     */
    function stake(
        uint256 amount
    )
        external
        nonReentrant
        beforeInterestStart
        withinPoolLimit(amount)
        withinPoolDuration
    {
        require(amount > 0, "Cannot stake 0");
        require(
            stakingToken.balanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );
        require(
            stakingToken.allowance(msg.sender, address(this)) >= amount,
            "Allowance not sufficient"
        );

        Stake storage userStake = stakes[msg.sender];
        _updateReward(msg.sender);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        userStake.amount += amount;
        userStake.lastUpdatedTime = block.timestamp;

        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Allows the owner to withdraw all staked tokens in an emergency.
     * @dev This function is restricted to the contract owner and should only be used in exceptional situations.
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 totalAmount = stakingToken.balanceOf(address(this));
        require(totalAmount > 0, "No funds to withdraw");

        stakingToken.safeTransfer(owner(), totalAmount);
        totalStaked = 0; // Reset total staked value

        emit EmergencyWithdraw(totalAmount);
    }

    /**
     * @notice Claim accrued rewards. Only enabled if `claimEnabled` is true.
     */
    function claimReward() external nonReentrant {
        require(claimEnabled, "Claiming disabled");

        _updateReward(msg.sender);

        Stake storage userStake = stakes[msg.sender];
        uint256 reward = userStake.accruedReward;
        require(reward > 0, "No rewards to claim");

        userStake.accruedReward = 0;

        rewardToken.safeTransfer(msg.sender, reward);

        emit Claimed(msg.sender, reward);
    }

    /**
     * @notice Withdraw all staked tokens and rewards after the lock-in period.
     */
    function withdrawAll() external nonReentrant afterLockin {
        _updateReward(msg.sender);

        Stake memory userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");

        uint256 totalAmount = userStake.amount;
        uint256 reward = userStake.accruedReward;

        delete stakes[msg.sender];
        totalStaked -= userStake.amount;

        stakingToken.safeTransfer(msg.sender, totalAmount);
        rewardToken.safeTransfer(msg.sender, reward);

        emit WithdrawAll(msg.sender, totalAmount, reward);
    }

    /**
     * @notice Enable or disable claiming rewards.
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

    function _updateReward(address user) internal {
        Stake storage userStake = stakes[user];
        uint256 pending = _pendingReward(userStake);

        userStake.accruedReward += pending;
        userStake.lastUpdatedTime = block.timestamp;
    }

    function _pendingReward(
        Stake memory userStake
    ) internal view returns (uint256) {
        if (block.timestamp < interestStartTime || userStake.amount == 0) {
            return 0;
        }

        // Determine the cap time for reward calculation
        uint256 capTime = (
            block.timestamp < interestStartTime + lockinPeriod
                ? block.timestamp
                : interestStartTime + lockinPeriod
        );

        capTime = poolEndTime < capTime ? poolEndTime : capTime; // Respect poolEndTime

        uint256 effectiveTime = capTime - userStake.lastUpdatedTime;

        return (userStake.amount * fixedAPR * effectiveTime) / (365 days * 100);
    }
}
