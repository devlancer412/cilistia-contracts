// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

/// @notice cilistia token contract interface
interface ICIL {
  /// @dev return cil token price base on eth price
  function getPrice() external view returns (uint256 price);
}
