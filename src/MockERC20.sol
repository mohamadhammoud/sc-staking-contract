// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice A mock implementation of the ERC20 token standard with an initial supply of 2 billion tokens.
 */
contract MockERC20 is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 2_000_000_000 ether; // 2 billion tokens with 18 decimals

    /**
     * @notice Constructor mints 2 billion tokens to the deployer.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
