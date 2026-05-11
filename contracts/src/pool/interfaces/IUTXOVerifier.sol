// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Interface for the snarkjs-generated Groth16 verifier contract.
/// @dev Public signal ordering (13 signals, canonical):
///      [0]  merkleRoot
///      [1]  chainId
///      [2]  dstChainId
///      [3]  protocolEpoch
///      [4]  fee
///      [5]  relayer
///      [6]  nullifier[0]
///      [7]  nullifier[1]
///      [8]  outCommitment[0]
///      [9]  outCommitment[1]
///      [10] withdrawOwner
///      [11] withdrawRecipient
///      [12] withdrawAmount
interface IUTXOVerifier {
    /// @notice Verifies a Groth16 proof.
    /// @param a   G1 point pi_a.
    /// @param b   G2 point pi_b (snarkjs coordinate order — caller must NOT swap).
    /// @param c   G1 point pi_c.
    /// @param input 13 public signals in canonical order.
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[13] calldata input
    ) external view returns (bool);
}
