// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title IPoseidonT3
/// @notice Interface for a deployed Poseidon T3 hash contract (BN254, t=3, 2 inputs).
/// @dev Compatible with Semaphore's deployment at 0xB43122Ecb241DD50062641f089876679fd06599a
///      (same address on Ethereum, OP Mainnet, OP Sepolia, Arbitrum, Base, and others).
interface IPoseidonT3 {
    function hash(uint256[2] memory inputs) external pure returns (uint256);
}
