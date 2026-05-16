// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Interface for the snarkjs-generated Groth16 verifier contract.
/// @dev Matches the output of snarkjs `exportSolidityVerifier` for the UTXOSettlement circuit.
///      Public signal ordering (13 signals, canonical):
///      [0]  merkleRoot       [1]  chainId         [2]  dstChainId
///      [3]  protocolEpoch    [4]  fee              [5]  relayer
///      [6]  nullifier[0]     [7]  nullifier[1]
///      [8]  outCommitment[0] [9]  outCommitment[1]
///      [10] withdrawOwner    [11] withdrawRecipient [12] withdrawAmount
///
///      Proof encoding (passed as separate typed arrays):
///        uint256[2]    a  — G1 point pi_a
///        uint256[2][2] b  — G2 point pi_b (snarkjs coordinate order)
///        uint256[2]    c  — G1 point pi_c
interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[13] calldata input
    ) external view returns (bool);
}
