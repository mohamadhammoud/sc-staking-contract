// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title IFixedStakingPool
 * @notice Interface for interacting with the Fixed Staking Pool contract.
 */
interface IFixedStakingPool {
    /// @notice Event emitted when a user stakes tokens
    event Staked(address indexed user, uint256 amount);

    /// @notice Event emitted when a user claims rewards
    event Claimed(address indexed user, uint256 reward);

    /// @notice Event emitted when a user withdraws all staked tokens and rewards
    event WithdrawAll(address indexed user, uint256 amount, uint256 reward);

    /// @notice Event emitted when claiming rewards is enabled or disabled
    event ClaimEnabled(bool enabled);

    /**
     * @dev Emitted when the owner performs an emergency withdrawal of all staked tokens.
     * @param totalAmount The total amount of staking tokens withdrawn by the owner.
     */
    event EmergencyWithdraw(uint256 totalAmount);

    /**
     * @notice Stakes a specified amount of tokens into the pool.
     * @dev Can only be called before the interest start time and within the pool size limit.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) external;

    /**
     * @notice Claims the accrued rewards for the caller.
     * @dev Rewards can only be claimed if claiming is enabled.
     */
    function claimReward() external;

    /**
     * @notice Withdraws all staked tokens and rewards for the caller.
     * @dev Can only be called after the lock-in period has passed.
     */
    function withdrawAll() external;

    /**
     * @notice Enables or disables reward claiming.
     * @dev Only callable by the contract owner.
     * @param _status True to enable claiming, false to disable.
     */
    function enableClaim(bool _status) external;

    /**
     * @notice Retrieves the staking details for a specific user.
     * @param user The address of the user.
     * @return amount The amount of tokens staked by the user.
     * @return lastUpdatedTime The last time the user's reward was updated.
     * @return accruedReward The total accrued rewards for the user.
     */
    function getStake(
        address user
    )
        external
        view
        returns (
            uint256 amount,
            uint256 lastUpdatedTime,
            uint256 accruedReward
        );

    /**
     * @notice Returns the total amount of tokens currently staked in the pool.
     * @return The total staked amount.
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Checks if claiming rewards is currently enabled.
     * @return True if claiming is enabled, false otherwise.
     */
    function claimEnabled() external view returns (bool);

    /**
     * @notice Returns the fixed Annual Percentage Rate (APR) for the staking pool.
     * @return The APR in percentage (e.g., 10 for 10% APR).
     */
    function fixedAPR() external view returns (uint256);

    /**
     * @notice Returns the epoch time when interest calculation begins.
     * @return The start time in seconds since Unix epoch.
     */
    function interestStartTime() external view returns (uint256);

    /**
     * @notice Returns the epoch time when the staking pool ends.
     * @return The end time in seconds since Unix epoch.
     */
    function poolEndTime() external view returns (uint256);

    /**
     * @notice Returns the lock-in period for staked tokens.
     * @return The lock-in period in seconds.
     */
    function lockinPeriod() external view returns (uint256);

    /**
     * @notice Returns the maximum staking pool size.
     * @return The maximum pool size in tokens.
     */
    function maxPoolSize() external view returns (uint256);
}
