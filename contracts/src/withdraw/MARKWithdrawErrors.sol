// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {NullifierErrors} from "src/errors/NullifierErrors.sol";

/// @notice Custom errors for WithdrawAdapter.
abstract contract MARKWithdrawErrors is NullifierErrors {
    error InvalidCreditOwner();
    error InvalidRecipient();
    error InvalidAmount();
    error InvalidSigner();
    error InvalidIntentDeadline();
    error IntentExpired();
    error IntentExceedsMaxValidity();
    error InsufficientLiquidity();
    error NonceMismatch();
    // Nullifier (inherited from NullifierErrors)
    // error NullifierAlreadyClaimed();
    // error NullifierInvalid();
    // error NullifierDuplicate();
    // error NullifierNotConsumed();
    error WithdrawBindingMismatch();
    error InvalidOwnerSigner();
    error UnauthorizedIntentSigner();
    error OwnerCannotCoSign();
    error NativeTransferFailed();
    error MissingOwnerSignature();
    error MissingIntentSignature();
    error InvalidMaxIntentValidity();
    error InvalidProofPool();
    error ProofPoolMustBeContract();
    error InvalidAssetLedger();
    error AssetLedgerMustBeContract();
    error AlreadyPaused();
    error NotPaused();
    error NoStateChange();
}
