// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IRYLA
/// @notice Minimal interface for settlement modules interacting with the RYLA token.
interface IRYLA is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}
