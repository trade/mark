// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoseidonT3} from "./PoseidonT3.sol";
import {PoolErrors} from "../errors/PoolErrors.sol";

/// @title MerkleTree
/// @notice Incremental Merkle tree using Poseidon hashing (depth 20, BN254 field).
library MerkleTree {
    uint256 internal constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Tree {
        uint256 depth;
        uint256 nextLeafIndex;
        bytes32 root;
        mapping(uint256 => bytes32) filledSubtrees;
        mapping(uint256 => bytes32) zeros;
    }

    function init(Tree storage tree, uint256 depth) internal {
        if (tree.depth != 0) revert PoolErrors.TreeAlreadyInitialized();
        if (depth == 0 || depth > 32) revert PoolErrors.InputExceedsCircuitRange();

        tree.depth = depth;
        bytes32 current = bytes32(0);
        for (uint256 i = 0; i < depth; i++) {
            tree.zeros[i] = current;
            tree.filledSubtrees[i] = current;
            current = _hash(current, current);
        }
        tree.root = current;
    }

    function insert(Tree storage tree, bytes32 leaf) internal {
        if (tree.depth == 0) revert PoolErrors.TreeNotInitialized();
        if (uint256(leaf) >= FIELD_SIZE) revert PoolErrors.LeafOutOfField();

        uint256 maxLeaves = uint256(1) << tree.depth;
        if (tree.nextLeafIndex >= maxLeaves) revert PoolErrors.TreeFull();

        uint256 index = tree.nextLeafIndex++;
        bytes32 current = leaf;

        for (uint256 i = 0; i < tree.depth; i++) {
            if (index % 2 == 0) {
                tree.filledSubtrees[i] = current;
                current = _hash(current, tree.zeros[i]);
            } else {
                current = _hash(tree.filledSubtrees[i], current);
            }
            index /= 2;
        }
        tree.root = current;
    }

    function getRoot(Tree storage tree) internal view returns (bytes32) {
        return tree.root;
    }

    function _hash(bytes32 left, bytes32 right) private pure returns (bytes32) {
        return bytes32(PoseidonT3.hash([uint256(left), uint256(right)]));
    }
}
