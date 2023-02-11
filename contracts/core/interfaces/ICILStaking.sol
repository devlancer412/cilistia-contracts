// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

/// @notice cilistia staking contract interface
interface ICILStaking {
  /// @notice fires when stake state changes
  event StakeUpdated(address staker, uint128 stakedAmount, uint64 unlockableTime);

  /// @notice fires when unstake token
  event UnStaked(address staker, uint256 rewardAmount);

  /// @dev stake token with amount
  function stake(uint256 amount_) external;

  /// @dev unstake staked token
  function unStake() external;

  /// @dev return colleted token amount
  function collectedToken() external view returns (uint256);
}
