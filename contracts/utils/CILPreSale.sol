// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Cilistia preSale contract address. (https://docs.cilistia.com/cil#tokenomics)
contract CILPreSale is Ownable {
  using SafeERC20 for IERC20;

  /// @notice stable coin addresses
  address public immutable USDT;
  address public immutable USDC;

  /// @notice cil token address
  address public immutable CIL;

  /// @notice multiSig wallet address
  address public immutable multiSig;

  /// @notice signer address
  address public immutable signer;

  /// @notice price per CIL
  uint256 public pricePerCIL = 500;

  /// @notice preSale period
  uint32 public openingTime;
  uint32 public closingTime;

  struct Sig {
    bytes32 r;
    bytes32 s;
    uint8 v;
  }

  /// @notice fires when buy CIL token
  event Buy(
    address indexed _executor,
    string indexed _tokenNameToDeposit,
    uint256 _deposit,
    uint256 _withdraw
  );

  /// @notice fires when set preSale period
  event SetPeriod(uint32 openingTime, uint32 closingTime);

  /// @notice fires when change price
  event PriceChanged(uint256 price);

  /**
   * @param signer_ signer address
   * @param multiSig_ multi sign address
   * @param USDT_ usdt address
   * @param USDC_ usdc address
   * @param CIL_ cil token address
   */
  constructor(address signer_, address multiSig_, address USDT_, address USDC_, address CIL_) {
    require(signer_ != address(0), "CILPreSale: invalid signer address");
    require(multiSig_ != address(0), "CILPreSale: invalid multiSig address");
    require(USDT_ != address(0), "CILPreSale: invalid USDT address");
    require(USDC_ != address(0), "CILPreSale: invalid USDC address");
    require(CIL_ != address(0), "CILPreSale: invalid CIL address");
    signer = signer_;
    multiSig = multiSig_;
    USDT = USDT_;
    USDC = USDC_;
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
   * @param amountToDeposit_ deposit token amount
   * @param tokenNameToDeposit_ token name to deposit
   * @param sig_ signature of backend wallet
   * @return isValid ture -> valid, false -> invalid
   */
  function _isBuyParamValid(
    uint256 amountToDeposit_,
    string memory tokenNameToDeposit_,
    Sig calldata sig_
  ) private view returns (bool) {
    bytes32 messageHash = keccak256(
      abi.encodePacked(_msgSender(), amountToDeposit_, tokenNameToDeposit_)
    );

    bytes32 ethSignedMessageHash = keccak256(
      abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
    );

    return signer == ecrecover(ethSignedMessageHash, sig_.v, sig_.r, sig_.s);
  }

  /**
   * @dev buy cil token with stable coins such as usdt, usdc
   * @param amountToDeposit_ deposit token amount
   * @param tokenNameToDeposit_ token name to deposit
   * @param sig_ signature of backend wallet
   * @return result bought cil token amount
   */
  function buy(
    uint256 amountToDeposit_,
    string memory tokenNameToDeposit_,
    Sig calldata sig_
  ) external returns (uint256 result) {
    require(isOpen(), "CILPreSale: not open now");
    require(
      _isBuyParamValid(amountToDeposit_, tokenNameToDeposit_, sig_),
      "CILPreSale: invalid signature"
    );

    address tokenToDeposit;

    if (keccak256(abi.encodePacked(tokenNameToDeposit_)) == keccak256(abi.encodePacked("USDT")))
      tokenToDeposit = USDT;
    else if (
      keccak256(abi.encodePacked(tokenNameToDeposit_)) == keccak256(abi.encodePacked("USDC"))
    ) tokenToDeposit = USDC;
    else revert("CILPreSale: incorrect deposit token");

    uint256 tokenDecimalToDeposit = IERC20Metadata(tokenToDeposit).decimals();
    uint256 multiplier = IERC20Metadata(CIL).decimals() - tokenDecimalToDeposit;
    uint256 currentAmountInUSD = (IERC20(CIL).balanceOf(_msgSender()) * pricePerCIL) /
      100 /
      (10 ** multiplier);

    require(
      amountToDeposit_ + currentAmountInUSD <= 1000 * (10 ** tokenDecimalToDeposit),
      "CILPreSale: max deposit amount is $1000 per wallet"
    );

    uint256 _balance = balance();
    uint256 amountWithdrawalCIL = (amountToDeposit_ * (10 ** multiplier) * 100) / pricePerCIL;
    require(amountWithdrawalCIL <= _balance, "CILPreSale: insufficient withdrawal amount");
    require(
      IERC20(tokenToDeposit).balanceOf(_msgSender()) >= amountToDeposit_,
      "CILPreSale: insufficient deposit balance"
    );

    IERC20(tokenToDeposit).safeTransferFrom(_msgSender(), multiSig, amountToDeposit_);
    IERC20(CIL).safeTransfer(_msgSender(), amountWithdrawalCIL);

    emit Buy(_msgSender(), tokenNameToDeposit_, amountToDeposit_, amountWithdrawalCIL);

    return amountWithdrawalCIL;
  }

  /**
   * @dev return balance of cil token
   * @return amount amount of cil token
   */
  function balance() public view returns (uint256) {
    return IERC20(CIL).balanceOf(address(this));
  }

  /**
   * @dev set preSale settings
   * @param openingTime_ opening time of airdrop
   * @param closingTime_ closing time of airdrop
   */
  function setPeriod(uint32 openingTime_, uint32 closingTime_) external onlyOwner {
    // require(!isOpen(), "CILPreSale: already opened");
    require(closingTime_ > openingTime_, "CILPreSale: invalid time window");
    openingTime = openingTime_;
    closingTime = closingTime_;

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

  /**
   * @dev renounce price of CIL ($ per CIL)
   * @param priceCIL_ price of the cil token
   */
  function renouncePrice(uint256 priceCIL_) external onlyOwner {
    require(priceCIL_ > 0, "CILPreSale: price must be greater than zero");
    pricePerCIL = priceCIL_;

    emit PriceChanged(priceCIL_);
  }
}
