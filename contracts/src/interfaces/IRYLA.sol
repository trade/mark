// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IRYLA
/// @notice Minimal interface for settlement modules interacting with the RYLA token.
interface IRYLA {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
