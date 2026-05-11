// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Interface for a Groth16 proof verifier contract.
/// @dev Matches the output of snarkjs `exportSolidityVerifier`. The verifier contract
///      is generated from the compiled circuit and is specific to that circuit's
///      verification key. Swap the implementation by deploying a new verifier contract
///      and calling `Groth16SettlementVerifier.setVerifierContract`.
///
///      Proof encoding (256 bytes):
///        uint256[2] a   — G1 point (proof.pi_a)
///        uint256[2][2] b — G2 point (proof.pi_b)
///        uint256[2] c   — G1 point (proof.pi_c)
///
///      Public signals (4 × uint256, 128 bytes):
///        [0] nullifierHash  — keccak256(note_secret, nullifier_nonce), prevents double-spend
///        [1] commitmentHash — keccak256(recipient, amount, blinding_factor), binds output note
///        [2] amount         — token amount in base units (must match settlement call)
///        [3] isMint         — 1 for mint, 0 for burn
interface IGroth16Verifier {
    /// @notice Verifies a Groth16 proof against the circuit's verification key.
    /// @param proof   ABI-encoded (uint256[2], uint256[2][2], uint256[2]) — 256 bytes.
    /// @param pubSignals ABI-encoded uint256[4] public signals — 128 bytes.
    /// @return True if the proof is valid.
    function verifyProof(bytes calldata proof, bytes calldata pubSignals) external view returns (bool);
}
