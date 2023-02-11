// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @notice utility and governance token of the Cilistia protocol. (https://docs.cilistia.com/cil)
 */
contract CIL is Context, IERC20, IERC20Metadata, Ownable {
  // token initialize state
  bool public initialized = false;
  // community multiSig contract address
  address public immutable multiSig;

  // staking contract address;
  address public staking;

  // uniswap addresses
  address public pool;
  // liquidity extension
  address public liquidityExtension;

  // erc20 variables
  mapping(address => uint256) private _balances;

  mapping(address => mapping(address => uint256)) private _allowances;

  uint256 private _totalSupply;

  string private _name;
  string private _symbol;

  // fires when initialize token
  event Initialized(address pool);

  /**
   * @param multiSig_ multi sign contract address
   */
  constructor(address multiSig_) {
    _name = "Cilistia";
    _symbol = "CIL";
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
  ) public onlyOwner {
    require(!initialized, "CIL: already initialized");

    uint256 _decimals = decimals();
    _mint(preSale_, 50_000 * 10**_decimals);
    _mint(airdrop_, 20_000 * 10**_decimals);
    _mint(multiSig, 4_930_000 * 10**_decimals); // 5,000,000 - 70,000 = 4,930,000

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

  /**
   * @dev setup hook for fee 1% (70% to staking contract, 30% to multiSig wallet)
   */
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    _beforeTokenTransfer(from, to, amount);

    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - amount;
    }
    if (initialized && from != liquidityExtension && (from == pool || to == pool)) {
      uint256 totalFee = amount / 100; // 1% of swap amount
      uint256 toStaking = (totalFee * 7) / 10; // send 70% to staking contract
      _balances[staking] += toStaking;
      _balances[multiSig] += (totalFee - toStaking); // send 30% to team multisig wallet
      _balances[to] += (amount - totalFee);
    } else {
      _balances[to] += amount;
    }

    emit Transfer(from, to, amount);

    _afterTokenTransfer(from, to, amount);
  }

  ////////////////////////////////////////////////////
  // ERC20 functions
  ////////////////////////////////////////////////////

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function decimals() public view virtual override returns (uint8) {
    return 18;
  }

  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) public view virtual override returns (uint256) {
    return _balances[account];
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    address owner = _msgSender();
    _transfer(owner, to, amount);
    return true;
  }

  function allowance(address owner, address spender)
    public
    view
    virtual
    override
    returns (uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) public virtual override returns (bool) {
    address owner = _msgSender();
    _approve(owner, spender, amount);
    return true;
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    address spender = _msgSender();
    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);
    return true;
  }

  function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
    address owner = _msgSender();
    _approve(owner, spender, allowance(owner, spender) + addedValue);
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    virtual
    returns (bool)
  {
    address owner = _msgSender();
    uint256 currentAllowance = allowance(owner, spender);
    require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
      _approve(owner, spender, currentAllowance - subtractedValue);
    }

    return true;
  }

  function _mint(address account, uint256 amount) internal virtual {
    require(account != address(0), "ERC20: mint to the zero address");

    _beforeTokenTransfer(address(0), account, amount);

    _totalSupply += amount;
    _balances[account] += amount;
    emit Transfer(address(0), account, amount);

    _afterTokenTransfer(address(0), account, amount);
  }

  function _burn(address account, uint256 amount) internal virtual {
    require(account != address(0), "ERC20: burn from the zero address");

    _beforeTokenTransfer(account, address(0), amount);

    uint256 accountBalance = _balances[account];
    require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
      _balances[account] = accountBalance - amount;
    }
    _totalSupply -= amount;

    emit Transfer(account, address(0), amount);

    _afterTokenTransfer(account, address(0), amount);
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) internal virtual {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _spendAllowance(
    address owner,
    address spender,
    uint256 amount
  ) internal virtual {
    uint256 currentAllowance = allowance(owner, spender);
    if (currentAllowance != type(uint256).max) {
      require(currentAllowance >= amount, "ERC20: insufficient allowance");
      unchecked {
        _approve(owner, spender, currentAllowance - amount);
      }
    }
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual {}

  function _afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual {}
}
