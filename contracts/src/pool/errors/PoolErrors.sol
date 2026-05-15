// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Custom errors for the Pool, PoolValidation, and MerkleTree contracts.
abstract contract PoolErrors {
    // Verifier / asset ledger configuration
    error InvalidVerifier();
    error VerifierMustBeContract();
    error InvalidPoseidon();
    error PoseidonMustBeContract();
    error VerifierNotConfigured();
    error InvalidAssetLedger();
    error AssetLedgerMustBeContract();
    error EntrypointMustBeContract();

    // Proof type management
    error InvalidProofType();
    error ProofTypeDisabled();

    // Pause / withdrawal gate
    error AlreadyPaused();
    error NotPaused();
    error WithdrawalsArePaused();
    error WithdrawalsAlreadyPaused();
    error WithdrawalsNotPaused();

    // Fee policy
    error FeeTooLow();
    /// @dev Fired when setMinFee is called with a value > 1. minFee is constrained to
    ///      0 or 1 credit unit — values above 1 indicate a misconfigured fee policy.
    error MinFeeTooLarge();
    error InvalidBurnBps();

    // Merkle tree
    error TreeNotInitialized();
    error TreeAlreadyInitialized();
    error TreeFull();
    error LeafOutOfField();

    // Merkle root / epoch
    error UnknownRoot();
    error RootExpired();
    error RootAlreadyKnown();
    error RootAgeTooLarge();
    error EpochCanOnlyIncrease();
    error EpochExceedsCircuitRange();
    error InputExceedsCircuitRange();

    // Nullifier
    error NullifierUsed();
    error NullifierDuplicate();
    error NullifierInvalid();

    // Commitment
    error CommitmentInvalid();
    error CommitmentDuplicate();

    // Proof / withdraw
    error InvalidProof();
    error InvalidWithdrawAmount();
    error InvalidWithdrawOwner();
    error InvalidWithdrawRecipient();
    error WithdrawBindingExists();

    // Bridge-out
    error BridgeOutDisabled();
    error UnauthorizedBridgeOutCaller();
    error InvalidSource();
    error InvalidDestination();
    error InvalidMessageId();
    error SourceIsDestination();
    error DestinationIsSource();
    error InvalidRoot();
    error BridgeMessageAlreadyProcessed();

    // Generic
    error NoStateChange();
    error InvalidRelayer();
}
