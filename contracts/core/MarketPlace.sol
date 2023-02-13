// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

/**
 * @title Cilistia P2P MarketPlace
 * @notice cilistia MarketPlace contract
 * price decimals 8
 * percent decimals 2
 */
contract MarketPlace is Ownable {
  using SafeERC20 for IERC20;

  struct Position {
    bool priceType; // 0 => fixed, 1 => percent
    uint128 price;
    uint8 paymentMethod; // 0 => BankTransfer, 1 => Other
    address token;
    address creator;
    uint128 amount;
    uint128 offerredAmount;
    uint128 minAmount;
    uint128 maxAmount;
  }

  struct Offer {
    bytes32 positionKey;
    uint128 amount;
    address creator;
    bool released;
  }

  /// @notice cil address
  address public immutable cil;
  /// @notice uniswap router address
  address public immutable cilPair;
  /// @notice cil staking address
  address public cilStaking;
  /// @notice chainlink pricefeeds (address => address)
  mapping(address => address) public pricefeeds;

  /// @notice positions (bytes32 => Position)
  mapping(bytes32 => Position) public positions;
  /// @notice offers (bytes32 => Offer)
  mapping(bytes32 => Offer) public offers;

  /// @notice fires when create position
  event PositionCreated(
    bytes32 key,
    bool priceType,
    uint128 price,
    uint8 paymentMethod,
    address indexed token,
    address indexed creator,
    uint128 amount,
    uint128 minAmount,
    uint128 maxAmount,
    string terms
  );

  /// @notice fires when update position
  event PositionUpdated(bytes32 indexed key, uint128 amount);

  /// @notice fires when position state change
  event OfferCreated(bytes32 offerKey, bytes32 indexed positionKey, uint128 amount, string terms);

  /// @notice fires when cancel offer
  event OfferCanceld(bytes32 indexed key);

  /// @notice fires when release offer
  event OfferReleased(bytes32 indexed key);

  /**
   * @param cil_ cilistia token address
   * @param cilPair_ address of cil/eth pair
   * @param ethPricefeed_ weth pricefeed contract address
   */
  constructor(
    address cil_,
    address cilPair_,
    address ethPricefeed_
  ) {
    cil = cil_;
    cilPair = cilPair_;

    bool isFirst = IUniswapV2Pair(cilPair).token0() == cil;
    pricefeeds[address(0)] = ethPricefeed_;
    pricefeeds[
      isFirst ? IUniswapV2Pair(cilPair).token1() : IUniswapV2Pair(cilPair).token0()
    ] = ethPricefeed_;
  }

  modifier initialized() {
    require(cilStaking != address(0), "MarketPlace: not initialized yet");
    _;
  }

  modifier whitelisted(address token) {
    require(pricefeeds[token] != address(0), "MarketPlace: token not whitelisted");
    _;
  }

  /**
   * @dev set staking contract address
   * @param cilStaking_ staking contract address
   */
  function init(address cilStaking_) external onlyOwner {
    cilStaking = cilStaking_;
  }

  /**
   * @dev set token price feed
   * @param token address of token
   * @param pricefeed address of chainlink aggregator
   */
  function setPriceFeed(address token, address pricefeed) external onlyOwner {
    pricefeeds[token] = pricefeed;
  }

  /**
   * @dev get token price
   * @param token address of token
   * @return price price of token
   */
  function getTokenPrice(address token) public view returns (uint256) {
    if (token == cil) {
      return getCilPrice();
    }

    require(pricefeeds[token] != address(0), "MarketPlace: token not whitelisted");

    (, int256 answer, , , ) = AggregatorV3Interface(pricefeeds[token]).latestRoundData();

    return uint256(answer);
  }

  /**
   * @dev get cil token price from uniswap
   * @return price price of cil token
   */
  function getCilPrice() public view returns (uint256) {
    bool isFirst = IUniswapV2Pair(cilPair).token0() == cil;
    (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(cilPair).getReserves();

    uint256 ethPrice = getTokenPrice(address(0));
    uint256 price = isFirst
      ? ((ethPrice * reserve1) / reserve0)
      : ((ethPrice * reserve0) / reserve1);

    return price;
  }

  /**
   * @dev get staking amount with eth
   * @param address_ wallet address
   * @return totalAmount amount of staked cil with usd
   */
  function getStakedCil(address address_) public view returns (uint256 totalAmount) {
    uint256 cilPrice = getCilPrice();
    totalAmount = (ICILStaking(cilStaking).lockableCil(address_) * cilPrice) / 1e18;
  }

  /// @dev calcualate key of position
  function getPositionKey(
    uint8 paymentMethod,
    uint128 price,
    address token,
    address creator,
    uint256 amount,
    uint128 minAmount,
    uint128 maxAmount,
    uint256 timestamp
  ) public pure returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          paymentMethod,
          price,
          token,
          amount,
          minAmount,
          maxAmount,
          creator,
          timestamp
        )
      );
  }

  /// @dev calcualate key of position
  function getOfferKey(
    bytes32 positionKey,
    uint256 amount,
    address creator,
    uint256 timestamp
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(positionKey, amount, creator, timestamp));
  }

  /**
   * @dev create position
   * @param paymentMethod payment methd
   * @param token token address
   * @param amount token amount
   * @param minAmount token min amount
   * @param maxAmount token max amount
   * @param terms terms of position
   */
  function createPosition(
    bool priceType,
    uint128 price,
    uint8 paymentMethod,
    address token,
    uint128 amount,
    uint128 minAmount,
    uint128 maxAmount,
    string memory terms
  ) external payable initialized whitelisted(token) {
    bytes32 key = getPositionKey(
      paymentMethod,
      price,
      token,
      msg.sender,
      amount,
      minAmount,
      maxAmount,
      block.timestamp
    );

    positions[key] = Position(
      priceType,
      price,
      paymentMethod,
      token,
      msg.sender,
      amount,
      minAmount,
      maxAmount,
      0
    );

    if (token == address(0)) {
      require(amount == msg.value, "MarketPlace: invalid eth amount");
    } else {
      IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    emit PositionCreated(
      key,
      priceType,
      price,
      paymentMethod,
      token,
      msg.sender,
      amount,
      minAmount,
      maxAmount,
      terms
    );
  }

  /**
   * @dev increate position amount
   * @param key key of position
   * @param amount amount to increase
   */
  function increasePosition(bytes32 key, uint128 amount) external payable initialized {
    require(positions[key].creator == msg.sender, "MarketPlace: not owner of this position");

    positions[key].amount += amount;

    if (positions[key].token == address(0)) {
      require(amount == msg.value, "MarketPlace: invalid eth amount");
    } else {
      IERC20(positions[key].token).transferFrom(msg.sender, address(this), amount);
    }

    emit PositionUpdated(key, positions[key].amount);
  }

  /**
   * @dev decrease position amount
   * @param key key of position
   * @param amount amount to increase
   */
  function decreasePosition(bytes32 key, uint128 amount) external initialized {
    require(positions[key].creator == msg.sender, "MarketPlace: not owner of this position");
    require(
      positions[key].amount >= positions[key].offerredAmount + amount,
      "MarketPlace: insufficient amount"
    );

    positions[key].amount -= amount;

    if (positions[key].token == address(0)) {
      payable(msg.sender).transfer(amount);
    } else {
      IERC20(positions[key].token).transfer(msg.sender, amount);
    }

    emit PositionUpdated(key, positions[key].amount);
  }

  /**
   * @dev create offer
   * @param positionKey key of position
   * @param amount amount to offer
   * @param terms terms of position
   */
  function createOffer(
    bytes32 positionKey,
    uint128 amount,
    string memory terms
  ) external initialized {
    require(positions[positionKey].creator != address(0), "MarketPlace: such position don't exist");

    uint256 lockableCil = getStakedCil(positions[positionKey].creator);
    require(lockableCil > amount, "MarketPlace: insufficient staking amount for offer");

    uint256 decimals = 18;
    uint256 price = positions[positionKey].price;

    if (positions[positionKey].token != address(0)) {
      decimals = IERC20Metadata(positions[positionKey].token).decimals();
    }

    if (!positions[positionKey].priceType) {
      if (positions[positionKey].token == cil) {
        price = (getCilPrice() * 10000) / positions[positionKey].price;
      } else {
        price =
          (getTokenPrice(positions[positionKey].token) * positions[positionKey].price) /
          10000;
      }
    }

    uint256 tokenAmount = (amount * 10**decimals) / price;

    ICILStaking(cilStaking).lock(
      positions[positionKey].creator,
      ICILStaking(cilStaking).lockedCil(positions[positionKey].creator) + tokenAmount
    );

    bytes32 key = getOfferKey(positionKey, amount, msg.sender, block.timestamp);

    offers[key] = Offer(positionKey, amount, msg.sender, false);

    emit OfferCreated(key, positionKey, amount, terms);
  }
}
