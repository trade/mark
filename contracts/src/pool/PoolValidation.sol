// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolErrors} from "../pool/errors/PoolErrors.sol";

/// @notice Shared validation helpers for Pool transaction and bridge flows.
library PoolValidation {
    // BN254 scalar field used by Groth16/circom public inputs.
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function requireDestEpochAndFeeWithinCircuitRange(uint256 dstChainId, uint256 protocolEpoch, uint256 fee)
        internal
        pure
    {
        if (dstChainId > type(uint64).max) revert PoolErrors.InputExceedsCircuitRange();
        if (protocolEpoch > type(uint32).max) revert PoolErrors.EpochExceedsCircuitRange();
        if (fee > type(uint64).max) revert PoolErrors.InputExceedsCircuitRange();
    }

    function requireWithdrawBindingWithinCircuitRange(
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount
    ) internal pure {
        if (withdrawAmount > type(uint64).max) revert PoolErrors.InputExceedsCircuitRange();
        if (withdrawAmount == 0) {
            if (withdrawOwner != address(0)) revert PoolErrors.InvalidWithdrawOwner();
            if (withdrawRecipient != address(0)) revert PoolErrors.InvalidWithdrawRecipient();
        } else {
            if (withdrawOwner == address(0)) revert PoolErrors.InvalidWithdrawOwner();
            if (withdrawRecipient == address(0)) revert PoolErrors.InvalidWithdrawRecipient();
        }
    }

    function requireRootWithinCircuitRange(bytes32 merkleRoot) internal pure {
        if (uint256(merkleRoot) >= SNARK_SCALAR_FIELD) revert PoolErrors.InputExceedsCircuitRange();
    }

    function requireNullifiersFresh(
        bytes32[2] calldata nullifiers,
        mapping(bytes32 => bool) storage usedNullifiersGlobal
    ) internal view {
        // Check duplicate first so the error is precise.
        if (nullifiers[0] == nullifiers[1]) revert PoolErrors.NullifierDuplicate();
        for (uint256 i = 0; i < nullifiers.length; i++) {
            bytes32 nullifier = nullifiers[i];
            if (nullifier == bytes32(0)) revert PoolErrors.NullifierInvalid();
            if (uint256(nullifier) >= SNARK_SCALAR_FIELD) revert PoolErrors.InputExceedsCircuitRange();
            if (usedNullifiersGlobal[nullifier]) revert PoolErrors.NullifierUsed();
        }
    }

    function requireCommitmentsValid(bytes32[2] calldata outCommitments) internal pure {
        for (uint256 i = 0; i < outCommitments.length; i++) {
            if (outCommitments[i] == bytes32(0)) revert PoolErrors.CommitmentInvalid();
            if (uint256(outCommitments[i]) >= SNARK_SCALAR_FIELD) revert PoolErrors.InputExceedsCircuitRange();
        }
        if (outCommitments[0] == outCommitments[1]) revert PoolErrors.CommitmentDuplicate();
    }
}
