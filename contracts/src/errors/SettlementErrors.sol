// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Shared settlement module custom errors.
abstract contract SettlementErrors {
    error InvalidAmount();
    error InvalidIntent();
    error IntentAlreadyConsumed();
    error BurnEscrowInvariantFailed();
    error VerifierRequired();
    error VerificationFailed();
    error ProductionModeAlreadyEnabled();
    error ProductionModeRequiresProofValidation();
}
