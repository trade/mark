// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title PoolPublicInputs
/// @notice Encodes the 13 public signals for UTXO proof verification in canonical order.
library PoolPublicInputs {
    // Canonical signal ordering — must match circuit's public declaration order.
    // [0] merkleRoot  [1] chainId  [2] dstChainId  [3] protocolEpoch
    // [4] fee  [5] relayer  [6] nullifier[0]  [7] nullifier[1]
    // [8] outCommitment[0]  [9] outCommitment[1]
    // [10] withdrawOwner  [11] withdrawRecipient  [12] withdrawAmount

    function build(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 dstChainId,
        uint256 protocolEpoch,
        uint256 fee,
        address relayer
    ) internal view returns (uint256[13] memory) {
        return build(
            nullifiers, outCommitments, merkleRoot, dstChainId,
            protocolEpoch, fee, relayer, address(0), address(0), 0
        );
    }

    function build(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 dstChainId,
        uint256 protocolEpoch,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount
    ) internal view returns (uint256[13] memory inputs) {
        inputs[0] = uint256(merkleRoot);
        inputs[1] = block.chainid;
        inputs[2] = dstChainId;
        inputs[3] = protocolEpoch;
        inputs[4] = fee;
        inputs[5] = uint256(uint160(relayer));
        inputs[6] = uint256(nullifiers[0]);
        inputs[7] = uint256(nullifiers[1]);
        inputs[8] = uint256(outCommitments[0]);
        inputs[9] = uint256(outCommitments[1]);
        inputs[10] = uint256(uint160(withdrawOwner));
        inputs[11] = uint256(uint160(withdrawRecipient));
        inputs[12] = withdrawAmount;
    }
}
