// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import {IUniswapV3Pool} from "../uniswap-contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "../uniswap-contracts/libraries/TickMath.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransferHelper} from "../uniswap-contracts/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "../uniswap-contracts/interfaces/INonfungiblePositionManager.sol";

contract LiquidityExtension is IERC721Receiver {
  address public immutable CIL;
  address public immutable WETH;

  uint24 public constant poolFee = 3000;

  INonfungiblePositionManager public immutable nonfungiblePositionManager;

  /// @notice Represents the deposit of an NFT
  struct Deposit {
    address owner;
    uint128 liquidity;
    address token0;
    address token1;
  }

  /// @dev deposits[tokenId] => Deposit
  mapping(uint256 => Deposit) public deposits;

  constructor(INonfungiblePositionManager _nonfungiblePositionManager, address cil) {
    nonfungiblePositionManager = _nonfungiblePositionManager;
    CIL = cil;
    WETH = nonfungiblePositionManager.WETH9();
  }

  // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
  function onERC721Received(
    address operator,
    address,
    uint256 tokenId,
    bytes calldata
  ) external override returns (bytes4) {
    // get position information

    _createDeposit(operator, tokenId);

    return this.onERC721Received.selector;
  }

  function _createDeposit(address owner, uint256 tokenId) internal {
    (
      ,
      ,
      address token0,
      address token1,
      ,
      ,
      ,
      uint128 liquidity,
      ,
      ,
      ,

    ) = nonfungiblePositionManager.positions(tokenId);

    // set the owner and data for position
    // operator is msg.sender
    deposits[tokenId] = Deposit({
      owner: owner,
      liquidity: liquidity,
      token0: token0,
      token1: token1
    });
  }

  /**
   * @notice Calls the mint function defined in periphery
   * @param amountCILToMint The amount of token0 to deposit
   * @param amountWETHToMint The amount of token1 to deposit
   * @return tokenId The id of the newly minted ERC721
   * @return liquidity The amount of liquidity for the position
   * @return cilAmount The amount of token0
   * @return wethAmount The amount of token1
   */
  function mintNewPosition(
    uint256 amountCILToMint,
    uint256 amountWETHToMint
  ) external returns (uint256 tokenId, uint128 liquidity, uint256 cilAmount, uint256 wethAmount) {
    bool isFirst = WETH > CIL;

    // transfer tokens to contract
    TransferHelper.safeTransferFrom(CIL, msg.sender, address(this), amountCILToMint);
    TransferHelper.safeTransferFrom(WETH, msg.sender, address(this), amountWETHToMint);

    // Approve the position manager
    TransferHelper.safeApprove(CIL, address(nonfungiblePositionManager), amountCILToMint);
    TransferHelper.safeApprove(WETH, address(nonfungiblePositionManager), amountWETHToMint);

    int24 maxTicks = (TickMath.MAX_TICK / 60) * 60;

    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
      token0: isFirst ? CIL : WETH,
      token1: isFirst ? WETH : CIL,
      fee: poolFee,
      tickLower: -1 * maxTicks,
      tickUpper: maxTicks,
      amount0Desired: isFirst ? amountCILToMint : amountWETHToMint,
      amount1Desired: isFirst ? amountWETHToMint : amountCILToMint,
      amount0Min: 0,
      amount1Min: 0,
      recipient: address(this),
      deadline: block.timestamp
    });

    uint256 amount0;
    uint256 amount1;
    // Note that the pool defined by CIL/WETH and fee tier 0.3% must already be created and initialized in order to mint
    (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

    // Create a deposit
    _createDeposit(msg.sender, tokenId);

    cilAmount = isFirst ? amount0 : amount1;
    wethAmount = isFirst ? amount1 : amount0;

    // Remove allowance and refund in both assets.
    if (cilAmount < amountCILToMint) {
      TransferHelper.safeApprove(CIL, address(nonfungiblePositionManager), 0);
      uint256 refund0 = amountCILToMint - cilAmount;
      TransferHelper.safeTransfer(CIL, msg.sender, refund0);
    }

    if (wethAmount < amountWETHToMint) {
      TransferHelper.safeApprove(WETH, address(nonfungiblePositionManager), 0);
      uint256 refund1 = amountWETHToMint - wethAmount;
      TransferHelper.safeTransfer(WETH, msg.sender, refund1);
    }
  }

  /**
   * @notice Collects the fees associated with provided liquidity
   * @dev The contract must hold the erc721 token before it can collect fees
   * @param tokenId The id of the erc721 token
   * @return amount0 The amount of fees collected in token0
   * @return amount1 The amount of fees collected in token1
   */
  function collectAllFees(uint256 tokenId) public returns (uint256 amount0, uint256 amount1) {
    // Caller must own the ERC721 position, meaning it must be a deposit

    // set amount0Max and amount1Max to uint256.max to collect all fees
    // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
    INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
      .CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      });

    (amount0, amount1) = nonfungiblePositionManager.collect(params);

    // send collected feed back to owner
    _sendToOwner(tokenId, amount0, amount1);
  }

  /**
   * @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
   * @param tokenId The id of the erc721 token
   * @param liquidity The liquidity amount to remove
   * @return amountCIL The amount received back in token0
   * @return amountWETH The amount returned back in token1
   */
  function decreaseLiquidity(
    uint256 tokenId,
    uint128 liquidity
  ) external returns (uint256 amountCIL, uint256 amountWETH) {
    bool isFirst = WETH > CIL;

    // caller must be the owner of the NFT
    require(msg.sender == deposits[tokenId].owner, "Not the owner");
    // liquidity should less than total
    require(liquidity <= deposits[tokenId].liquidity, "Invalid liquidity amount");

    // amountCILMin and amountWETHMin are price slippage checks
    // if the amount received after burning is not greater than these minimums, transaction will fail
    INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
      .DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      });

    uint256 amount0;
    uint256 amount1;
    (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

    collectAllFees(tokenId);

    amountCIL = isFirst ? amount0 : amount1;
    amountWETH = isFirst ? amount1 : amount0;
  }

  /// @notice Increases liquidity in the current range
  /// @dev Pool must be initialized already to add liquidity
  /// @param tokenId The id of the erc721 token
  /// @param amountCIL The amount to add of token0
  /// @param amountWETH The amount to add of token1
  function increaseLiquidityCurrentRange(
    uint256 tokenId,
    uint256 amountAddCIL,
    uint256 amountAddWETH
  ) external returns (uint128 liquidity, uint256 amountCIL, uint256 amountWETH) {
    bool isFirst = WETH > CIL;

    TransferHelper.safeTransferFrom(
      deposits[tokenId].token0,
      msg.sender,
      address(this),
      amountAddCIL
    );
    TransferHelper.safeTransferFrom(
      deposits[tokenId].token1,
      msg.sender,
      address(this),
      amountAddWETH
    );

    TransferHelper.safeApprove(
      deposits[tokenId].token0,
      address(nonfungiblePositionManager),
      amountAddCIL
    );
    TransferHelper.safeApprove(
      deposits[tokenId].token1,
      address(nonfungiblePositionManager),
      amountAddWETH
    );

    INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
      .IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: isFirst ? amountAddCIL : amountAddWETH,
        amount1Desired: isFirst ? amountAddWETH : amountAddCIL,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      });

    uint256 amount0;
    uint256 amount1;
    (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);

    amountCIL = isFirst ? amount0 : amount1;
    amountWETH = isFirst ? amount1 : amount0;
  }

  /// @notice Transfers funds to owner of NFT
  /// @param tokenId The id of the erc721
  /// @param amount0 The amount of token0
  /// @param amount1 The amount of token1
  function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
    // get owner of contract
    address owner = deposits[tokenId].owner;

    address token0 = deposits[tokenId].token0;
    address token1 = deposits[tokenId].token1;

    // send collected fees to owner
    TransferHelper.safeTransfer(token0, owner, amount0);
    TransferHelper.safeTransfer(token1, owner, amount1);
  }

  /// @notice Transfers the NFT to the owner
  /// @param tokenId The id of the erc721
  function retrieveNFT(uint256 tokenId) external {
    // must be the owner of the NFT
    require(msg.sender == deposits[tokenId].owner, "Not the owner");
    // transfer ownership to original owner
    nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
    //remove information related to tokenId
    delete deposits[tokenId];
  }
}
