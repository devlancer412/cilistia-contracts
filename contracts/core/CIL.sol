// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

/**
 * @notice utility and governance token of the Cilistia protocol. (https://docs.cilistia.com/cil)
 */
contract CIL is ERC20Permit, Ownable {
  // token decimals
  uint8 private immutable _decimals;

  // token initialize state
  bool public initialized = false;
  // community multiSig contract address
  address public immutable multiSig;

  /**
   * @param multiSig_ multi sign contract address
   * @param decimals_ token decimals
   */
  constructor(address multiSig_, uint8 decimals_) ERC20Permit("Cilistia") ERC20("Cilistia", "CIL") {
    _decimals = decimals_;
    multiSig = multiSig_;
  }

  /**
   * @dev init cilistia token supply
   * @param presale presale contract address
   * @param airdrop airdrop contract address
   */
  function init(address presale, address airdrop) public onlyOwner {
    require(!initialized, "CIL: already initialized");
    _mint(presale, 50_000 * 10**_decimals);
    _mint(airdrop, 20_000 * 10**_decimals);
    _mint(multiSig, 4_930_000 * 10**_decimals);
  }

  /**
   * @dev return token decimals
   * @return decimals decimal of token
   */
  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
