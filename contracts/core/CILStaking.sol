// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

/// @notice cilistia staking contract
contract CILStaking is ICILStaking {
  /// @notice multi sign wallet address of team
  address public immutable multiSig;
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

  /// @notice total staked token amount
  uint256 public totalStakedAmount;
  uint256 public totalNegativePoint;

  /// @notice lock time - immutable 1 weeks
  uint256 public immutable lockTime = 1 weeks;

  /**
   * @param cil_ cil token address
   * @param marketplace_ marketplace address
   * @param multiSig_ multi sign wallet address
   */
  constructor(
    address cil_,
    address marketplace_,
    address multiSig_
  ) {
    cil = cil_;
    marketplace = marketplace_;
    multiSig = multiSig_;
  }

  /**
   * @dev stake token with amount
   * @param amount token amount to stake
   */
  function stake(uint256 amount) external {
    Stake memory newStake = stakes[msg.sender];
    newStake.tokenAmount += _collectedTokenAmount(msg.sender);

    newStake.tokenAmount += amount;
    totalStakedAmount += (newStake.tokenAmount - stakes[msg.sender].tokenAmount);
    uint256 negativePoint = totalNegativePoint + (newStake.tokenAmount * block.timestamp);
    totalNegativePoint =
      negativePoint -
      (stakes[msg.sender].tokenAmount * stakes[msg.sender].stakedTime);
    newStake.stakedTime = block.timestamp;

    stakes[msg.sender] = newStake;

    IERC20(cil).transferFrom(msg.sender, address(this), amount);

    emit StakeUpdated(msg.sender, newStake.tokenAmount, newStake.lockedAmount);
  }

  /**
   * @dev unstake staked token
   * @param amount token amount to unstake
   */
  function unStake(uint256 amount) external {
    uint256 rewardAmount = _collectedTokenAmount(msg.sender);

    Stake memory newStake = stakes[msg.sender];
    uint256 newTotalStakedAmount = totalStakedAmount;

    uint256 withdrawAmount = amount;

    if (newStake.tokenAmount + rewardAmount < newStake.lockedAmount + amount) {
      withdrawAmount = newStake.tokenAmount + rewardAmount - newStake.lockedAmount;
    }

    newStake.tokenAmount += rewardAmount;
    newStake.tokenAmount -= withdrawAmount;

    newTotalStakedAmount += rewardAmount;
    newTotalStakedAmount -= withdrawAmount;

    uint256 negativePoint = totalNegativePoint + (newStake.tokenAmount * block.timestamp);
    totalNegativePoint =
      negativePoint -
      (stakes[msg.sender].tokenAmount * stakes[msg.sender].stakedTime);

    stakes[msg.sender] = newStake;
    totalStakedAmount = newTotalStakedAmount;

    IERC20(cil).transfer(msg.sender, withdrawAmount);

    emit StakeUpdated(msg.sender, newStake.tokenAmount, newStake.lockedAmount);
    emit UnStaked(msg.sender, withdrawAmount);
  }

  /**
   * @dev return colleted token amount
   * @return collectedAmount total collected token amount
   */
  function collectedToken(address user) external view returns (uint256 collectedAmount) {
    collectedAmount = _collectedTokenAmount(user);
  }

  /**
   * @dev return colleted token amount
   * @param user user address
   * @return stakingAmount lockable staking token amount
   */
  function lockableCil(address user) external view returns (uint256 stakingAmount) {
    stakingAmount = stakes[user].tokenAmount - stakes[user].lockedAmount;
  }

  /**
   * @dev return colleted token amount
   * @param user user address
   * @return stakingAmount unlocked staking token amount
   */
  function lockedCil(address user) external view returns (uint256 stakingAmount) {
    stakingAmount = stakes[user].lockedAmount;
  }

  /**
   * @dev lock staked token: called from marketplace contract
   * @param amount token amount to lock
   */
  function lock(address user, uint256 amount) external {
    require(msg.sender == marketplace, "CILStaking: forbidden");
    require(stakes[user].tokenAmount >= amount, "CILStaking: insufficient staking amount");

    stakes[user].lockedAmount = amount;

    emit StakeUpdated(user, stakes[user].tokenAmount, amount);
  }

  /// @dev remove staking data
  function remove(address user) external {
    require(msg.sender == marketplace, "CILStaking: forbidden");

    Stake memory newStake = stakes[user];

    uint256 reward = _collectedTokenAmount(user) + newStake.stakedTime;

    newStake.stakedTime = block.timestamp;
    newStake.tokenAmount = 0;
    newStake.lockedAmount = 0;

    stakes[user] = newStake;

    IERC20(cil).transfer(multiSig, reward);

    emit StakeUpdated(user, 0, 0);
  }

  /// @dev return total releasable token amount of staking contract
  function _totalReleasable() private view returns (uint256) {
    return IERC20(cil).balanceOf(address(this)) - totalStakedAmount;
  }

  /// @dev return total stake point of staking contract stake point = amount * period
  function _totalStakePoint() private view returns (uint256 totalStakePoint) {
    totalStakePoint = totalStakedAmount * block.timestamp - totalNegativePoint;
  }

  /// @dev get collected token amount
  function _collectedTokenAmount(address user) private view returns (uint256) {
    uint256 totalReleasable = _totalReleasable();
    uint256 totalStakePoint = _totalStakePoint();
    uint256 stakePoint = stakes[user].tokenAmount * (block.timestamp - stakes[user].stakedTime);

    if (stakePoint == 0) {
      return 0;
    }

    return (totalReleasable * stakePoint) / totalStakePoint;
  }
}
