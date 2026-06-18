// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Custom errors for nullifier handling across pool and withdraw adapters.
/// @dev Centralized to ensure consistent error naming and avoid duplication.
abstract contract NullifierErrors {
    /// @dev Reverted when a nullifier has already been spent in the pool.
    error NullifierUsed();

    /// @dev Reverted when a nullifier has already been claimed in the withdraw adapter
    ///      (i.e., the user already withdrew against this nullifier).
    error NullifierAlreadyClaimed();

    /// @dev Reverted when the same nullifier appears twice in the same transaction.
    error NullifierDuplicate();

    /// @dev Reverted when a nullifier is zero or outside the valid field range.
    error NullifierInvalid();

    /// @dev Reverted when a nullifier is not present in the pool's global used set.
    ///      Used by the withdraw adapter to ensure the nullifier was actually spent.
    error NullifierNotConsumed();
}
