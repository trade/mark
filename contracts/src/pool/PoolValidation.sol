// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolErrors} from "src/pool/errors/PoolErrors.sol";
import {NullifierErrors} from "src/errors/NullifierErrors.sol";
import {MerkleTree} from "src/crypto/MerkleTree.sol";

/// @notice Shared validation helpers for Pool transaction and bridge flows.
library PoolValidation {
    // BN254 scalar field used by Groth16/circom public inputs.
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice Approximate number of L2 blocks per day on OP Stack (~2s block time).
    /// @dev 86400 seconds / 2 seconds per block = 43200 blocks. Shared so block-based
    ///      root-age math stays consistent across the pool and its validation helpers.
    uint256 internal constant BLOCKS_PER_DAY = 43200;

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
        if (nullifiers[0] == nullifiers[1]) revert NullifierErrors.NullifierDuplicate();
        for (uint256 i = 0; i < nullifiers.length; i++) {
            bytes32 nullifier = nullifiers[i];
            if (nullifier == bytes32(0)) revert NullifierErrors.NullifierInvalid();
            if (uint256(nullifier) >= SNARK_SCALAR_FIELD) revert PoolErrors.InputExceedsCircuitRange();
            if (usedNullifiersGlobal[nullifier]) revert NullifierErrors.NullifierUsed();
        }
    }

    function requireCommitmentsValid(bytes32[2] calldata outCommitments) internal pure {
        for (uint256 i = 0; i < outCommitments.length; i++) {
            if (outCommitments[i] == bytes32(0)) revert PoolErrors.CommitmentInvalid();
            if (uint256(outCommitments[i]) >= SNARK_SCALAR_FIELD) revert PoolErrors.InputExceedsCircuitRange();
        }
        if (outCommitments[0] == outCommitments[1]) revert PoolErrors.CommitmentDuplicate();
    }

    /// @notice Validates fee and relayer parameters.
    /// @param fee The fee amount.
    /// @param relayer The relayer address.
    function requireFeeOk(
        uint256 fee,
        address relayer,
        uint256 minFee
    ) internal pure {
        if (minFee > 0 && fee < minFee) revert PoolErrors.FeeTooLow();
        if (fee > 0 && relayer == address(0)) revert PoolErrors.InvalidRelayer();
    }

    /// @notice Validates that a Merkle root is known and not expired.
    /// @dev Reverts with UnknownRoot or RootExpired.
    /// @param root The root hash to validate.
    /// @param knownRoots Mapping of known roots.
    /// @param rootBlockNumbers Mapping of root block numbers.
    /// @param maxRootAge Maximum age for root validity in seconds (0 = no expiry).
    /// @param currentRoot Current active root (never expires).
    function requireRootUsable(
        bytes32 root,
        mapping(bytes32 => bool) storage knownRoots,
        mapping(bytes32 => uint256) storage rootBlockNumbers,
        uint256 maxRootAge,
        bytes32 currentRoot
    ) internal view {
        requireRootWithinCircuitRange(root);
        if (!knownRoots[root]) revert PoolErrors.UnknownRoot();
        if (maxRootAge != 0) {
            if (root != currentRoot) {
                uint256 blockNum = rootBlockNumbers[root];
                // Convert maxRootAge (seconds) to blocks (OP Stack ~2s/block)
                uint256 maxRootAgeBlocks = (maxRootAge * BLOCKS_PER_DAY) / 1 days;
                if (blockNum != 0 && block.number > blockNum + maxRootAgeBlocks) revert PoolErrors.RootExpired();
            }
        }
    }
}
