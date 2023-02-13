// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

/// @notice cilistia staking contract
contract CILStaking is ICILStaking {
  /// @notice cil token address
  address public immutable cil;
  /// @notice p2p marketplace contract address
  address public immutable marketplace;

  struct Stake {
    uint256 tokenAmount; // amount of tokens locked in a stake
    uint256 lockedAmount; // amount of tokens locked in a stake
    uint256 stakedTime; // start time of locking
  }

  /// @notice active stakes for each user
  mapping(address => Stake) public stakes;
  /// @notice active staker address list
  address[] private stakers;

  /// @notice total staked token amount
  uint256 public totalStakedAmount;

  /// @notice lock time - immutable 1 weeks
  uint256 public immutable lockTime = 1 weeks;

  /**
   * @param cil_ cil token address
   * @param marketplace_ marketplace address
   */
  constructor(address cil_, address marketplace_) {
    cil = cil_;
    marketplace = marketplace_;
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
      newStake.tokenAmount += _collectedTokenAmount(msg.sender);
    } else {
      stakers.push(msg.sender);
    }

    newStake.tokenAmount += amount_;
    totalStakedAmount += (newStake.tokenAmount - stakes[msg.sender].tokenAmount);
    newStake.stakedTime = block.timestamp;

    stakes[msg.sender] = newStake;

    IERC20(cil).transferFrom(msg.sender, address(this), amount_);

    emit StakeUpdated(msg.sender, newStake.tokenAmount, newStake.lockedAmount);
  }

  /**
   * @dev unstake staked token
   * @param amount_ token amount to unstake
   */
  function unStake(uint256 amount_) external {
    uint256 rewardAmount = _collectedTokenAmount(msg.sender);

    Stake memory newStake = stakes[msg.sender];
    uint256 newTotalStakedAmount = totalStakedAmount;

    require(
      newStake.tokenAmount + rewardAmount > newStake.lockedAmount + amount_,
      "CILStaking: insufficient unstake amount"
    );

    newStake.tokenAmount += rewardAmount;
    newStake.tokenAmount -= amount_;

    newTotalStakedAmount += rewardAmount;
    newTotalStakedAmount -= amount_;

    if (newStake.tokenAmount == 0) {
      for (uint256 i = 0; i < stakers.length; i++) {
        if (stakers[i] == msg.sender) {
          stakers[i] = stakers[stakers.length - 1];
          stakers.pop();
        }
      }
    }

    stakes[msg.sender] = newStake;
    totalStakedAmount = newTotalStakedAmount;

    IERC20(cil).transfer(msg.sender, amount_);

    emit UnStaked(msg.sender, amount_);
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
   * @return stakingAmount lockable staking token amount
   */
  function lockableCil(address staker_) external view returns (uint256 stakingAmount) {
    stakingAmount = stakes[staker_].tokenAmount - stakes[staker_].lockedAmount;
  }

  /**
   * @dev return colleted token amount
   * @param staker_ staker address
   * @return stakingAmount unlocked staking token amount
   */
  function lockedCil(address staker_) external view returns (uint256 stakingAmount) {
    stakingAmount = stakes[staker_].tokenAmount - stakes[staker_].lockedAmount;
  }

  /**
   * @dev lock staked token: called from marketplace contract
   * @param amount_ token amount to lock
   */
  function lock(address staker_, uint256 amount_) external {
    require(msg.sender == marketplace, "CILStaking: forbidden");
    require(stakes[staker_].tokenAmount >= amount_, "CILStaking: insufficient staking amount");

    stakes[staker_].lockedAmount = amount_;

    emit StakeUpdated(staker_, stakes[staker_].tokenAmount, amount_);
  }
}
