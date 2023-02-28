// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @notice utility and governance token of the Cilistia protocol. (https://docs.cilistia.com/cil)
contract CIL is Context, ERC20, Ownable {
  /// @notice token initialize state
  bool public initialized = false;
  /// @notice community multiSig contract address
  address public immutable multiSig;

  /// @notice staking contract address;
  address public staking;

  /// @notice uniswap addresses
  address public pool;
  /// @notice liquidity extension
  address public liquidityExtension;

  /// @notice erc20 variables
  mapping(address => uint256) private _balances;

  mapping(address => mapping(address => uint256)) private _allowances;

  uint256 private _totalSupply;

  string private _name;
  string private _symbol;

  /// @notice fires when initialize token
  event Initialized(address pool);

  /// @param multiSig_ multi sign contract address
  constructor(address multiSig_) ERC20("Cilistia", "CIL") {
    multiSig = multiSig_;
  }

  /**
   * @dev init cilistia token supply
   * @param preSale_ preSale contract address
   * @param airdrop_ airdrop contract address
   * @param staking_ staking contract address
   * @param uniswapRouter_ uniswap router address
   * @param liquidityExtension_ uniswap router address
   */
  function init(
    address preSale_,
    address airdrop_,
    address staking_,
    address uniswapRouter_,
    address liquidityExtension_
  ) external onlyOwner {
    require(!initialized, "CIL: already initialized");

    _mint(preSale_, 50_000 * 1e18);
    _mint(airdrop_, 20_000 * 1e18);
    _mint(multiSig, 4_930_000 * 1e18); // 5,000,000 - 70,000 = 4,930,000

    staking = staking_;
    liquidityExtension = liquidityExtension_;

    IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(uniswapRouter_);
    IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

    pool = uniswapFactory.createPair(address(this), uniswapRouter.WETH());

    initialized = true;

    emit Initialized(pool);
  }

  /**
   * @dev renounce price of CIL ($ per CIL)
   * @param staking_ price of the cil token
   */
  function renounceStaking(address staking_) external onlyOwner {
    require(staking_ != address(0), "CILPreSale: invalid staking address");
    staking = staking_;
  }

  /// @dev setup hook for fee 1% (70% to staking contract, 30% to multiSig wallet)
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    if (from == liquidityExtension || to == liquidityExtension || (from != pool && to != pool)) {
      super._transfer(from, to, amount);
      return;
    }

    uint256 totalFee = amount / 100; // 1% of swap amount
    uint256 toStaking = (totalFee * 7) / 10; // send 70% to staking contract

    super._transfer(from, staking, toStaking);
    super._transfer(from, multiSig, totalFee - toStaking);
    super._transfer(from, to, amount - totalFee);
  }
}
