// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice CIL Airdrop contract, each og can claim 7.1% of total amount.  (https://docs.cilistia.com/cil#tokenomics)
contract CILAirdrop is Ownable {
  using SafeERC20 for IERC20;

  /// @notice cil token addresses
  address public immutable CIL;

  /// @notice signer address
  address public immutable signer;

  /// @notice airdrop datas
  uint32 public openingTime;
  uint32 public closingTime;
  uint32 public ogNumber;
  uint256 public claimAmountPerWallet;

  /// @notice address => claimed timestamp
  mapping(address => uint256) public lastClaimedTime;

  struct Sig {
    bytes32 r;
    bytes32 s;
    uint8 v;
  }

  /// @notice fires when set period
  event SetPeriod(uint32 openingTime, uint32 closingTime);

  /// @notice fires when claimed
  event Claimed(address to, uint256 amount);

  /**
   * @param signer_ signer address
   * @param CIL_ cil token address
   */
  constructor(address signer_, address CIL_) {
    require(signer_ != address(0), "CILAirdrop: invalid signer address");
    require(CIL_ != address(0), "CILAirdrop: invalid CIL address");
    signer = signer_;
    CIL = CIL_;
  }

  /**
   * @dev returns airdrop state
   * @return bool returns true if airdrop is live
   */
  function isOpen() public view returns (bool) {
    return block.timestamp >= openingTime && block.timestamp < closingTime;
  }

  /**
   * @dev validates buy function variables
   * @return isValid ture -> valid, false -> invalid
   */
  function _isClaimParamValid(Sig calldata sig) private view returns (bool) {
    bytes32 messageHash = keccak256(abi.encodePacked(_msgSender()));

    bytes32 ethSignedMessageHash = keccak256(
      abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
    );

    return signer == ecrecover(ethSignedMessageHash, sig.v, sig.r, sig.s);
  }

  /**
   * @dev claim cil token
   * @param sig signature of signer
   * @return result return claimed cil token amount
   */
  function claim(Sig calldata sig) external returns (uint256 result) {
    require(isOpen(), "CILAirdrop: not open now");
    require(_isClaimParamValid(sig), "CILAirdrop: invalid signature");
    require(
      lastClaimedTime[_msgSender()] + 1 days <= block.timestamp,
      "CILAirdrop: already claimed today"
    );

    uint256 tokenAmount = claimAmountPerWallet;

    lastClaimedTime[_msgSender()] = block.timestamp;
    IERC20(CIL).safeTransfer(_msgSender(), tokenAmount);

    emit Claimed(_msgSender(), tokenAmount);
    return tokenAmount;
  }

  /**
   * @dev return balance of cil token
   * @return amount amount of cil token
   */
  function balance() public view returns (uint256) {
    return IERC20(CIL).balanceOf(address(this));
  }

  /**
   * @dev set airdrop settings
   * @param openingTime_ opening time of airdrop
   * @param closingTime_ closing time of airdrop
   * @param ogNumber_ number of og member
   */
  function setPeriod(
    uint32 openingTime_,
    uint32 closingTime_,
    uint32 ogNumber_
  ) external onlyOwner {
    // require(!isOpen(), "CILAirdrop: already opened");
    require(closingTime_ > openingTime_, "CILAirdrop: invalid time window");
    openingTime = openingTime_;
    closingTime = closingTime_;
    ogNumber = ogNumber_;
    claimAmountPerWallet = balance() / ogNumber_ / 14; // 14 days of airdrop duration

    emit SetPeriod(openingTime, closingTime);
  }

  /**
   * @dev withdraw all CIL to another address
   * @param recipient_ address to withdraw cil token
   */
  function withdraw(address recipient_) external onlyOwner {
    uint256 _balance = balance();
    IERC20(CIL).safeTransfer(recipient_, _balance);
  }
}
