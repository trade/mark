// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRYLA} from "../interfaces/IRYLA.sol";
import {IUTXOVerifier} from "./interfaces/IUTXOVerifier.sol";
import {MerkleTree} from "./crypto/MerkleTree.sol";
import {PoolErrors} from "./errors/PoolErrors.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title MARKPool
/// @notice ZK UTXO pool for shielded RYLA transfers.
/// @dev Holds MINTER_ROLE and BURNER_ROLE on RYLA. Deposit mints RYLA into the pool.
///      Withdraw burns pool RYLA and mints to the recipient.
///      Shielded transfers (transact) move value between notes without touching supply.
///      Withdrawal binding lets a note owner pre-commit a withdrawal destination before
///      the operator processes it, preventing operator-controlled fund redirection.
contract MARKPool is ReentrancyGuard, AccessControlDefaultAdminRules, PoolErrors {
    using MerkleTree for MerkleTree.Tree;
    using SafeERC20 for IRYLA;

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev BN254 scalar field size — all public inputs must be strictly less than this.
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 public constant MAX_ROOT_AGE = 30 days;
    uint256 public constant MAX_FEE_BURN_BPS = 10_000;

    /// @dev Domain separator for withdrawal binding hashes.
    bytes32 public constant WITHDRAW_BINDING_DOMAIN =
        keccak256("MARKPool.WithdrawBinding.v1");

    event VerifierSet(address indexed verifier);
    event ProtocolEpochSet(uint256 previousEpoch, uint256 newEpoch);
    event FeeBurnBpsSet(uint256 feeBurnBps);
    event ProductionModeActivated(address indexed admin);
    event NoteCreated(bytes32 indexed commitment);
    event RootAdded(bytes32 indexed root);
    event NoteSpent(bytes32 indexed nullifier);
    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);
    event FeePaid(address indexed relayer, uint256 relayerAmount);
    event FeeBurned(uint256 burnAmount);
    event WithdrawBindingRecorded(
        bytes32 indexed nullifier,
        bytes32 indexed bindingHash,
        address indexed owner,
        address recipient,
        uint256 amount
    );

    IRYLA public immutable TOKEN;

    IUTXOVerifier public verifier;
    bool public productionMode;
    uint256 public protocolEpoch;
    uint256 public feeBurnBps;

    MerkleTree.Tree private _tree;
    mapping(bytes32 => bool) public usedNullifiers;
    mapping(bytes32 => bool) public knownRoots;
    mapping(bytes32 => uint256) public rootTimestamps;
    mapping(bytes32 => bytes32) public nullifierWithdrawBinding;

    constructor(address initialAdmin, address token)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (token == address(0)) revert ZeroAddress();
        TOKEN = IRYLA(token);

        _tree.init(20);
        bytes32 initialRoot = _tree.getRoot();
        knownRoots[initialRoot] = true;
        rootTimestamps[initialRoot] = block.timestamp;
        emit RootAdded(initialRoot);
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

    /// @notice Bumps the protocol epoch, invalidating all outstanding proofs.
    /// @dev Requires withdrawals to be paused (productionMode not yet active) or admin override.
    function setProtocolEpoch(uint256 newEpoch) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEpoch > type(uint32).max) revert EpochExceedsCircuitRange();
        if (newEpoch <= protocolEpoch) revert EpochCanOnlyIncrease();
        uint256 prev = protocolEpoch;
        protocolEpoch = newEpoch;
        emit ProtocolEpochSet(prev, newEpoch);
    }

    function setFeeBurnBps(uint256 newFeeBurnBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeeBurnBps > MAX_FEE_BURN_BPS) revert InputExceedsCircuitRange();
        feeBurnBps = newFeeBurnBps;
        emit FeeBurnBpsSet(newFeeBurnBps);
    }

    function setOperator(address operator, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (operator == address(0)) revert ZeroAddress();
        if (enabled) _grantRole(OPERATOR_ROLE, operator);
        else _revokeRole(OPERATOR_ROLE, operator);
    }

    // Pool operations

    /// @notice Deposits RYLA into the pool, creating a shielded note.
    /// @dev Caller must have approved this contract for `amount` RYLA.
    ///      The commitment encodes the note value and is inserted into the Merkle tree.
    function deposit(address depositor, uint256 amount, bytes32 commitment)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (depositor == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        _requireCommitmentValid(commitment);

        TOKEN.safeTransferFrom(depositor, address(this), amount);
        TOKEN.burn(amount);
        _insertCommitment(commitment);
        emit Deposited(depositor, amount);
    }

    struct TransactParams {
        bytes32 merkleRoot;
        bytes32[2] nullifiers;
        bytes32[2] outCommitments;
        uint256 fee;
        address relayer;
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    struct WithdrawBindingParams {
        address withdrawOwner;
        address withdrawRecipient;
        uint256 withdrawAmount;
    }

    /// @notice Shielded transfer — spends 2 input notes, creates 2 output notes.
    function transact(TransactParams calldata p) external nonReentrant {
        _verifyAndConsume(
            p.merkleRoot, block.chainid, p.nullifiers, p.outCommitments,
            p.fee, p.relayer, address(0), address(0), 0, p.a, p.b, p.c
        );
        _insertCommitments(p.outCommitments);
        _applyFee(p.fee, p.relayer);
    }

    /// @notice Shielded transfer with withdrawal binding.
    /// @dev Records a binding from nullifiers to (owner, recipient, amount) so the
    ///      operator cannot redirect the withdrawal to a different address.
    function transactWithWithdrawBinding(
        TransactParams calldata p,
        WithdrawBindingParams calldata w
    ) external nonReentrant {
        if (w.withdrawAmount == 0) revert InvalidWithdrawAmount();
        _verifyAndConsume(
            p.merkleRoot, block.chainid, p.nullifiers, p.outCommitments,
            p.fee, p.relayer, w.withdrawOwner, w.withdrawRecipient, w.withdrawAmount,
            p.a, p.b, p.c
        );
        _insertCommitments(p.outCommitments);
        _applyFee(p.fee, p.relayer);
        _recordWithdrawBinding(p.nullifiers, w.withdrawOwner, w.withdrawRecipient, w.withdrawAmount);
    }

    /// @notice Withdraws RYLA from the pool to a recipient, consuming a withdraw binding.
    function withdraw(
        bytes32 nullifier,
        address owner,
        address recipient,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        bytes32 expected = computeWithdrawBindingHash(owner, recipient, amount);
        bytes32 recorded = nullifierWithdrawBinding[nullifier];
        if (recorded == bytes32(0)) revert WithdrawBindingNotFound();
        if (recorded != expected) revert WithdrawBindingMismatch();

        // Clear binding before mint (CEI)
        delete nullifierWithdrawBinding[nullifier];

        TOKEN.mint(recipient, amount);
        emit Withdrawn(recipient, amount);
    }

    // Views

    function getMerkleRoot() external view returns (bytes32) {
        return _tree.getRoot();
    }

    function isRootUsable(bytes32 root) public view returns (bool) {
        if (!knownRoots[root]) return false;
        uint256 ts = rootTimestamps[root];
        return ts != 0 && block.timestamp - ts <= MAX_ROOT_AGE;
    }

    function computeWithdrawBindingHash(address owner, address recipient, uint256 amount)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAW_BINDING_DOMAIN, address(this), block.chainid, owner, recipient, amount));
    }

    // Internal

    struct TransactContext {
        bytes32 merkleRoot;
        uint256 dstChainId;
        uint256 fee;
        address relayer;
        address withdrawOwner;
        address withdrawRecipient;
        uint256 withdrawAmount;
    }

    function _verifyAndConsume(
        bytes32 merkleRoot,
        uint256 dstChainId,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c
    ) internal {
        TransactContext memory ctx = TransactContext({
            merkleRoot: merkleRoot,
            dstChainId: dstChainId,
            fee: fee,
            relayer: relayer,
            withdrawOwner: withdrawOwner,
            withdrawRecipient: withdrawRecipient,
            withdrawAmount: withdrawAmount
        });

        _validateContext(ctx);
        _requireNullifiersFresh(nullifiers);
        _requireCommitmentsValid(outCommitments);
        _verifyProof(ctx, nullifiers, outCommitments, a, b, c);

        for (uint256 i = 0; i < 2; i++) {
            usedNullifiers[nullifiers[i]] = true;
            emit NoteSpent(nullifiers[i]);
        }
    }

    function _validateContext(TransactContext memory ctx) internal view {
        if (ctx.dstChainId > type(uint64).max) revert InputExceedsCircuitRange();
        if (protocolEpoch > type(uint32).max) revert EpochExceedsCircuitRange();
        if (ctx.fee > type(uint64).max) revert InputExceedsCircuitRange();
        if (ctx.withdrawAmount > type(uint64).max) revert InputExceedsCircuitRange();
        if (uint256(ctx.merkleRoot) >= SNARK_SCALAR_FIELD) revert InputExceedsCircuitRange();
        if (ctx.withdrawAmount == 0) {
            if (ctx.withdrawOwner != address(0)) revert InvalidWithdrawOwner();
            if (ctx.withdrawRecipient != address(0)) revert InvalidWithdrawRecipient();
        } else {
            if (ctx.withdrawOwner == address(0)) revert InvalidWithdrawOwner();
            if (ctx.withdrawRecipient == address(0)) revert InvalidWithdrawRecipient();
        }
        if (!knownRoots[ctx.merkleRoot]) revert UnknownRoot();
        if (!isRootUsable(ctx.merkleRoot)) revert RootExpired();
        if (address(verifier) == address(0)) revert VerifierRequired();
    }

    function _verifyProof(
        TransactContext memory ctx,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c
    ) internal view {
        uint256[13] memory inputs;
        // Build in two steps to stay within stack depth limit.
        _fillBaseInputs(inputs, ctx, nullifiers, outCommitments);
        inputs[10] = uint256(uint160(ctx.withdrawOwner));
        inputs[11] = uint256(uint160(ctx.withdrawRecipient));
        inputs[12] = ctx.withdrawAmount;
        // G2 coordinate swap: snarkjs uses (x[1],x[0]) order, verifier expects (x[0],x[1])
        uint256[2][2] memory bFixed = [[b[0][1], b[0][0]], [b[1][1], b[1][0]]];
        if (!verifier.verifyProof(a, bFixed, c, inputs)) revert InvalidProof();
    }

    function _fillBaseInputs(
        uint256[13] memory inputs,
        TransactContext memory ctx,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments
    ) internal view {
        inputs[0] = uint256(ctx.merkleRoot);
        inputs[1] = block.chainid;
        inputs[2] = ctx.dstChainId;
        inputs[3] = protocolEpoch;
        inputs[4] = ctx.fee;
        inputs[5] = uint256(uint160(ctx.relayer));
        inputs[6] = uint256(nullifiers[0]);
        inputs[7] = uint256(nullifiers[1]);
        inputs[8] = uint256(outCommitments[0]);
        inputs[9] = uint256(outCommitments[1]);
    }

    function _insertCommitments(bytes32[2] calldata commitments) internal {
        _requireCommitmentsValid(commitments);
        for (uint256 i = 0; i < 2; i++) {
            _insertCommitment(commitments[i]);
        }
    }

    function _insertCommitment(bytes32 commitment) internal {
        _tree.insert(commitment);
        bytes32 newRoot = _tree.getRoot();
        knownRoots[newRoot] = true;
        rootTimestamps[newRoot] = block.timestamp;
        emit NoteCreated(commitment);
        emit RootAdded(newRoot);
    }

    function _applyFee(uint256 fee, address relayer) internal {
        if (fee == 0) return;
        uint256 burnAmount = fee * feeBurnBps / MAX_FEE_BURN_BPS;
        uint256 relayerAmount = fee - burnAmount;
        if (relayerAmount > 0) {
            if (relayer == address(0)) revert InvalidRelayer();
            TOKEN.mint(relayer, relayerAmount);
            emit FeePaid(relayer, relayerAmount);
        }
        if (burnAmount > 0) emit FeeBurned(burnAmount);
    }

    function _recordWithdrawBinding(
        bytes32[2] calldata nullifiers,
        address owner,
        address recipient,
        uint256 amount
    ) internal {
        bytes32 bindingHash = computeWithdrawBindingHash(owner, recipient, amount);
        for (uint256 i = 0; i < 2; i++) {
            if (nullifierWithdrawBinding[nullifiers[i]] != bytes32(0)) revert WithdrawBindingExists();
            nullifierWithdrawBinding[nullifiers[i]] = bindingHash;
            emit WithdrawBindingRecorded(nullifiers[i], bindingHash, owner, recipient, amount);
        }
    }

    function _requireNullifiersFresh(bytes32[2] calldata nullifiers) internal view {
        if (nullifiers[0] == bytes32(0) || nullifiers[1] == bytes32(0)) revert NullifierInvalid();
        if (uint256(nullifiers[0]) >= SNARK_SCALAR_FIELD) revert NullifierInvalid();
        if (uint256(nullifiers[1]) >= SNARK_SCALAR_FIELD) revert NullifierInvalid();
        if (nullifiers[0] == nullifiers[1]) revert NullifierDuplicate();
        if (usedNullifiers[nullifiers[0]]) revert NullifierUsed();
        if (usedNullifiers[nullifiers[1]]) revert NullifierUsed();
    }

    function _requireCommitmentsValid(bytes32[2] calldata commitments) internal pure {
        if (commitments[0] == bytes32(0) || commitments[1] == bytes32(0)) revert CommitmentInvalid();
        if (uint256(commitments[0]) >= SNARK_SCALAR_FIELD) revert CommitmentInvalid();
        if (uint256(commitments[1]) >= SNARK_SCALAR_FIELD) revert CommitmentInvalid();
        if (commitments[0] == commitments[1]) revert CommitmentDuplicate();
    }

    function _requireCommitmentValid(bytes32 commitment) internal pure {
        if (commitment == bytes32(0)) revert CommitmentInvalid();
        if (uint256(commitment) >= SNARK_SCALAR_FIELD) revert CommitmentInvalid();
    }
}
