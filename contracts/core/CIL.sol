// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPeripheryImmutableState} from "../uniswap-contracts/interfaces/IPeripheryImmutableState.sol";
import {IUniswapV3Factory} from "../uniswap-contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../uniswap-contracts/interfaces/IUniswapV3Pool.sol";
import {ICIL} from "./interfaces/ICIL.sol";

/// @notice utility and governance token of the Cilistia protocol. (https://docs.cilistia.com/cil)
contract CIL is ICIL, ERC20, Ownable {
  /// @notice token initialize state
  bool public initialized;
  /// @notice community multiSig contract address
  address public immutable multiSig;

  /// @notice staking contract address;
  address public staking;

  /// @notice uniswap addresses
  address public pool;
  /// @notice fee exceptions
  address public nonfungiblePositionManager;
  address public liquidityExtension;

  /// @notice fires when initialize token
  event Initialized(address pool);

  /// @param multiSig_ multi sign contract address
  constructor(address multiSig_) ERC20("Cilistia", "CIL") {
    multiSig = multiSig_;
  }

  /**
   * @dev init cilistia token supply
   * @param preSale_ preSale contract address
   * @param ogAirdrop_ airdrop contract address
   * @param trueOgAirdrop_ airdrop contract address
   * @param staking_ staking contract address
   * @param uniswapRouter_ uniswap router address
   * @param liquidityExtension_ uniswap router address
   * @param sqrtPriceX96 sqrtPriceX96 to initialize token
   */
  function init(
    address preSale_,
    address ogAirdrop_,
    address trueOgAirdrop_,
    address staking_,
    address uniswapRouter_,
    address nonfungiblePositionManager_,
    address liquidityExtension_,
    uint160 sqrtPriceX96
  ) external onlyOwner {
    require(!initialized, "CIL: already initialized");

    _mint(preSale_, 50_000 * 1e18);
    _mint(ogAirdrop_, 30_000 * 1e18);
    _mint(trueOgAirdrop_, 20_000 * 1e18);
    _mint(multiSig, 4_900_000 * 1e18); // 5,000,000 - 100,000 = 4,900,000

    staking = staking_;
    nonfungiblePositionManager = nonfungiblePositionManager_;
    liquidityExtension = liquidityExtension_;

    IPeripheryImmutableState uniswapRouter = IPeripheryImmutableState(uniswapRouter_);
    IUniswapV3Factory uniswapFactory = IUniswapV3Factory(uniswapRouter.factory());

    uint24 poolFee = 3000;
    pool = uniswapFactory.createPool(address(this), uniswapRouter.WETH9(), poolFee);
    IUniswapV3Pool(pool).initialize(sqrtPriceX96);

    initialized = true;

    emit Initialized(pool);
  }

  /**
   * @dev update staking contract address
   * @param staking_ address of staking contract
   */
  function updateStaking(address staking_) external onlyOwner {
    require(staking_ != address(0), "CILPreSale: invalid staking address");
    staking = staking_;
  }

  /**
   * @dev update liquidityExtension contract address
   * @param liquidityExtension_ address of liquidityExtension contract
   */
  function updateLiquidityExtension(address liquidityExtension_) external onlyOwner {
    require(liquidityExtension_ != address(0), "CILPreSale: invalid liquidityExtension address");
    liquidityExtension = liquidityExtension_;
  }

  /// @dev setup hook for fee 1% (70% to staking contract, 30% to multiSig wallet)
  function _transfer(address from, address to, uint256 amount) internal virtual override {
    if (
      from == liquidityExtension ||
      to == liquidityExtension ||
      from == nonfungiblePositionManager ||
      to == nonfungiblePositionManager ||
      (from != pool && to != pool)
    ) {
      super._transfer(from, to, amount);
      return;
    }

    uint256 totalFee = amount / 100; // 1% of swap amount
    uint256 toStaking = (totalFee * 7) / 10; // send 70% to staking contract

    super._transfer(from, staking, toStaking);
    super._transfer(from, multiSig, totalFee - toStaking);
    super._transfer(from, to, amount - totalFee);
  }

  function getPrice() external view returns (uint256 price) {
    (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
    return ((uint(sqrtPriceX96) * uint(sqrtPriceX96)) * 1e18) >> (96 * 2);
  }
}
