// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title Liquidity extension contract
 * @notice add liquidity to uniswap router
 */
contract LiquidityExtension is Ownable {
  // uniswap router address
  address public router;

  /**
   * @param router_ uniswap router address
   */
  constructor(address router_) {
    router = router_;
  }

  /**
   * @dev add liquidity to uniswap pool
   * @param tokenA first token address
   * @param tokenB first token address
   * @param amountADesired first token deposit amount
   * @param amountBDesired second token deposit amount
   * @param amountAMin first token min amount
   * @param amountBMin second token min amount
   */
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) external {
    IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
    IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
    IERC20(tokenA).approve(router, amountADesired);
    IERC20(tokenB).approve(router, amountBDesired);
    IUniswapV2Router02(router).addLiquidity(
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      amountAMin,
      amountBMin,
      msg.sender,
      block.timestamp + 10 minutes
    );
    uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
    IERC20(tokenA).transfer(msg.sender, balanceA);
    uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
    IERC20(tokenB).transfer(msg.sender, balanceB);
  }

  /**
   * @dev add liquidity to uniswap pool with eth
   * @param token token address
   * @param amountTokenDesired token deposit amount
   * @param amountTokenMin token min amount
   * @param amountETHMin eth min amount
   */
  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountETHMin
  ) external payable {
    IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
    IERC20(token).approve(router, amountTokenDesired);
    (, uint256 amountETH, ) = IUniswapV2Router02(router).addLiquidityETH{value: msg.value}(
      token,
      amountTokenDesired,
      amountTokenMin,
      amountETHMin,
      msg.sender,
      block.timestamp + 10 minutes
    );
    uint256 balance = IERC20(token).balanceOf(address(this));
    IERC20(token).transfer(msg.sender, balance);
    if (msg.value > amountETH) transferDust();
  }

  /**
   * @dev transfer remainning eth
   */
  function transferDust() internal {
    address liquidityProvider = msg.sender;
    payable(liquidityProvider).transfer(address(this).balance);
  }

  /**
   * @dev Recovery functions incase assets are stuck in the contract
   * @param token token address
   * @param benefactor receiver address
   */
  function recoverLeftoverTokens(address token, address benefactor) public onlyOwner {
    uint256 leftOverBalance = IERC20(token).balanceOf(address(this));
    IERC20(token).transfer(benefactor, leftOverBalance);
  }

  /**
   * @dev Recovery functions native token are stuck in the contract
   * @param benefactor receiver address
   */
  function recoverNativeToken(address benefactor) public onlyOwner {
    payable(benefactor).transfer(address(this).balance);
  }

  /**
   * @dev to receive eth from uniswap router
   */
  receive() external payable {}
}
