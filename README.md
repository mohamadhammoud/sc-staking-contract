# Fixed Staking Pool

## Overview

The Fixed Staking Pool is a smart contract that enables users to stake ERC20 tokens in exchange for fixed annual rewards (APR). The pool provides mechanisms for staking, claiming rewards, withdrawing staked tokens, and emergency withdrawals, making it a flexible and secure solution for token staking.

---

## Key Features

1. **Fixed APR Staking**

   - Users earn rewards based on a predefined Annual Percentage Rate (APR).

2. **Lock-In Period**

   - Rewards accrue only after a defined lock-in period.

3. **Claim Rewards**

   - Users can claim accrued rewards at any time during the pool's duration (after lock-in).

4. **Withdrawal**

   - Users can withdraw their staked tokens and rewards after the lock-in period ends.

5. **Emergency Withdrawals**

   - The contract owner can withdraw all staked tokens in case of emergencies.

6. **Maximum Pool Size**

   - Ensures the staking pool does not exceed its capacity.

7. **Efficient Reward Calculation**
   - Uses pre-computed accrued rewards for optimized gas usage.

---

## Contract Architecture

### Key Components

1. **Stake Struct**
   Represents the details of a user's stake.

   ```solidity
   struct Stake {
       uint256 amount;
       uint256 lastUpdatedTime;
       uint256 accruedReward;
   }
   ```

2. **State Variables**

   - `stakingToken` and `rewardToken`: ERC20 tokens for staking and rewards.
   - `fixedAPR`: Annual Percentage Rate (in %).
   - `interestStartTime` & `poolEndTime`: Timestamps defining the staking window.
   - `lockinPeriod`: Duration users must wait before earning rewards.
   - `maxPoolSize`: The total staking capacity.
   - `totalStaked`: Tracks the amount of tokens staked in the pool.

3. **Mappings**

   - `stakes`: Tracks staking details for each user.

4. **Modifiers**
   - **`beforeInterestStart`**: Restricts actions before staking starts.
   - **`afterLockin`**: Ensures actions occur after the lock-in period.
   - **`withinPoolLimit`**: Validates pool size limits.
   - **`withinPoolDuration`**: Ensures actions occur before the pool end time.

---

## Deployment Parameters

### Constructor Arguments

- **`_stakingToken`**: Address of the staking ERC20 token.
- **`_rewardToken`**: Address of the reward ERC20 token.
- **`_fixedAPR`**: Annual Percentage Rate (e.g., `10` for 10%).
- **`_interestStartTime`**: Epoch time when interest calculation begins.
- **`_poolEndTime`**: Epoch time when the staking pool ends.
- **`_lockinPeriod`**: Lock-in period duration in seconds.
- **`_maxPoolSize`**: Maximum capacity of the staking pool.
- **`_owner`**: Owner of the staking contract.

---

## Functionality

### 1. **Staking Tokens**

#### **`stake(uint256 amount)`**

Allows users to stake tokens before the pool starts accruing interest.

**Workflow:**

1. **Validation:**

   - Check if staking occurs before `interestStartTime`.
   - Verify that the pool has not exceeded its maximum size.
   - Ensure sufficient token allowance and balance.

2. **Updates:**

   - Adds the staked amount to the user's `Stake` struct.
   - Updates `lastUpdatedTime`.

3. **Events:**
   - Emits `Staked` event.

**Example Use Case:**
Alice stakes 10,000 tokens in the pool to earn rewards at a 10% APR.

---

### 2. **Claiming Rewards**

#### **`claimReward()`**

Enables users to claim their accrued rewards.

**Workflow:**

1. **Validation:**

   - Ensure rewards claiming is enabled (`claimEnabled = true`).
   - Check that the user has accrued rewards.

2. **Updates:**

   - Transfers accrued rewards to the user.
   - Resets `accruedReward` to `0`.

3. **Events:**
   - Emits `Claimed` event.

**Example Use Case:**
Bob claims his rewards after 15 days of staking, earning based on the fixed APR.

---

### 3. **Withdrawing Tokens**

#### **`withdrawAll()`**

Allows users to withdraw their staked tokens and accrued rewards after the lock-in period ends.

**Workflow:**

1. **Validation:**

   - Ensure the lock-in period has ended.
   - Check that the user has a valid stake.

2. **Updates:**

   - Transfers staked tokens and rewards to the user.
   - Resets the user's stake.

3. **Events:**
   - Emits `WithdrawAll` event.

**Example Use Case:**
Carol withdraws her 5,000 staked tokens and accrued rewards after 8 days.

---

### 4. **Emergency Withdrawals**

#### **`emergencyWithdraw()`**

Allows the owner to withdraw all staked tokens in emergencies.

**Workflow:**

1. **Validation:**

   - Can only be invoked by the contract owner.

2. **Updates:**

   - Transfers all staked tokens to the owner.
   - Resets `totalStaked` to `0`.

3. **Events:**
   - Emits `EmergencyWithdraw` event.

**Example Use Case:**
The contract owner withdraws all staked tokens due to a critical bug or security breach.

---

## Reward Calculation Logic

Rewards are calculated using the formula:

```solidity
reward = (stakedAmount * fixedAPR * effectiveTime) / (365 * 86400 * 100);
```

- **`stakedAmount`**: Tokens staked by the user.
- **`fixedAPR`**: Annual Percentage Rate (e.g., `10` for 10% APR).
- **`effectiveTime`**: The duration (in seconds) for which rewards are accrued.
  - Limited by the lock-in period and pool end time.

---

## Use Cases

### 1. **Standard Staking and Reward Claiming**

- User stakes tokens before the `interestStartTime`.
- Rewards are claimed after the lock-in period ends.

### 2. **Withdrawing Staked Tokens**

- User withdraws their staked tokens and accrued rewards after the lock-in period.

### 3. **Emergency Withdrawals**

- Owner retrieves all staked tokens in case of emergencies.

---

## Running the Project

### Prerequisites

1. Install [Foundry](https://getfoundry.sh/) for testing and deployment.
2. Install dependencies:
   ```bash
   forge install
   ```

### Compile the Contracts

```bash
forge build
```

### Run Tests

```bash
forge test -vv
```

### Debugging

Add logging to your tests using:

```solidity
console.log("Debug message", variable);
```

---

## Testing

### Unit Tests

1. **Staking Functionality**

   - `testStakeSuccess`: Tests successful staking.
   - `testStakeFailsIfPoolFull`: Validates max pool size limit.

2. **Reward Claiming**

   - `testClaimRewardSuccess`: Validates reward calculation and claiming.
   - `testClaimRewardFailsIfDisabled`: Ensures claiming fails when disabled.

3. **Withdrawals**

   - `testWithdrawAllSuccess`: Tests successful withdrawal of staked tokens and rewards.
   - `testWithdrawFailsBeforeLockIn`: Ensures withdrawal fails before lock-in.

4. **Admin Functions**
   - `testEmergencyWithdraw`: Validates owner’s ability to withdraw all tokens.
   - `testEnableAndDisableClaim`: Tests enabling/disabling reward claiming.

### Edge Case Testing

- `testRewardCalculationPrecision`: Tests precision with minimal stake amounts.

---

## Conclusion

The Fixed Staking Pool provides a secure and efficient way for users to stake tokens and earn fixed APR rewards. Its features, including a lock-in period, reward claiming, and emergency withdrawal, make it suitable for diverse use cases in decentralized finance (DeFi) systems.
