// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

/// @notice cilistia staking contract
contract CILStaking is ICILStaking {
  // cil token address
  address public immutable cil;

  struct Stake {
    uint128 tokenAmount; // amount of tokens locked in a stake
    uint64 stakedTime; // start time of locking
    uint64 unlockableTime; // end time of the locking
  }

  /// @notice active stakes for each user
  mapping(address => Stake) public stakes;
  /// @notice active staker address list
  address[] private stakers;

  /// @notice total staked token amount
  uint256 public totalStakedAmount;

  /// @notice lock time - immutable 1 weeks
  uint64 public immutable lockTime = 1 weeks;

  /// @param cil_ cil token address
  constructor(address cil_) {
    cil = cil_;
  }

  /// @dev return total releasable token amount of staking contract
  function _totalReleasable() private view returns (uint256) {
    return IERC20(cil).balanceOf(address(this)) - totalStakedAmount;
  }

  /// @dev return total stake point of staking contract stake point = amount * period
  function _totalStakePoint() private view returns (uint256 totalStakePoint) {
    totalStakePoint = 0;
    for (uint256 i = 0; i < stakers.length; i++) {
      totalStakePoint +=
        stakes[stakers[i]].tokenAmount *
        (block.timestamp - stakes[stakers[i]].stakedTime);
    }
  }

  /**
   * @dev stake token with amount
   * @param amount_ token amount to stake
   */
  function stake(uint256 amount_) external {
    Stake memory newStake = stakes[msg.sender];
    if (newStake.tokenAmount > 0) {
      newStake.tokenAmount += uint128(_collectedTokenAmount(msg.sender));
    } else {
      stakers.push(msg.sender);
    }

    newStake.tokenAmount += uint128(amount_);
    totalStakedAmount += (newStake.tokenAmount - stakes[msg.sender].tokenAmount);
    newStake.stakedTime = uint64(block.timestamp);
    newStake.unlockableTime = newStake.stakedTime + lockTime;

    stakes[msg.sender] = newStake;

    IERC20(cil).transferFrom(msg.sender, address(this), amount_);

    emit StakeUpdated(msg.sender, newStake.tokenAmount, newStake.unlockableTime);
  }

  /// @dev unstake staked token
  function unStake() external {
    require(stakes[msg.sender].tokenAmount > 0, "CILStaking: you didn't stake");
    require(
      stakes[msg.sender].unlockableTime < block.timestamp,
      "CILStaking: can't unStake during lock time"
    );

    uint256 rewardAmount = _collectedTokenAmount(msg.sender);

    rewardAmount += stakes[msg.sender].tokenAmount;
    totalStakedAmount -= stakes[msg.sender].tokenAmount;

    for (uint256 i = 0; i < stakers.length; i++) {
      if (stakers[i] == msg.sender) {
        stakers[i] = stakers[stakers.length - 1];
        stakers.pop();
      }
    }

    stakes[msg.sender].tokenAmount = 0;

    IERC20(cil).transfer(msg.sender, rewardAmount);

    emit UnStaked(msg.sender, rewardAmount);
  }

  /// @dev get collected token amount
  function _collectedTokenAmount(address staker_) private view returns (uint256) {
    uint256 totalReleasable = _totalReleasable();
    uint256 totalStakePoint = _totalStakePoint();
    uint256 stakePoint = stakes[staker_].tokenAmount *
      (block.timestamp - stakes[staker_].stakedTime);

    if (stakePoint == 0) {
      return 0;
    }

    return (totalReleasable * stakePoint) / totalStakePoint;
  }

  /**
   * @dev return colleted token amount
   * @return collectedAmount total collected token amount
   */
  function collectedToken(address staker_) external view returns (uint256 collectedAmount) {
    collectedAmount = _collectedTokenAmount(staker_);
  }

  /**
   * @dev return colleted token amount
   * @param staker_ staker address
   * @return stakedAmount total staked token amount
   */
  function stakedToken(address staker_) public view returns (uint256 stakedAmount) {
    stakedAmount = stakes[staker_].tokenAmount;
  }
}
