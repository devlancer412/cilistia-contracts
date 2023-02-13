// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

/// @notice cilistia staking contract interface
interface ICILStaking {
  /// @notice fires when stake state changes
  event StakeUpdated(address staker, uint256 stakedAmount, uint256 lockedAmount);

  /// @notice fires when unstake token
  event UnStaked(address staker, uint256 rewardAmount);

  /// @dev unstake staked token
  function lock(address staker_, uint256 amount_) external;

  /// @dev return colleted token amount
  function collectedToken(address staker) external view returns (uint256);

  /// @dev return lockable token amount
  function lockableCil(address staker) external view returns (uint256);

  /// @dev return locked token amount
  function lockedCil(address staker) external view returns (uint256);
}
