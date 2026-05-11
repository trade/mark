// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

abstract contract PoolErrors {
    error TreeNotInitialized();
    error TreeAlreadyInitialized();
    error TreeFull();
    error LeafOutOfField();
    error UnknownRoot();
    error RootExpired();
    error NullifierUsed();
    error NullifierInvalid();
    error NullifierDuplicate();
    error CommitmentInvalid();
    error CommitmentDuplicate();
    error InvalidProof();
    error VerifierRequired();
    error FeeTooLow();
    error InvalidWithdrawAmount();
    error InvalidWithdrawOwner();
    error InvalidWithdrawRecipient();
    error WithdrawBindingExists();
    error WithdrawBindingMismatch();
    error WithdrawBindingNotFound();
    error InputExceedsCircuitRange();
    error ProductionModeAlreadyEnabled();
    error ProductionModeRequiresVerifier();
    error EpochCanOnlyIncrease();
    error EpochExceedsCircuitRange();
    error InvalidAmount();
    error InvalidRelayer();
}
