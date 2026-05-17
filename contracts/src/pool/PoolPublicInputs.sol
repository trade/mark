// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Canonical public input encoder for UTXO proof verification.
library PoolPublicInputs {
    function build(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 chainId,
        uint256 dstChainId,
        uint256 protocolEpoch,
        uint256 fee,
        address relayer
    ) internal pure returns (uint256[13] memory publicInputs) {
        return build(
            nullifiers,
            outCommitments,
            merkleRoot,
            chainId,
            dstChainId,
            protocolEpoch,
            fee,
            relayer,
            address(0),
            address(0),
            0
        );
    }

    function build(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 chainId,
        uint256 dstChainId,
        uint256 protocolEpoch,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount
    ) internal pure returns (uint256[13] memory publicInputs) {
        // Canonical ordering:
        // [root, chainId, dstChainId, protocolEpoch, fee, relayer, nullifier0, nullifier1, outCommitment0, outCommitment1, withdrawOwner, withdrawRecipient, withdrawAmount]
        publicInputs[0] = uint256(merkleRoot);
        publicInputs[1] = chainId;
        publicInputs[2] = dstChainId;
        publicInputs[3] = protocolEpoch;
        publicInputs[4] = fee;
        publicInputs[5] = uint256(uint160(relayer));
        publicInputs[6] = uint256(nullifiers[0]);
        publicInputs[7] = uint256(nullifiers[1]);
        publicInputs[8] = uint256(outCommitments[0]);
        publicInputs[9] = uint256(outCommitments[1]);
        publicInputs[10] = uint256(uint160(withdrawOwner));
        publicInputs[11] = uint256(uint160(withdrawRecipient));
        publicInputs[12] = withdrawAmount;
    }
}
