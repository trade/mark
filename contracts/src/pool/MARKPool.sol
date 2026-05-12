// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ICreditLedger} from "../interfaces/ICreditLedger.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";
import {ProofUtils} from "../crypto/ProofUtils.sol";
import {MerkleTree} from "../crypto/MerkleTree.sol";
import {PoolFeePolicy} from "./PoolFeePolicy.sol";
import {PoolPublicInputs} from "./PoolPublicInputs.sol";
import {PoolValidation} from "./PoolValidation.sol";
import {PoolErrors} from "./errors/PoolErrors.sol";

/// @title MARKPool
/// @notice ZK UTXO pool for private RYLA transfers with Merkle tree membership proofs.
/// @dev Withdrawal flow (burn-to-claim model):
///      Notes enter the pool via transact() or bridgeIn() — both require a valid ZK proof
///      or restricted access respectively. Notes do NOT deposit tokens into the pool;
///      the pool is a nullifier registry backed by a Merkle tree.
///
///      To withdraw RYLA, a note owner calls transactWithWithdrawBinding(), which:
///        1. Verifies the ZK proof (Merkle membership + balance equation)
///        2. Marks nullifiers as spent (prevents double-spend)
///        3. Records a withdraw binding: hash(owner, recipient, amount) per nullifier
///        4. Does NOT transfer any tokens
///
///      The note owner then calls MARKWithdrawAdapter.withdrawWithSig(), which:
///        1. Verifies the withdraw binding matches the pool's recorded binding
///        2. Verifies owner + intent signer signatures (EIP-712)
///        3. Calls RYLACreditLedger.debit(owner, amount) — burns RYLA from owner
///
///      The owner must hold RYLA tokens equal to the withdrawal amount and approve
///      RYLACreditLedger before calling withdrawWithSig. The ZK proof proves the owner
///      controls the note; the RYLA burn proves they are redeeming it.
///
///      Relayer fees are credited via ASSET_LEDGER.credit(relayer, fee) during transact().
///      ASSET_LEDGER must be set via setAssetLedger() after deployment.
contract MARKPool is ReentrancyGuard, AccessManaged, Pausable, PoolErrors {
    using MerkleTree for MerkleTree.Tree;

    struct VerifyContext {
        bytes32 merkleRoot;
        uint256 dstChainId;
        uint256 protocolEpoch;
        uint256 fee;
        address relayer;
        address withdrawOwner;
        address withdrawRecipient;
        uint256 withdrawAmount;
    }

    uint8 public constant PROOF_TYPE_TRANSFER = 1;
    bytes32 public constant WITHDRAW_BINDING_DOMAIN = keccak256("MARKPool.WithdrawBinding.v1");
    uint256 public constant MAX_ALLOWED_ROOT_AGE = 30 days;
    uint256 public constant MAX_FEE_BURN_BPS = 10_000;
    uint256 public constant MAX_MIN_FEE = type(uint64).max;

    ICreditLedger public ASSET_LEDGER;
    bool public withdrawalsPaused;
    uint256 public maxRootAge;
    uint256 public feeBurnBps;
    uint256 public minFee;
    uint256 public protocolEpoch;
    address public bridgeOutEntrypoint;

    MerkleTree.Tree private tree;
    mapping(uint8 => address) private verifiers;
    mapping(uint8 => bool) public proofTypeEnabled;
    mapping(bytes32 => bool) private usedNullifiersGlobal;
    mapping(bytes32 => bytes32) public nullifierWithdrawBinding;
    mapping(bytes32 => bool) public knownRoots;
    mapping(bytes32 => uint256) public rootTimestamps;
    mapping(uint256 => bytes32) private rootQueue;
    uint256 public rootQueueHead;
    uint256 public rootQueueTail;

    event WithdrawalsPaused(address indexed account);
    event WithdrawalsUnpaused(address indexed account);
    event VerifierSet(uint8 indexed proofType, address indexed verifier);
    event ProofTypeEnabled(uint8 indexed proofType, bool enabled);
    event RootAdded(bytes32 indexed root);
    event MaxRootAgeSet(uint256 maxRootAge);
    event FeeBurnBpsSet(uint256 feeBurnBps);
    event MinFeeSet(uint256 minFee);
    event ProtocolEpochSet(uint256 previousProtocolEpoch, uint256 newProtocolEpoch);
    event NoteSpent(bytes32 indexed nullifier);
    event WithdrawBindingRecorded(
        bytes32 indexed nullifier,
        bytes32 indexed bindingHash,
        address indexed owner,
        address recipient,
        uint256 amount
    );
    event NoteCreated(bytes32 indexed commitment);
    event FeePaid(address indexed relayer, uint256 fee);
    event FeeBurned(uint256 amount);
    event AssetLedgerSet(address indexed assetLedger);
    event BridgeOutEntrypointSet(address indexed entrypoint);
    event RootPruned(bytes32 indexed root);
    event BridgeOut(
        uint256 indexed dstChainId,
        bytes32 indexed commitment0,
        bytes32 indexed commitment1,
        uint256 fee,
        address relayer
    );
    event BridgeIn(
        uint256 indexed srcChainId,
        bytes32 indexed commitment0,
        bytes32 indexed commitment1
    );

    constructor(address initialAuthority, address _verifier)
        AccessManaged(initialAuthority)
    {
        if (_verifier == address(0)) revert InvalidVerifier();
        if (_verifier.code.length == 0) revert VerifierMustBeContract();

        verifiers[PROOF_TYPE_TRANSFER] = _verifier;
        proofTypeEnabled[PROOF_TYPE_TRANSFER] = true;

        tree.init(20);
        bytes32 initialRoot = tree.getRoot();
        knownRoots[initialRoot] = true;
        rootTimestamps[initialRoot] = block.timestamp;
        rootQueue[0] = initialRoot;
        rootQueueHead = 0;
        rootQueueTail = 1;

        emit VerifierSet(PROOF_TYPE_TRANSFER, _verifier);
        emit ProofTypeEnabled(PROOF_TYPE_TRANSFER, true);
        emit RootAdded(initialRoot);
    }

    modifier whenWithdrawalsNotPaused() {
        if (withdrawalsPaused) revert WithdrawalsArePaused();
        _;
    }

    function pause() external restricted {
        if (paused()) revert AlreadyPaused();
        _pause();
        if (!withdrawalsPaused) {
            withdrawalsPaused = true;
            emit WithdrawalsPaused(msg.sender);
        }
    }

    function unpause() external restricted {
        if (!paused()) revert NotPaused();
        _unpause();
    }

    function pauseWithdrawals() external restricted {
        if (withdrawalsPaused) revert WithdrawalsAlreadyPaused();
        withdrawalsPaused = true;
        emit WithdrawalsPaused(msg.sender);
    }

    function unpauseWithdrawals() external restricted {
        if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused(msg.sender);
    }

    function verifier() external view returns (address) {
        return verifiers[PROOF_TYPE_TRANSFER];
    }

    function verifierForType(uint8 proofType) external view returns (address) {
        return verifiers[proofType];
    }

    function setVerifier(uint8 proofType, address verifierAddr) external restricted {
        if (proofType == 0) revert InvalidProofType();
        if (verifierAddr == address(0)) revert InvalidVerifier();
        if (verifierAddr.code.length == 0) revert VerifierMustBeContract();
        if (verifiers[proofType] == verifierAddr) revert NoStateChange();
        if (proofTypeEnabled[proofType] && !withdrawalsPaused) revert WithdrawalsNotPaused();
        verifiers[proofType] = verifierAddr;
        emit VerifierSet(proofType, verifierAddr);
    }

    function setProofTypeEnabled(uint8 proofType, bool enabled) external restricted {
        if (proofType == 0) revert InvalidProofType();
        if (proofTypeEnabled[proofType] == enabled) revert NoStateChange();
        if (enabled) {
            if (verifiers[proofType] == address(0)) revert VerifierNotConfigured();
            if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        }
        proofTypeEnabled[proofType] = enabled;
        emit ProofTypeEnabled(proofType, enabled);
    }

    function emergencyDisableProofType(uint8 proofType) external restricted {
        if (proofType == 0) revert InvalidProofType();
        proofTypeEnabled[proofType] = false;
        emit ProofTypeEnabled(proofType, false);
    }

    function setMaxRootAge(uint256 newMaxRootAge) external restricted {
        if (newMaxRootAge > MAX_ALLOWED_ROOT_AGE) revert RootAgeTooLarge();
        if (newMaxRootAge == maxRootAge) revert NoStateChange();
        bool tightening = (maxRootAge == 0 && newMaxRootAge != 0)
            || (maxRootAge != 0 && newMaxRootAge != 0 && newMaxRootAge < maxRootAge);
        if (tightening && !withdrawalsPaused) revert WithdrawalsNotPaused();
        maxRootAge = newMaxRootAge;
        emit MaxRootAgeSet(newMaxRootAge);
    }

    function setFeeBurnBps(uint256 newFeeBurnBps) external restricted {
        if (newFeeBurnBps > MAX_FEE_BURN_BPS) revert InvalidBurnBps();
        if (newFeeBurnBps == feeBurnBps) revert NoStateChange();
        feeBurnBps = newFeeBurnBps;
        emit FeeBurnBpsSet(newFeeBurnBps);
    }

    function setMinFee(uint256 newMinFee) external restricted {
        // Circuit enforces percentage fee; runtime floor is a narrow safety guard only.
        // Allowed values are intentionally constrained to 0/1 credit unit.
        if (newMinFee > 1) revert FixedFeePolicy();
        if (newMinFee != minFee) {
            minFee = newMinFee;
            emit MinFeeSet(newMinFee);
        }
    }

    function setProtocolEpoch(uint256 newProtocolEpoch) external restricted {
        if (newProtocolEpoch > type(uint32).max) revert EpochExceedsCircuitRange();
        uint256 currentProtocolEpoch = protocolEpoch;
        if (newProtocolEpoch == currentProtocolEpoch) revert NoStateChange();
        if (newProtocolEpoch < currentProtocolEpoch) revert EpochCanOnlyIncrease();
        if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        protocolEpoch = newProtocolEpoch;
        emit ProtocolEpochSet(currentProtocolEpoch, newProtocolEpoch);
    }

    function setBridgeOutEntrypoint(address entrypoint) external restricted {
        if (entrypoint != address(0) && entrypoint.code.length == 0) revert EntrypointMustBeContract();
        if (entrypoint == bridgeOutEntrypoint) revert NoStateChange();
        bool tightening = (bridgeOutEntrypoint == address(0) && entrypoint != address(0))
            || (bridgeOutEntrypoint != address(0) && entrypoint != address(0) && bridgeOutEntrypoint != entrypoint);
        if (tightening && !withdrawalsPaused) revert WithdrawalsNotPaused();
        bridgeOutEntrypoint = entrypoint;
        emit BridgeOutEntrypointSet(entrypoint);
    }

    /// @notice Sets the asset ledger used for relayer fee credits. Can only be set once.
    /// @dev Separated from the constructor to break the circular dependency between
    ///      MARKPool and RYLACreditLedger (each needs the other's address at construction).
    function setAssetLedger(address ledgerAddress) external restricted {
        if (address(ASSET_LEDGER) != address(0)) revert NoStateChange();
        if (ledgerAddress == address(0)) revert InvalidAssetLedger();
        if (ledgerAddress.code.length == 0) revert AssetLedgerMustBeContract();
        ASSET_LEDGER = ICreditLedger(ledgerAddress);
        emit AssetLedgerSet(ledgerAddress);
    }

    function pruneRoots(uint256 maxToPrune) external returns (uint256 pruned) {
        return _pruneRoots(maxToPrune);
    }

    function _pruneRoots(uint256 maxToPrune) internal returns (uint256 pruned) {
        if (maxRootAge == 0 || maxToPrune == 0) return 0;
        // slither-disable-next-line timestamp
        if (block.timestamp <= maxRootAge) return 0;

        uint256 cutoff = block.timestamp - maxRootAge;
        uint256 head = rootQueueHead;
        uint256 tail = rootQueueTail;

        // Keep at least one root (the newest) to preserve transaction liveness.
        while (head + 1 < tail && pruned < maxToPrune) {
            bytes32 root = rootQueue[head];
            // slither-disable-next-line timestamp
            if (rootTimestamps[root] > cutoff) break;
            delete knownRoots[root];
            delete rootTimestamps[root];
            delete rootQueue[head];
            emit RootPruned(root);
            head++;
            pruned++;
        }

        if (head != rootQueueHead) {
            rootQueueHead = head;
        }
    }

    function getMerkleRoot() external view returns (bytes32) {
        return tree.getRoot();
    }

    function isRootUsable(bytes32 root) public view returns (bool) {
        if (!knownRoots[root]) return false;
        // Always allow the latest root so the system can advance even in low activity periods.
        if (root == tree.getRoot()) return true;
        if (maxRootAge == 0) return true;
        // slither-disable-next-line timestamp
        return block.timestamp <= rootTimestamps[root] + maxRootAge;
    }

    function isNullifierUsedGlobal(bytes32 nullifier) external view returns (bool) {
        return usedNullifiersGlobal[nullifier];
    }

    /// @notice Executes a private transfer. Permissionless — the ZK proof is the authorization.
    /// @dev Any caller may submit a valid proof. Access is gated by proof validity, not by role.
    ///      The proof binds to merkleRoot, chainId, protocolEpoch, nullifiers, and outCommitments,
    ///      preventing cross-chain, cross-epoch, and replay attacks without requiring a privileged caller.
    function transact(
        bytes32 merkleRoot,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        uint256[2] calldata a,
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) external nonReentrant whenNotPaused whenWithdrawalsNotPaused {
        _verifyAndConsume(merkleRoot, block.chainid, nullifiers, outCommitments, fee, relayer, address(0), address(0), 0, a, bSnarkjs, c);
        _insertCommitmentsValidated(outCommitments);
        _applyFee(fee, relayer);
    }

    /// @notice Executes a private transfer with a withdraw binding. Permissionless — the ZK proof is the authorization.
    /// @dev Identical access model to transact. The withdraw binding additionally commits the proof
    ///      to a specific (withdrawOwner, withdrawRecipient, withdrawAmount) tuple, enabling
    ///      the WithdrawAdapter to claim the output without a second ZK proof.
    function transactWithWithdrawBinding(
        bytes32 merkleRoot,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount,
        uint256[2] calldata a,
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) external nonReentrant whenNotPaused whenWithdrawalsNotPaused {
        if (withdrawAmount == 0) revert InvalidWithdrawAmount();
        _verifyAndConsume(merkleRoot, block.chainid, nullifiers, outCommitments, fee, relayer, withdrawOwner, withdrawRecipient, withdrawAmount, a, bSnarkjs, c);
        _insertCommitmentsValidated(outCommitments);
        _applyFee(fee, relayer);
        _recordWithdrawBinding(nullifiers, withdrawOwner, withdrawRecipient, withdrawAmount);
    }

    /// @notice Initiates a cross-chain transfer. Restricted to the configured bridgeOutEntrypoint.
    /// @dev The proof binds to dstChainId instead of block.chainid, committing the output notes
    ///      to the destination chain. Only the bridgeOutEntrypoint may call this — not permissionless.
    function bridgeOut(
        bytes32 merkleRoot,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        uint256 dstChainId,
        uint256[2] calldata a,
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) external nonReentrant whenNotPaused whenWithdrawalsNotPaused {
        address configuredEntrypoint = bridgeOutEntrypoint;
        if (configuredEntrypoint == address(0)) revert BridgeOutDisabled();
        if (msg.sender != configuredEntrypoint) revert UnauthorizedBridgeOutCaller();
        if (dstChainId == 0) revert InvalidDestination();
        if (dstChainId == block.chainid) revert DestinationIsSource();
        _verifyAndConsume(merkleRoot, dstChainId, nullifiers, outCommitments, fee, relayer, address(0), address(0), 0, a, bSnarkjs, c);
        _applyFee(fee, relayer);
        emit BridgeOut(dstChainId, outCommitments[0], outCommitments[1], fee, relayer);
    }

    /// @notice Inserts incoming cross-chain commitments into the Merkle tree. Restricted.
    /// @dev Called by the bridge relay after a bridgeOut on the source chain is confirmed.
    ///      Restricted to prevent unauthorized note insertion.
    function bridgeIn(uint256 srcChainId, bytes32[2] calldata outCommitments)
        external
        restricted
        whenNotPaused
    {
        if (srcChainId == 0) revert InvalidSource();
        if (srcChainId == block.chainid) revert SourceIsDestination();
        _insertCommitments(outCommitments);
        emit BridgeIn(srcChainId, outCommitments[0], outCommitments[1]);
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
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) internal {
        VerifyContext memory ctx = VerifyContext({
            merkleRoot: merkleRoot,
            dstChainId: dstChainId,
            protocolEpoch: protocolEpoch,
            fee: fee,
            relayer: relayer,
            withdrawOwner: withdrawOwner,
            withdrawRecipient: withdrawRecipient,
            withdrawAmount: withdrawAmount
        });

        PoolValidation.requireDestEpochAndFeeWithinCircuitRange(ctx.dstChainId, ctx.protocolEpoch, ctx.fee);
        PoolValidation.requireWithdrawBindingWithinCircuitRange(ctx.withdrawOwner, ctx.withdrawRecipient, ctx.withdrawAmount);
        PoolValidation.requireRootWithinCircuitRange(ctx.merkleRoot);
        if (!proofTypeEnabled[PROOF_TYPE_TRANSFER]) revert ProofTypeDisabled();
        if (!knownRoots[ctx.merkleRoot]) revert UnknownRoot();
        if (!isRootUsable(ctx.merkleRoot)) revert RootExpired();
        if (ctx.fee < minFee) revert FeeTooLow();

        address verifierAddr = verifiers[PROOF_TYPE_TRANSFER];
        if (verifierAddr == address(0)) revert VerifierNotConfigured();
        if (verifierAddr.code.length == 0) revert VerifierMustBeContract();

        PoolValidation.requireNullifiersFresh(nullifiers, usedNullifiersGlobal);
        _requireCommitmentsValid(outCommitments);

        uint256[13] memory publicInputs = _buildPublicInputs(ctx, nullifiers, outCommitments);
        if (!_verifyProof(IVerifier(verifierAddr), publicInputs, a, bSnarkjs, c)) revert InvalidProof();

        for (uint256 i = 0; i < nullifiers.length; i++) {
            usedNullifiersGlobal[nullifiers[i]] = true;
            emit NoteSpent(nullifiers[i]);
        }
    }

    function _insertCommitments(bytes32[2] calldata outCommitments) internal {
        _requireCommitmentsValid(outCommitments);
        _insertCommitmentsValidated(outCommitments);
    }

    function _insertCommitmentsValidated(bytes32[2] calldata outCommitments) internal {
        uint256 tail = rootQueueTail;
        for (uint256 i = 0; i < outCommitments.length; i++) {
            tree.insert(outCommitments[i]);
            bytes32 newRoot = tree.getRoot();
            knownRoots[newRoot] = true;
            rootTimestamps[newRoot] = block.timestamp;
            rootQueue[tail] = newRoot;
            tail++;
            emit NoteCreated(outCommitments[i]);
            emit RootAdded(newRoot);
        }
        if (tail != rootQueueTail) {
            rootQueueTail = tail;
        }
    }

    function _requireCommitmentsValid(bytes32[2] calldata outCommitments) internal pure {
        PoolValidation.requireCommitmentsValid(outCommitments);
    }

    function _applyFee(uint256 fee, address relayer) internal {
        if (fee == 0) return;
        (uint256 burnAmount, uint256 relayerAmount) = PoolFeePolicy.split(fee, feeBurnBps, MAX_FEE_BURN_BPS);
        // "Burn" is applied by withholding mint; total supply increases only by relayerAmount.
        if (relayerAmount > 0) {
            if (relayer == address(0)) revert InvalidRelayer();
            ASSET_LEDGER.credit(relayer, relayerAmount);
            emit FeePaid(relayer, relayerAmount);
        }
        if (burnAmount > 0) {
            emit FeeBurned(burnAmount);
        }
    }

    function _verifyProof(
        IVerifier selectedVerifier,
        uint256[13] memory publicInputs,
        uint256[2] memory a,
        uint256[2][2] memory bSnarkjs,
        uint256[2] memory c
    ) internal view returns (bool) {
        uint256[2][2] memory bFixed = ProofUtils.convertProof(bSnarkjs);
        return selectedVerifier.verifyProof(a, bFixed, c, publicInputs);
    }

    function _buildPublicInputs(
        VerifyContext memory ctx,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments
    ) internal view returns (uint256[13] memory publicInputs) {
        return computePublicInputsWithWithdraw(
            nullifiers, outCommitments, ctx.merkleRoot, ctx.dstChainId,
            ctx.protocolEpoch, ctx.fee, ctx.relayer,
            ctx.withdrawOwner, ctx.withdrawRecipient, ctx.withdrawAmount
        );
    }

    function computeWithdrawBindingHash(address owner, address recipient, uint256 amount)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAW_BINDING_DOMAIN, address(this), block.chainid, owner, recipient, amount));
    }

    function _recordWithdrawBinding(
        bytes32[2] calldata nullifiers,
        address owner,
        address recipient,
        uint256 amount
    ) internal {
        bytes32 bindingHash = computeWithdrawBindingHash(owner, recipient, amount);
        for (uint256 i = 0; i < nullifiers.length; i++) {
            if (nullifierWithdrawBinding[nullifiers[i]] != bytes32(0)) revert WithdrawBindingExists();
            nullifierWithdrawBinding[nullifiers[i]] = bindingHash;
            emit WithdrawBindingRecorded(nullifiers[i], bindingHash, owner, recipient, amount);
        }
    }

    function _seedRoot(bytes32 root) internal {
        if (root == bytes32(0)) revert InvalidRoot();
        if (knownRoots[root]) revert RootAlreadyKnown();
        uint256 tail = rootQueueTail;
        knownRoots[root] = true;
        rootTimestamps[root] = block.timestamp;
        rootQueue[tail] = root;
        rootQueueTail = tail + 1;
        emit RootAdded(root);
    }

    function computePublicInputs(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 dstChainId,
        uint256 protocolEpoch_,
        uint256 fee,
        address relayer
    ) public view returns (uint256[13] memory publicInputs) {
        return computePublicInputsWithWithdraw(nullifiers, outCommitments, merkleRoot, dstChainId, protocolEpoch_, fee, relayer, address(0), address(0), 0);
    }

    function computePublicInputsWithWithdraw(
        bytes32[2] memory nullifiers,
        bytes32[2] memory outCommitments,
        bytes32 merkleRoot,
        uint256 dstChainId,
        uint256 protocolEpoch_,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount
    ) public view returns (uint256[13] memory publicInputs) {
        return PoolPublicInputs.build(
            nullifiers, outCommitments, merkleRoot, block.chainid, dstChainId,
            protocolEpoch_, fee, relayer, withdrawOwner, withdrawRecipient, withdrawAmount
        );
    }
}
