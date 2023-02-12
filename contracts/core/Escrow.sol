// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

/**
 * @title Escrow
 * @notice cilistia escrow contract
 */
contract Escrow is Ownable {
  using SafeERC20 for IERC20;

  enum TransactionState {
    Pending,
    Rejected,
    Fulfilled,
    Canceled
  }

  struct Transaction {
    address token; // 160 bytes
    address from; // 160 bytes
    address to; // 160 bytes
    uint32 updatedTime; // 32 bytes
    uint256 amount; // 256 bytes
    TransactionState state;
  }

  /// @notice lock duration = immutable 1 weeks
  uint32 public immutable lockTime = 1 weeks;

  // /// @notice staking contract address
  // address public staking;
  /// @notice whitelistedToken
  mapping(address => bool) public whitelisted;
  /// @notice fee amount
  mapping(address => uint256) private feeAmount;

  /// @notice transactions key => Transaction
  mapping(bytes32 => Transaction) public transactions;

  /// @notice sign key => address => bool
  mapping(bytes32 => mapping(address => bool)) public sign;

  /// @notice fires when create transaction
  event TransactionCreated(
    bytes32 key,
    address indexed token,
    address indexed from,
    address indexed to,
    uint32 updatedTime,
    uint256 amount
  );

  /// @notice fires when update transaction state
  event TransactionUpdated(bytes32 indexed key, TransactionState state, uint32 updatedTime);

  /// @notice fires when sign to transaction
  event TransactionSigned(bytes32 indexed key, address indexed user);

  /// @notice fires when clear all sign of transaction
  event SignCleared(bytes32 indexed key);

  /// @notice fires when token whitelisted
  event TokenWhitelisted(address indexed token, bool state);

  /*/// @param staking_ staking contract address*/
  /// @param cil cil token address
  constructor(
    address cil // address staking_
  ) {
    // staking = staking_;

    whitelisted[cil] = true;
    whitelisted[address(0)] = true;

    emit TokenWhitelisted(cil, true);
    emit TokenWhitelisted(address(0), true);
  }

  modifier pendingTransaction(bytes32 key) {
    require(transactions[key].updatedTime != 0, "Escrow: such transaction doesn't exist");
    require(
      transactions[key].state != TransactionState.Canceled &&
        transactions[key].state != TransactionState.Fulfilled,
      "Escrow: transaction already finished"
    );
    require(
      transactions[key].from == msg.sender || transactions[key].to == msg.sender,
      "Escrow: you aren't signer of this transaction"
    );
    _;
  }

  /**
   * @dev set whitelist tokens
   * @param token token address
   * @param value token whitelist state
   */
  function setWhitelist(address token, bool value) public onlyOwner {
    whitelisted[token] = value;

    emit TokenWhitelisted(token, value);
  }

  /// @dev get transaction key
  function getTransactionKey(
    address token,
    address from,
    address to,
    uint256 timestamp
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(token, from, to, timestamp));
  }

  /**
   * @dev creates transaction
   * @param token token address
   * @param to to address
   * @param amount amount of token
   */
  function createTransaction(
    address token,
    address to,
    uint256 amount
  ) public payable {
    require(whitelisted[token], "Escrow: not whitelisted token");

    bytes32 key = getTransactionKey(token, msg.sender, to, block.timestamp);
    Transaction memory transaction = Transaction(
      token,
      msg.sender,
      to,
      uint32(block.timestamp),
      amount,
      TransactionState.Pending
    );

    transactions[key] = transaction;

    if (token == address(0)) {
      require(amount == msg.value, "Escrow: invalid eth amount");
    } else {
      IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    emit TransactionCreated(key, token, msg.sender, to, uint32(block.timestamp), amount);
  }

  /// @dev cancel all sign of transaction when reject or resume
  function _cancelAllSign(bytes32 key) private {
    sign[key][transactions[key].from] = false;
    sign[key][transactions[key].to] = false;

    emit SignCleared(key);
  }

  /**
   * @dev sign to transaction
   * @param key key of transaction
   */
  function signTransaction(bytes32 key) public pendingTransaction(key) {
    require(!sign[key][msg.sender], "Escrow: you already signed to this transaction");

    sign[key][msg.sender] = true;

    emit TransactionSigned(key, msg.sender);
  }

  /**
   * @dev reject transaction - change transaction state to rejected
   * @param key key of transaction
   */
  function rejectTransaction(bytes32 key) public pendingTransaction(key) {
    require(transactions[key].from == msg.sender, "Escrow: you aren't sender of this transaction");
    require(
      transactions[key].state == TransactionState.Pending,
      "Escrow: invalid transaction state"
    );

    Transaction memory newTransaction = transactions[key];

    newTransaction.state = TransactionState.Rejected;
    newTransaction.updatedTime = uint32(block.timestamp);

    transactions[key] = newTransaction;
    _cancelAllSign(key);

    emit TransactionUpdated(key, TransactionState.Rejected, uint32(block.timestamp));
  }

  /**
   * @dev resume transaction - change transaction state to pedding
   * @param key key of transaction
   */
  function resumeTransaction(bytes32 key) public pendingTransaction(key) {
    require(transactions[key].from == msg.sender, "Escrow: you aren't sender of this transaction");
    require(
      transactions[key].state == TransactionState.Rejected,
      "Escrow: invalid transaction state"
    );

    Transaction memory newTransaction = transactions[key];

    newTransaction.state = TransactionState.Pending;
    newTransaction.updatedTime = uint32(block.timestamp);

    transactions[key] = newTransaction;
    _cancelAllSign(key);

    emit TransactionUpdated(key, TransactionState.Pending, uint32(block.timestamp));
  }

  /**
   * @dev finish transaction
   * @param key key of transaction
   */
  function finishTransaction(bytes32 key) public pendingTransaction(key) {
    require(
      block.timestamp > transactions[key].updatedTime + lockTime,
      "Escrow: can't finished transaction during lock time"
    );
    require(
      sign[key][transactions[key].from] && sign[key][transactions[key].to],
      "Escrow: not signed yet"
    );

    address destination;
    TransactionState state;
    uint256 amount;
    if (transactions[key].state == TransactionState.Pending) {
      transactions[key].state = TransactionState.Fulfilled;

      destination = transactions[key].to;
      state = TransactionState.Fulfilled;
      uint256 fee = transactions[key].amount / 100;
      amount = transactions[key].amount - fee;

      feeAmount[transactions[key].token] += fee;
    } else if (transactions[key].state == TransactionState.Rejected) {
      transactions[key].state = TransactionState.Canceled;

      destination = transactions[key].from;
      state = TransactionState.Canceled;
      amount = transactions[key].amount;
    } else {
      revert("Escrow: invalid transaction state");
    }

    if (transactions[key].token == address(0)) {
      payable(destination).transfer(amount);
    } else {
      IERC20(transactions[key].token).transfer(destination, amount);
    }

    emit TransactionUpdated(key, state, uint32(block.timestamp));
  }

  /**
   * @dev force finish transaction by admin
   * @param key key of transaction
   * @param direction if direction is true, send to toAddress, else send to fromAddress
   */
  function forceFinishTrancsaction(bytes32 key, bool direction)
    public
    pendingTransaction(key)
    onlyOwner
  {
    require(
      block.timestamp > transactions[key].updatedTime + lockTime,
      "Escrow: can't finished transaction during lock time"
    );

    address destination;
    TransactionState state;
    uint256 amount;
    if (direction) {
      transactions[key].state = TransactionState.Fulfilled;

      destination = transactions[key].to;
      state = TransactionState.Fulfilled;
      uint256 fee = transactions[key].amount / 100;
      amount = transactions[key].amount - fee;

      feeAmount[transactions[key].token] += fee;
    } else {
      transactions[key].state = TransactionState.Canceled;

      destination = transactions[key].from;
      state = TransactionState.Canceled;
      amount = transactions[key].amount;
    }

    if (transactions[key].token == address(0)) {
      payable(destination).transfer(amount);
    } else {
      IERC20(transactions[key].token).transfer(destination, amount);
    }

    emit TransactionUpdated(key, state, uint32(block.timestamp));
  }

  /**
   * @dev Recovery functions incase assets are stuck in the contract
   * @param token token address
   * @param benefactor receiver address
   */
  function recoverLeftoverTokens(address token, address benefactor) public onlyOwner {
    feeAmount[token] = 0;

    IERC20(token).transfer(benefactor, feeAmount[token]);
  }

  /**
   * @dev Recovery functions native token are stuck in the contract
   * @param benefactor receiver address
   */
  function recoverNativeToken(address benefactor) public onlyOwner {
    feeAmount[address(0)] = 0;

    payable(benefactor).transfer(feeAmount[address(0)]);
  }
}
