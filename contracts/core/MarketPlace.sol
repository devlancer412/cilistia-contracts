// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ICILStaking} from "./interfaces/ICILStaking.sol";

import "hardhat/console.sol";

/**
 * @title Cilistia P2P MarketPlace
 * @notice cilistia MarketPlace contract
 * price decimals 8
 * percent decimals 2
 */
contract MarketPlace is Ownable {
  using SafeERC20 for IERC20;

  struct PositionCreateParam {
    uint128 price;
    uint128 amount;
    uint128 minAmount;
    uint128 maxAmount;
    bool priceType; // 0 => fixed, 1 => percent
    uint8 paymentMethod; // 0 => BankTransfer, 1 => Other
    address token;
  }

  struct Position {
    uint128 price;
    uint128 amount;
    uint128 minAmount;
    uint128 maxAmount;
    uint128 offerredAmount;
    bool priceType; // 0 => fixed, 1 => percent
    uint8 paymentMethod; // 0 => BankTransfer, 1 => Other
    address token;
    address creator;
  }

  struct Offer {
    bytes32 positionKey;
    uint128 amount;
    address creator;
    bool released;
    bool canceled;
  }

  /// @notice multi sign wallet address of team
  address public immutable multiSig;

  /// @notice cil address
  address public immutable cil;
  /// @notice uniswap router address
  address public cilPair;
  /// @notice cil staking address
  address public cilStaking;
  /// @notice chainlink pricefeeds (address => address)
  mapping(address => address) public pricefeeds;

  /// @notice positions (bytes32 => Position)
  mapping(bytes32 => Position) public positions;
  /// @notice offers (bytes32 => Offer)
  mapping(bytes32 => Offer) public offers;
  /// @notice fee decimals 2
  uint256 public feePoint = 100;

  /// @notice blocked address
  mapping(address => bool) public isBlocked;

  /// @notice fires when create position
  event PositionCreated(
    bytes32 key,
    uint128 price,
    uint128 amount,
    uint128 minAmount,
    uint128 maxAmount,
    bool priceType,
    uint8 paymentMethod,
    address indexed token,
    address indexed creator,
    string terms
  );

  /// @notice fires when update position
  event PositionUpdated(bytes32 indexed key, uint128 amount);

  /// @notice fires when position state change
  event OfferCreated(bytes32 offerKey, bytes32 indexed positionKey, uint128 amount, string terms);

  /// @notice fires when cancel offer
  event OfferCanceled(bytes32 indexed key);

  /// @notice fires when release offer
  event OfferReleased(bytes32 indexed key);

  /// @notice fires when block account
  event AccountBlocked(address account);

  /**
   * @param cil_ cilistia token address
   * @param multiSig_ multi sign wallet address
   */
  constructor(address cil_, address multiSig_) {
    cil = cil_;
    multiSig = multiSig_;
  }

  modifier initialized() {
    require(cilStaking != address(0), "MarketPlace: not initialized yet");
    _;
  }

  modifier whitelisted(address token) {
    if (token != cil) {
      require(pricefeeds[token] != address(0), "MarketPlace: token not whitelisted");
    }
    _;
  }

  modifier noBlocked() {
    require(!isBlocked[msg.sender], "MarketPlace: blocked address");
    _;
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

  /**
   * @dev create position
   * @param params position create params
   * @param terms terms of position
   */
  function createPosition(PositionCreateParam memory params, string memory terms)
    external
    payable
    initialized
    whitelisted(params.token)
    noBlocked
  {
    bytes32 key = getPositionKey(
      params.paymentMethod,
      params.price,
      params.token,
      msg.sender,
      params.amount,
      params.minAmount,
      params.maxAmount,
      block.timestamp
    );

    positions[key] = Position(
      params.price,
      params.amount,
      params.minAmount,
      params.maxAmount,
      0,
      params.priceType,
      params.paymentMethod,
      params.token,
      msg.sender
    );

    if (params.token == address(0)) {
      require(params.amount == msg.value, "MarketPlace: invalid eth amount");
    } else {
      IERC20(params.token).transferFrom(msg.sender, address(this), params.amount);
    }

    emit PositionCreated(
      key,
      params.price,
      params.amount,
      params.minAmount,
      params.maxAmount,
      params.priceType,
      params.paymentMethod,
      params.token,
      msg.sender,
      terms
    );
  }

  /**
   * @dev increate position amount
   * @param key key of position
   * @param amount amount to increase
   */
  function increasePosition(bytes32 key, uint128 amount) external payable initialized noBlocked {
    require(positions[key].creator != address(0), "MarketPlace: not exist such position");
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
  function decreasePosition(bytes32 key, uint128 amount) external initialized noBlocked {
    require(positions[key].creator != address(0), "MarketPlace: not exist such position");
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
  ) external initialized noBlocked {
    require(positions[positionKey].creator != address(0), "MarketPlace: such position don't exist");

    require(positions[positionKey].minAmount <= amount, "MarketPlace: amount less than min");
    require(positions[positionKey].maxAmount >= amount, "MarketPlace: amount exceed max");

    uint256 lockableCil = getStakedCil(positions[positionKey].creator);
    require(lockableCil > amount, "MarketPlace: insufficient staking amount for offer");

    uint256 decimals = 18;
    uint256 price = positions[positionKey].price;

    if (positions[positionKey].token != address(0)) {
      decimals = IERC20Metadata(positions[positionKey].token).decimals();
    }

    if (positions[positionKey].priceType) {
      if (positions[positionKey].token == cil) {
        price = (getCilPrice() * positions[positionKey].price) / 10000;
      } else {
        price =
          (getTokenPrice(positions[positionKey].token) * positions[positionKey].price) /
          10000;
      }
    }

    uint256 tokenAmount = (amount * 10**decimals) / price;
    uint256 cilAmount = (amount * 1e18) / getCilPrice();

    ICILStaking(cilStaking).lock(
      positions[positionKey].creator,
      ICILStaking(cilStaking).lockedCil(positions[positionKey].creator) + cilAmount
    );

    bytes32 key = getOfferKey(positionKey, amount, msg.sender, block.timestamp);

    positions[positionKey].offerredAmount += uint128(tokenAmount);
    offers[key] = Offer(positionKey, uint128(tokenAmount), msg.sender, false, false);

    emit OfferCreated(key, positionKey, amount, terms);
  }

  /**
   * @dev cancel offer
   * @param key key of offer
   */
  function cancelOffer(bytes32 key) external noBlocked {
    require(offers[key].creator == msg.sender, "MarketPlace: you aren't creator of this offer");
    require(!offers[key].released && !offers[key].canceled, "MarketPlace: offer already finished");

    offers[key].canceled = true;
    positions[offers[key].positionKey].offerredAmount -= offers[key].amount;

    emit OfferCanceled(key);
  }

  /**
   * @dev release offer
   * @param key key of offer
   */
  function releaseOffer(bytes32 key) external noBlocked {
    bytes32 positionKey = offers[key].positionKey;
    require(
      positions[positionKey].creator == msg.sender,
      "MarketPlace: you aren't creator of this position"
    );
    require(!offers[key].released && !offers[key].canceled, "MarketPlace: offer already finished");

    offers[key].released = true;
    positions[positionKey].amount -= offers[key].amount;
    positions[positionKey].offerredAmount -= offers[key].amount;

    uint256 fee = (offers[key].amount * feePoint) / 10000;
    if (positions[positionKey].token == address(0)) {
      payable(offers[key].creator).transfer(offers[key].amount - fee);
      payable(multiSig).transfer(fee);
    } else {
      IERC20(positions[positionKey].token).transfer(offers[key].creator, offers[key].amount - fee);
      IERC20(positions[positionKey].token).transfer(multiSig, fee);
    }

    emit OfferReleased(key);
  }

  /**
   * @dev set staking contract address
   * @param cilStaking_ staking contract address
   * @param cilPair_ address of cil/eth pair
   * @param ethPricefeed_ weth pricefeed contract address
   */
  function init(
    address cilStaking_,
    address cilPair_,
    address ethPricefeed_
  ) external onlyOwner {
    cilStaking = cilStaking_;
    cilPair = cilPair_;

    bool isFirst = IUniswapV2Pair(cilPair).token0() == cil;
    pricefeeds[address(0)] = ethPricefeed_;
    pricefeeds[
      isFirst ? IUniswapV2Pair(cilPair).token1() : IUniswapV2Pair(cilPair).token0()
    ] = ethPricefeed_;
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
   * @dev force cancel offer
   * @param key key of offer
   */
  function forceCancelOffer(bytes32 key) external onlyOwner {
    require(!offers[key].released && !offers[key].canceled, "MarketPlace: offer already finished");

    offers[key].canceled = true;
    positions[offers[key].positionKey].offerredAmount -= offers[key].amount;

    emit OfferCanceled(key);
  }

  /**
   * @dev force remove position
   * @param key key of position
   */
  function forceRemovePosition(bytes32 key) external onlyOwner {
    uint256 positionAmount = positions[key].amount;
    isBlocked[positions[key].creator] = true;
    positions[key].amount = 0;
    ICILStaking(cilStaking).remove(positions[key].creator);

    if (positions[key].token == address(0)) {
      payable(multiSig).transfer(positionAmount);
    } else {
      IERC20(positions[key].token).transfer(multiSig, positionAmount);
    }

    emit PositionUpdated(key, 0);
    emit AccountBlocked(positions[key].creator);
  }
}
