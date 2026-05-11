// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Interface for the snarkjs-generated Groth16 verifier contract.
/// @dev Public signal ordering (4 signals, canonical):
///      [0] nullifierHash  — Poseidon(secret, nonce), prevents double-spend
///      [1] commitmentHash — Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
///      [2] amount         — token amount in base units
///      [3] isMint         — 1 for mint, 0 for burn
interface IUTXOVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[4] calldata pubSignals
    ) external view returns (bool);
}
