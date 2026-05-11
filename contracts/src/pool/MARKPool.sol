// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRYLA} from "../interfaces/IRYLA.sol";
import {IUTXOVerifier} from "./interfaces/IUTXOVerifier.sol";
import {PoolErrors} from "./errors/PoolErrors.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title MARKPool
/// @notice ZK note pool for private RYLA withdrawals.
/// @dev Operators create shielded notes off-chain by committing a note hash on-chain.
///      Note owners prove ownership via a Groth16 proof (UTXOSettlement circuit) to withdraw.
///
///      Circuit public signals (4):
///        [0] nullifierHash  — Poseidon(secret, nonce), prevents double-spend
///        [1] commitmentHash — Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
///        [2] amount         — token amount in base units
///        [3] isMint         — 1 for mint, 0 for burn
///
///      On withdraw, the contract verifies:
///        - proof is valid against the registered verifier
///        - nullifier has not been used before
///        - commitmentHash is registered in the pool
///        - amount and isMint match the proof's public signals
///        - chainId and settlementModule are bound in the commitment (enforced by circuit)
contract MARKPool is ReentrancyGuard, AccessControlDefaultAdminRules, PoolErrors {
    using SafeERC20 for IRYLA;

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    event VerifierSet(address indexed verifier);
    event ProductionModeActivated(address indexed admin);
    event NoteCommitted(bytes32 indexed commitmentHash, uint256 amount);
    event NoteWithdrawn(bytes32 indexed nullifierHash, address indexed recipient, uint256 amount);

    IRYLA public immutable TOKEN;

    IUTXOVerifier public verifier;
    bool public productionMode;

    /// @notice Registered note commitments. commitmentHash => amount.
    mapping(bytes32 => uint256) public commitments;
    /// @notice Spent nullifiers. nullifierHash => true if spent.
    mapping(bytes32 => bool) public usedNullifiers;

    constructor(address initialAdmin, address token)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (token == address(0)) revert ZeroAddress();
        TOKEN = IRYLA(token);
    }

    // Admin

    function setVerifier(address verifierAddr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (productionMode) revert ProductionModeAlreadyEnabled();
        if (verifierAddr == address(0)) revert VerifierRequired();
        if (verifierAddr.code.length == 0) revert VerifierRequired();
        verifier = IUTXOVerifier(verifierAddr);
        emit VerifierSet(verifierAddr);
    }

    function activateProductionMode() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (productionMode) revert ProductionModeAlreadyEnabled();
        if (address(verifier) == address(0)) revert ProductionModeRequiresVerifier();
        productionMode = true;
        emit ProductionModeActivated(msg.sender);
    }

    function setOperator(address operator, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (operator == address(0)) revert ZeroAddress();
        if (enabled) _grantRole(OPERATOR_ROLE, operator);
        else _revokeRole(OPERATOR_ROLE, operator);
    }

    // Pool operations

    /// @notice Commits a shielded note. The operator creates the note off-chain and
    ///         registers its commitment hash on-chain. RYLA is transferred in and burned.
    /// @param commitmentHash Poseidon(secret, amount, isMint=1, recipient, chainId, address(this))
    /// @param amount         Token amount locked in this note.
    function commit(bytes32 commitmentHash, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (commitmentHash == bytes32(0)) revert CommitmentInvalid();
        if (uint256(commitmentHash) >= SNARK_SCALAR_FIELD) revert CommitmentInvalid();
        if (amount == 0) revert InvalidAmount();
        if (commitments[commitmentHash] != 0) revert CommitmentDuplicate();

        commitments[commitmentHash] = amount;
        emit NoteCommitted(commitmentHash, amount);
    }

    /// @notice Withdraws RYLA by proving ownership of a committed note.
    /// @dev The proof binds to chainId and address(this) via the commitmentHash,
    ///      preventing cross-chain and cross-contract replay. The settlementModule
    ///      binding is enforced by the circuit — the prover must know the secret
    ///      that hashes to a commitment including address(this) as settlementModule.
    ///      isMint=1: mints RYLA to recipient (withdraw from pool).
    ///      isMint=0: burns RYLA from recipient (deposit-and-burn flow).
    function withdraw(
        address recipient,
        uint256 amount,
        bool isMint,
        bytes32 nullifierHash,
        bytes32 commitmentHash,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c
    ) external nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (nullifierHash == bytes32(0)) revert NullifierInvalid();
        if (uint256(nullifierHash) >= SNARK_SCALAR_FIELD) revert NullifierInvalid();
        if (usedNullifiers[nullifierHash]) revert NullifierUsed();
        if (commitments[commitmentHash] != amount) revert CommitmentInvalid();

        IUTXOVerifier v = verifier;
        if (address(v) == address(0)) revert VerifierRequired();

        // Public signals: [nullifierHash, commitmentHash, amount, isMint]
        uint256[4] memory signals;
        signals[0] = uint256(nullifierHash);
        signals[1] = uint256(commitmentHash);
        signals[2] = amount;
        signals[3] = isMint ? 1 : 0;

        // G2 coordinate swap: snarkjs uses (x[1],x[0]) order
        uint256[2][2] memory bFixed = [[b[0][1], b[0][0]], [b[1][1], b[1][0]]];

        if (!v.verifyProof(a, bFixed, c, signals)) revert InvalidProof();

        // CEI: mark nullifier used before any token operation
        usedNullifiers[nullifierHash] = true;
        delete commitments[commitmentHash];

        if (isMint) {
            TOKEN.mint(recipient, amount);
        } else {
            TOKEN.safeTransferFrom(recipient, address(this), amount);
            TOKEN.burn(amount);
        }
        emit NoteWithdrawn(nullifierHash, recipient, amount);
    }
}
