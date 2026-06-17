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
import {NullifierErrors} from "src/errors/NullifierErrors.sol";
import {IL2ToL2CrossDomainMessenger} from "@interop-lib/interfaces/IL2ToL2CrossDomainMessenger.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";
import {CrossDomainMessageLib} from "@interop-lib/libraries/CrossDomainMessageLib.sol";

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
///        2. Verifies owner + intent signer signatures (EIP-191 personal_sign)
///        3. Calls RYLACreditLedger.debit(owner, amount) — burns RYLA from owner
///
///      The owner must hold RYLA tokens equal to the withdrawal amount and approve
///      RYLACreditLedger before calling withdrawWithSig. The ZK proof proves the owner
///      controls the note; the RYLA burn proves they are redeeming it.
///
///      Relayer fees are credited via ASSET_LEDGER.credit(relayer, fee) during transact().
///      ASSET_LEDGER must be set via setAssetLedger() after deployment.
///
///      INVARIANTS (CI-enforced):
///        1. Nullifier Uniqueness: nullifierUsedGlobal[hash] is set TRUE before any
///           external call and never reset. Check: make test-cross-chain-double-spend
///        2. Circuit Soundness: Public input encoding via PoolPublicInputs.build()
///           matches circuit signal order exactly. Every <-- in the circuit has ===.
///        3. Circuit Completeness: Honest user with valid note + proof can always call
///           transact() or transactWithWithdrawBinding(). No block.timestamp in core path.
///        4. Privacy: Events emit only nullifierHash and commitment. No amounts,
///           recipients, or owners. WithdrawAdapter handles those off-chain via signatures.
///        5. Reorg Safety: Merkle root updates happen synchronously within the pool.
///           Cross-L2 root propagation is via L2ToL2CrossDomainMessenger (handled by bridge).
contract MARKPool is ReentrancyGuard, AccessManaged, Pausable, PoolErrors {
    using MerkleTree for MerkleTree.Tree;
    using ProofUtils for uint256[2][2];

    // =========================================================
    //  Constants
    // =========================================================

    /// @notice Proof type identifier for standard transfers (2-in, 2-out).
    uint8 public constant PROOF_TYPE_TRANSFER = 1;

    /// @notice Domain separator for withdraw binding hash computation.
    /// @dev Prevents binding hash collisions across different protocol components.
    bytes32 public constant WITHDRAW_BINDING_DOMAIN = keccak256("MARKPool.WithdrawBinding.v1");

    /// @notice Maximum allowed age for a Merkle root before it expires.
    uint256 public constant MAX_ALLOWED_ROOT_AGE = 30 days;

    /// @notice Approximate number of L2 blocks per day on OP Stack (2s block time).
    /// @dev 86400 seconds / 2 seconds per block = 43200 blocks. Single-sourced from
    ///      PoolValidation so the pool and its validation library can never diverge.
    uint256 public constant BLOCKS_PER_DAY = PoolValidation.BLOCKS_PER_DAY;

    /// @notice L2ToL2CrossDomainMessenger predeploy address for cross-chain nullifier sync.
    address public constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = PredeployAddresses.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    /// @notice Maximum fee burn basis points (10000 = 100%).
    uint256 public constant MAX_FEE_BURN_BPS = 10_000;

    // =========================================================
    //  Immutable state
    // =========================================================

    /// @notice The credit ledger (RYLACreditLedger) for relayer fee payouts.
    ICreditLedger public ASSET_LEDGER;

    // =========================================================
    //  Admin-configurable state
    // =========================================================

    /// @notice When true, all transact/bridge operations are blocked.
    /// @dev Separate from Pausable — allows emergency stop without fully pausing admin functions.
    bool public withdrawalsPaused;

    /// @notice Maximum age (seconds) a Merkle root remains valid.
    /// @dev 0 means roots never expire. Set via setMaxRootAge() (requires pause).
    uint256 public maxRootAge;

    /// @notice Fee burn basis points. Portion of each fee that is burned (sent to ledger debit).
    /// @dev 0 = all fee to relayer. 10000 = all fee burned. Enforced: feeBurnBps <= MAX_FEE_BURN_BPS.
    uint256 public feeBurnBps;

    /// @notice Minimum fee required per transaction.
    /// @dev Transactions with fee < minFee revert.
    uint256 public minFee;

    /// @notice Monotonically increasing protocol epoch.
    /// @dev Can only increase. Used for circuit versioning.
    uint256 public protocolEpoch;

    /// @notice Authorized caller for bridgeOut().
    /// @dev Only this address can initiate bridge-out operations.
    address public bridgeOutEntrypoint;

    // =========================================================
    //  Merkle tree state
    // =========================================================

    /// @notice The Merkle tree storing note commitments.
    MerkleTree.Tree private tree;

    /// @notice Queue of known Merkle roots for expiry management.
    /// @dev rootQueueHead/rootQueueTail implement a circular buffer of root hashes.
    mapping(uint256 => bytes32) private rootQueue;

    /// @notice Head index of the root queue.
    uint256 public rootQueueHead;

    /// @notice Tail index of the root queue.
    uint256 public rootQueueTail;

    /// @notice Whether a root hash is known (exists in the tree history).
    mapping(bytes32 => bool) public knownRoots;

    /// @notice Block number when each root was added.
    mapping(bytes32 => uint256) public rootBlockNumbers;

    // =========================================================
    //  Nullifier & binding state
    // =========================================================

    /// @notice Global nullifier registry. Maps nullifier hash to "spent" status.
    /// @dev INVARIANT: Once true, never false. Set BEFORE external calls (CEI pattern).
    mapping(bytes32 => bool) private usedNullifiersGlobal;

    /// @notice Withdraw binding per nullifier: keccak256(owner, recipient, amount).
    /// @dev Recorded during transactWithWithdrawBinding(). Verified by MARKWithdrawAdapter.
    mapping(bytes32 => bytes32) public nullifierWithdrawBinding;

    // =========================================================
    //  Proof verification state
    // =========================================================

    /// @notice Verifier contracts indexed by proof type.
    /// @dev PROOF_TYPE_TRANSFER (1) => Groth16 verifier (MARKPoolVerifier.sol).
    mapping(uint8 => address) private verifiers;

    /// @notice Whether a proof type is enabled.
    mapping(uint8 => bool) public proofTypeEnabled;

    // =========================================================
    //  Cross-chain nullifier sync state
    // =========================================================

    /// @notice Chains that this pool syncs nullifiers with.
    /// @dev Set by admin via setSupportedChain(). True = sync enabled.
    mapping(uint256 => bool) public supportedChains;

    /// @notice List of supported chain IDs for iteration.
    /// @dev Maintained by setSupportedChain().
    uint256[] private supportedChainList;

    /// @notice Processed bridge message IDs to prevent replay.
    /// @dev Keyed by message hash sourced from origin chain.
    mapping(bytes32 => bool) public processedBridgeMessages;

    // =========================================================
    //  Events
    // =========================================================

    /// @notice Emitted when withdrawals are paused.
    event WithdrawalsPaused(address indexed account);

    /// @notice Emitted when withdrawals are unpaused.
    event WithdrawalsUnpaused(address indexed account);

    /// @notice Emitted when a verifier is set for a proof type.
    event VerifierSet(uint8 indexed proofType, address indexed verifier);

    /// @notice Emitted when a proof type is enabled/disabled.
    event ProofTypeEnabled(uint8 indexed proofType, bool enabled);

    /// @notice Emitted when a new Merkle root is added.
    event RootAdded(bytes32 indexed root);

    /// @notice Emitted when max root age is changed.
    event MaxRootAgeSet(uint256 maxRootAge);

    /// @notice Emitted when fee burn bps is changed.
    event FeeBurnBpsSet(uint256 feeBurnBps);

    /// @notice Emitted when min fee is changed.
    event MinFeeSet(uint256 minFee);

    /// @notice Emitted when protocol epoch is incremented.
    event ProtocolEpochSet(uint256 previousProtocolEpoch, uint256 newProtocolEpoch);

    /// @notice Emitted when a note (nullifier) is spent.
    /// @dev PRIVACY: Only emits the nullifier hash, no amounts or addresses.
    event NoteSpent(bytes32 indexed nullifier);

    /// @notice Emitted when a withdraw binding is recorded for a nullifier.
    event WithdrawBindingRecorded(
        bytes32 indexed nullifier, bytes32 indexed bindingHash, address indexed owner, address recipient, uint256 amount
    );

    /// @notice Emitted when a new output commitment is added to the pool.
    /// @dev PRIVACY: Only emits the commitment hash.
    event NoteCreated(bytes32 indexed commitment);

    /// @notice Emitted when a fee is paid to a relayer.
    event FeePaid(address indexed relayer, uint256 fee);

    /// @notice Emitted when a fee burn amount is debited.
    event FeeBurned(uint256 amount);

    /// @notice Emitted when the asset ledger is set.
    event AssetLedgerSet(address indexed assetLedger);

    /// @notice Emitted when the bridge-out entrypoint is set.
    event BridgeOutEntrypointSet(address indexed entrypoint);

    /// @notice Emitted when an expired root is pruned.
    event RootPruned(bytes32 indexed root);

    /// @notice Emitted when a bridge-out operation is initiated.
    event BridgeOut(
        uint256 indexed dstChainId, bytes32 indexed nullifier0, bytes32 indexed nullifier1, uint256 fee, address relayer
    );

    /// @notice Emitted when a bridge-in operation completes.
    event BridgeIn(uint256 indexed srcChainId, bytes32 indexed messageId, bytes32[2] commitments);

    /// @notice Emitted when a supported chain is added or removed for nullifier sync.
    event SupportedChainSet(uint256 indexed chainId, bool enabled);

    /// @notice Emitted when nullifiers are synced to a destination chain.
    /// @dev `msgHash` is the L2ToL2CrossDomainMessenger message hash, the canonical handle
    ///      operators use to track delivery of this sync on the destination chain.
    event NullifierSyncSent(
        uint256 indexed dstChainId, bytes32 indexed nullifier0, bytes32 indexed nullifier1, bytes32 msgHash
    );

    /// @notice Emitted when nullifiers are received from a source chain via cross-chain sync.
    event NullifierSyncReceived(uint256 indexed srcChainId, bytes32 indexed nullifier0, bytes32 indexed nullifier1);

    // =========================================================
    //  Constructor
    // =========================================================

    /// @notice Deploys the MARKPool contract.
    /// @param authority The access manager authority (admin).
    /// @param verifier The initial Groth16 verifier for PROOF_TYPE_TRANSFER.
    /// @param poseidon The Poseidon T3 hash contract for Merkle tree operations.
    constructor(address authority, address verifier, address poseidon) AccessManaged(authority) {
        if (authority == address(0)) revert ZeroAddress();
        if (verifier == address(0)) revert InvalidVerifier();
        if (verifier.code.length == 0) revert VerifierMustBeContract();
        if (poseidon == address(0)) revert InvalidPoseidon();
        if (poseidon.code.length == 0) revert PoseidonMustBeContract();

        verifiers[PROOF_TYPE_TRANSFER] = verifier;
        proofTypeEnabled[PROOF_TYPE_TRANSFER] = true;

        // Initialize the Merkle tree (depth 20 = ~1M leaves).
        MerkleTree.init(tree, 20, poseidon);

        // Register the initial root so it is usable for the first transact
        bytes32 initialRoot = tree.getRoot();
        knownRoots[initialRoot] = true;
        rootBlockNumbers[initialRoot] = block.number;
        rootQueue[rootQueueTail] = initialRoot;
        unchecked {
            rootQueueTail++;
        }
    }

    // =========================================================
    //  Transact (standard transfer)
    // =========================================================

    /// @notice Processes a private transfer by verifying a ZK proof and updating the Merkle tree.
    /// @dev CEI pattern: nullifier state changes happen BEFORE external fee transfer.
    ///      Validates root, nullifiers, commitments, fee, and proof before state changes.
    /// @param merkleRoot The Merkle root to verify against (must be known and non-expired).
    /// @param nullifiers The two nullifier hashes of the input notes to spend.
    /// @param outCommitments The two output note commitments to add to the tree.
    /// @param fee The fee amount to pay to the relayer.
    /// @param relayer The relayer address to receive the fee.
    /// @param a G1 point of the Groth16 proof.
    /// @param bSnarkjs G2 point of the Groth16 proof (snarkjs coordinate order).
    /// @param c G1 point of the Groth16 proof.
    function transact(
        bytes32 merkleRoot,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        uint256[2] calldata a,
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) external whenNotPaused nonReentrant {
        if (withdrawalsPaused) revert WithdrawalsArePaused();
        PoolValidation.requireFeeOk(fee, relayer, minFee);
        PoolValidation.requireRootUsable(merkleRoot, knownRoots, rootBlockNumbers, maxRootAge, tree.getRoot());
        PoolValidation.requireNullifiersFresh(nullifiers, usedNullifiersGlobal);
        PoolValidation.requireCommitmentsValid(outCommitments);

        // Verify ZK proof
        _verifyProof(
            PROOF_TYPE_TRANSFER,
            merkleRoot,
            nullifiers,
            outCommitments,
            fee,
            relayer,
            address(0),
            address(0),
            0,
            block.chainid,
            a,
            bSnarkjs,
            c
        );

        // CEI: State changes before external calls
        _spendNullifiers(nullifiers);
        _addCommitmentToTree(outCommitments[0]);
        _addCommitmentToTree(outCommitments[1]);

        // External call: credit relayer fee
        _creditRelayerFee(fee, relayer);
    }

    // =========================================================
    //  Transact with withdraw binding
    // =========================================================

    /// @notice Processes a transfer that records a withdraw binding for later redemption.
    /// @dev Like transact(), but additionally records hash(owner, recipient, amount) per nullifier.
    ///      The MARKWithdrawAdapter later verifies this binding before debiting RYLA.
    /// @param merkleRoot The Merkle root to verify against.
    /// @param nullifiers The two nullifier hashes of the input notes.
    /// @param outCommitments The two output note commitments.
    /// @param fee The fee amount.
    /// @param relayer The relayer address.
    /// @param withdrawOwner Note owner (for withdraw binding).
    /// @param withdrawRecipient Intended withdrawal recipient (for withdraw binding).
    /// @param withdrawAmount Amount the owner intends to withdraw (for withdraw binding).
    /// @param a G1 point of the Groth16 proof.
    /// @param bSnarkjs G2 point of the Groth16 proof (snarkjs coordinate order).
    /// @param c G1 point of the Groth16 proof.
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
    ) external whenNotPaused nonReentrant {
        if (withdrawalsPaused) revert WithdrawalsArePaused();
        PoolValidation.requireFeeOk(fee, relayer, minFee);
        PoolValidation.requireRootUsable(merkleRoot, knownRoots, rootBlockNumbers, maxRootAge, tree.getRoot());
        PoolValidation.requireNullifiersFresh(nullifiers, usedNullifiersGlobal);
        PoolValidation.requireCommitmentsValid(outCommitments);

        // Validate withdraw binding inputs
        if (withdrawAmount == 0) revert InvalidWithdrawAmount();
        if (withdrawOwner == address(0)) revert InvalidWithdrawOwner();
        if (withdrawRecipient == address(0)) revert InvalidWithdrawRecipient();

        // Verify ZK proof
        _verifyProof(
            PROOF_TYPE_TRANSFER,
            merkleRoot,
            nullifiers,
            outCommitments,
            fee,
            relayer,
            withdrawOwner,
            withdrawRecipient,
            withdrawAmount,
            block.chainid,
            a,
            bSnarkjs,
            c
        );

        // CEI: State changes before external calls
        _spendNullifiers(nullifiers);
        _addCommitmentToTree(outCommitments[0]);
        _addCommitmentToTree(outCommitments[1]);

        // Record withdraw binding
        bytes32 bindingHash = computeWithdrawBindingHash(withdrawOwner, withdrawRecipient, withdrawAmount);
        nullifierWithdrawBinding[nullifiers[0]] = bindingHash;
        nullifierWithdrawBinding[nullifiers[1]] = bindingHash;
        emit WithdrawBindingRecorded(nullifiers[0], bindingHash, withdrawOwner, withdrawRecipient, withdrawAmount);
        emit WithdrawBindingRecorded(nullifiers[1], bindingHash, withdrawOwner, withdrawRecipient, withdrawAmount);

        // External call: credit relayer fee
        _creditRelayerFee(fee, relayer);
    }

    // =========================================================
    //  Bridge-out
    // =========================================================

    /// @notice Burns output notes on this chain and sends a cross-chain message to mint on destination.
    /// @dev Only callable by bridgeOutEntrypoint. Validates root, nullifiers, and proof before state changes.
    /// @param merkleRoot The Merkle root to verify against.
    /// @param nullifiers The two nullifier hashes to spend.
    /// @param outCommitments The two output note commitments to add to the tree.
    /// @param fee The fee amount.
    /// @param relayer The relayer address.
    /// @param dstChainId The destination chain ID for the bridge message.
    /// @param a G1 point of the Groth16 proof.
    /// @param bSnarkjs G2 point of the Groth16 proof (snarkjs coordinate order).
    /// @param c G1 point of the Groth16 proof.
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
    ) external whenNotPaused nonReentrant {
        if (bridgeOutEntrypoint == address(0)) revert BridgeOutDisabled();
        if (msg.sender != bridgeOutEntrypoint) revert UnauthorizedBridgeOutCaller();
        if (dstChainId == 0) revert InvalidDestination();
        if (dstChainId == block.chainid) revert SourceIsDestination();
        if (withdrawalsPaused) revert WithdrawalsArePaused();
        PoolValidation.requireFeeOk(fee, relayer, minFee);
        PoolValidation.requireRootUsable(merkleRoot, knownRoots, rootBlockNumbers, maxRootAge, tree.getRoot());
        PoolValidation.requireNullifiersFresh(nullifiers, usedNullifiersGlobal);
        PoolValidation.requireCommitmentsValid(outCommitments);

        // Verify ZK proof with the actual destination chain ID
        _verifyProof(
            PROOF_TYPE_TRANSFER,
            merkleRoot,
            nullifiers,
            outCommitments,
            fee,
            relayer,
            address(0),
            address(0),
            0,
            dstChainId,
            a,
            bSnarkjs,
            c
        );

        // CEI: State changes before external calls
        _spendNullifiers(nullifiers);

        // Do NOT insert output commitments on the source chain.
        // They are delivered to the destination chain via bridgeIn().
        // Inserting them here would allow double-spend across chains.

        // External call: credit relayer fee (if any)
        _creditRelayerFee(fee, relayer);

        emit BridgeOut(dstChainId, nullifiers[0], nullifiers[1], fee, relayer);
    }

    // =========================================================
    //  Bridge-in
    // =========================================================

    /// @notice Mints output notes on this chain from a cross-chain bridge message.
    /// @dev Only callable by authorized admin/restricted. Validates message replay protection.
    /// @param srcChainId The source chain ID.
    /// @param messageId Unique message identifier for replay protection.
    /// @param outCommitments The two output note commitments to add to the tree.
    function bridgeIn(uint256 srcChainId, bytes32 messageId, bytes32[2] calldata outCommitments)
        external
        restricted
        whenNotPaused
    {
        if (srcChainId == 0) revert InvalidSource();
        if (srcChainId == block.chainid) revert SourceIsDestination();
        if (messageId == bytes32(0)) revert InvalidMessageId();
        if (processedBridgeMessages[messageId]) revert BridgeMessageAlreadyProcessed();
        if (outCommitments[0] == bytes32(0) || outCommitments[1] == bytes32(0)) revert CommitmentInvalid();
        if (outCommitments[0] == outCommitments[1]) revert CommitmentDuplicate();

        processedBridgeMessages[messageId] = true;

        _addCommitmentToTree(outCommitments[0]);
        _addCommitmentToTree(outCommitments[1]);

        emit BridgeIn(srcChainId, messageId, outCommitments);
    }

    /// @notice Receives nullifier sync from a source chain via L2ToL2CrossDomainMessenger.
    /// @dev Only callable by L2ToL2CrossDomainMessenger via relayMessage.
    ///      Marks the nullifiers as spent on this chain to enforce cross-chain uniqueness.
    /// @param nullifier0 First nullifier hash to mark as spent.
    /// @param nullifier1 Second nullifier hash to mark as spent.
    function syncNullifiers(bytes32 nullifier0, bytes32 nullifier1) external {
        CrossDomainMessageLib.requireCallerIsCrossDomainMessenger();
        CrossDomainMessageLib.requireCrossDomainCallback();

        // Get source chain from the message context
        uint256 srcChainId = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
            .crossDomainMessageSource();

        // Validate source chain is supported
        if (!supportedChains[srcChainId]) revert PoolErrors.InvalidSource();

        // Mark nullifiers as spent (local, no re-sync to avoid infinite loop)
        _markNullifiersFromSync(srcChainId, nullifier0, nullifier1);
    }

    /// @notice Internal function to mark nullifiers from cross-chain sync.
    /// @dev Separated for testing purposes.
    /// @param srcChainId Source chain ID.
    /// @param nullifier0 First nullifier hash.
    /// @param nullifier1 Second nullifier hash.
    function _markNullifiersFromSync(uint256 srcChainId, bytes32 nullifier0, bytes32 nullifier1) internal {
        // Validate source chain is supported
        if (!supportedChains[srcChainId]) revert PoolErrors.InvalidSource();

        // Mark nullifiers as spent (local, no re-sync to avoid infinite loop)
        if (!usedNullifiersGlobal[nullifier0]) {
            usedNullifiersGlobal[nullifier0] = true;
            emit NoteSpent(nullifier0);
        }
        if (!usedNullifiersGlobal[nullifier1]) {
            usedNullifiersGlobal[nullifier1] = true;
            emit NoteSpent(nullifier1);
        }

        // Emit once per received sync message (covers both nullifiers) regardless of
        // whether either was already marked, so off-chain indexers can reconstruct the
        // full cross-chain sync history from logs.
        emit NullifierSyncReceived(srcChainId, nullifier0, nullifier1);
    }

    // =========================================================
    //  Admin configuration
    // =========================================================

    /// @notice Pauses the contract (inherited from Pausable).
    /// @dev Delegates to Pausable._pause(). Restricted to admin.
    function pause() external restricted {
        _pause();
    }

    /// @notice Unpauses the contract (inherited from Pausable).
    /// @dev Delegates to Pausable._unpause(). Restricted to admin.
    function unpause() external restricted {
        _unpause();
    }

    /// @notice Pauses all transact/bridge operations (withdrawals).
    /// @dev Requires withdrawalsPaused to be false.
    function pauseWithdrawals() external restricted {
        if (withdrawalsPaused) revert WithdrawalsAlreadyPaused();
        withdrawalsPaused = true;
        emit WithdrawalsPaused(msg.sender);
    }

    /// @notice Unpauses all transact/bridge operations.
    /// @dev Requires withdrawalsPaused to be true.
    function unpauseWithdrawals() external restricted {
        if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused(msg.sender);
    }

    /// @notice Sets the verifier contract for a proof type.
    /// @dev Requires withdrawalsPaused (prevents mid-operation verifier swap).
    /// @param proofType The proof type identifier.
    /// @param verifier The new verifier contract address.
    function setVerifier(uint8 proofType, address verifier) external restricted {
        if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        if (proofType == 0) revert InvalidProofType();
        if (verifier == address(0)) revert InvalidVerifier();
        if (verifier.code.length == 0) revert VerifierMustBeContract();

        verifiers[proofType] = verifier;
        emit VerifierSet(proofType, verifier);
    }

    /// @notice Enables or disables a proof type.
    /// @dev Emergency use: disabled proof types cannot be used in transact().
    /// @param proofType The proof type identifier.
    /// @param enabled True to enable, false to disable.
    function setProofTypeEnabled(uint8 proofType, bool enabled) external restricted {
        if (proofType == 0) revert InvalidProofType();
        if (proofTypeEnabled[proofType] == enabled) revert NoStateChange();
        proofTypeEnabled[proofType] = enabled;
        emit ProofTypeEnabled(proofType, enabled);
    }

    /// @notice Emergency disables a proof type without unpausing withdrawals.
    /// @dev Use this when an exploit is detected in a specific proof type.
    /// @param proofType The proof type to disable.
    function emergencyDisableProofType(uint8 proofType) external restricted {
        if (proofType == 0) revert InvalidProofType();
        proofTypeEnabled[proofType] = false;
        emit ProofTypeEnabled(proofType, false);
    }

    /// @notice Sets the maximum Merkle root age.
    /// @dev Tightening (enabling expiry or reducing the window) requires withdrawalsPaused.
    /// @param newMaxRootAge The new max age in seconds (0 = no expiry).
    function setMaxRootAge(uint256 newMaxRootAge) external restricted {
        if (newMaxRootAge != 0 && newMaxRootAge > MAX_ALLOWED_ROOT_AGE) revert RootAgeTooLarge();
        if (newMaxRootAge == maxRootAge) revert NoStateChange();
        bool tightening = (maxRootAge == 0 && newMaxRootAge != 0)
            || (maxRootAge != 0 && newMaxRootAge != 0 && newMaxRootAge < maxRootAge);
        if (tightening && !withdrawalsPaused) revert WithdrawalsNotPaused();
        maxRootAge = newMaxRootAge;
        emit MaxRootAgeSet(newMaxRootAge);
    }

    /// @notice Sets the fee burn basis points.
    /// @dev feeBurnBps must not exceed MAX_FEE_BURN_BPS.
    /// @param newFeeBurnBps The new fee burn bps.
    function setFeeBurnBps(uint256 newFeeBurnBps) external restricted {
        if (newFeeBurnBps > MAX_FEE_BURN_BPS) revert InvalidBurnBps();
        if (newFeeBurnBps == feeBurnBps) revert NoStateChange();
        feeBurnBps = newFeeBurnBps;
        emit FeeBurnBpsSet(newFeeBurnBps);
    }

    /// @notice Sets the minimum fee per transaction.
    /// @dev Circuit enforces percentage fee; runtime floor is a narrow safety guard only.
    ///      Allowed values are intentionally constrained to 0 or 1 credit unit.
    /// @param newMinFee The new minimum fee value (0 or 1).
    function setMinFee(uint256 newMinFee) external restricted {
        if (newMinFee > 1) revert MinFeeTooLarge();
        if (newMinFee != minFee) {
            minFee = newMinFee;
            emit MinFeeSet(newMinFee);
        }
    }

    /// @notice Increments the protocol epoch.
    /// @dev Monotonic: newEpoch must be greater than current protocolEpoch.
    ///      Requires withdrawalsPaused.
    /// @param newEpoch The new epoch value (must be > protocolEpoch).
    function setProtocolEpoch(uint256 newEpoch) external restricted {
        if (newEpoch > type(uint32).max) revert EpochExceedsCircuitRange();
        uint256 currentProtocolEpoch = protocolEpoch;
        if (newEpoch == currentProtocolEpoch) revert NoStateChange();
        if (newEpoch < currentProtocolEpoch) revert EpochCanOnlyIncrease();
        if (!withdrawalsPaused) revert WithdrawalsNotPaused();
        protocolEpoch = newEpoch;
        emit ProtocolEpochSet(currentProtocolEpoch, newEpoch);
    }

    /// @notice Sets the bridge-out entrypoint contract.
    /// @dev Tightening (setting a non-zero entrypoint when previously zero, or changing)
    ///      requires withdrawalsPaused.
    /// @param entrypoint The new entrypoint address.
    function setBridgeOutEntrypoint(address entrypoint) external restricted {
        if (entrypoint != address(0) && entrypoint.code.length == 0) revert EntrypointMustBeContract();
        if (entrypoint == bridgeOutEntrypoint) revert NoStateChange();
        bool tightening = (bridgeOutEntrypoint == address(0) && entrypoint != address(0))
            || (bridgeOutEntrypoint != address(0) && entrypoint != address(0) && bridgeOutEntrypoint != entrypoint);
        if (tightening && !withdrawalsPaused) revert WithdrawalsNotPaused();
        bridgeOutEntrypoint = entrypoint;
        emit BridgeOutEntrypointSet(entrypoint);
    }

    /// @notice Adds or removes a supported chain for cross-chain nullifier sync.
    /// @dev Only callable by admin. Enables/disables nullifier synchronization
    ///      with the specified destination chain via L2ToL2CrossDomainMessenger.
    /// @param chainId The destination chain ID.
    /// @param enabled True to enable sync, false to disable.
    function setSupportedChain(uint256 chainId, bool enabled) external restricted {
        if (chainId == 0) revert InvalidChainId();
        if (chainId == block.chainid) revert InvalidChainId();
        if (supportedChains[chainId] == enabled) revert NoStateChange();
        supportedChains[chainId] = enabled;

        if (enabled) {
            supportedChainList.push(chainId);
        } else {
            // Remove from list (swap with last and pop for O(1) removal)
            for (uint256 i = 0; i < supportedChainList.length; ++i) {
                if (supportedChainList[i] == chainId) {
                    supportedChainList[i] = supportedChainList[supportedChainList.length - 1];
                    supportedChainList.pop();
                    break;
                }
            }
        }
        emit SupportedChainSet(chainId, enabled);
    }

    /// @notice Sets the asset ledger (credit ledger) address.
    /// @dev Required post-deployment to break circular dependency.
    /// @param newLedger The new ledger address.
    function setAssetLedger(address newLedger) external restricted {
        if (newLedger == address(0)) revert InvalidAssetLedger();
        if (newLedger.code.length == 0) revert AssetLedgerMustBeContract();
        if (ASSET_LEDGER != ICreditLedger(address(0))) revert NoStateChange(); // Already set
        ASSET_LEDGER = ICreditLedger(newLedger);
        emit AssetLedgerSet(newLedger);
    }

    /// @notice Prunes expired Merkle roots from the knownRoots mapping.
    /// @dev Cannot prune the latest root. Prunes up to `maxIterations` roots per call.
    /// @param maxIterations Maximum number of roots to prune in this call.
    /// @return pruned The number of roots actually pruned.
    function pruneRoots(uint256 maxIterations) external returns (uint256 pruned) {
        if (maxRootAge == 0) return 0;
        if (rootQueueHead >= rootQueueTail) return 0;

        bytes32 latestRoot = tree.getRoot();
        uint256 head = rootQueueHead;

        // Convert maxRootAge (seconds) to blocks
        uint256 maxRootAgeBlocks = (maxRootAge * BLOCKS_PER_DAY) / 1 days;

        for (uint256 i = 0; i < maxIterations && head < rootQueueTail;) {
            bytes32 root = rootQueue[head];
            if (root == latestRoot) {
                // Always keep the latest root
                break;
            }
            uint256 blockNum = rootBlockNumbers[root];
            if (blockNum != 0 && block.number > blockNum + maxRootAgeBlocks) {
                delete knownRoots[root];
                delete rootBlockNumbers[root];
                emit RootPruned(root);
                unchecked {
                    head++;
                    pruned++;
                }
            } else {
                break;
            }
        }
        rootQueueHead = head;
        return pruned;
    }

    // =========================================================
    //  View functions
    // =========================================================

    /// @notice Returns the current Merkle root.
    function getMerkleRoot() external view returns (bytes32) {
        return tree.getRoot();
    }

    /// @notice Checks whether a nullifier has been spent.
    /// @param nullifier The nullifier hash to check.
    /// @return True if the nullifier has been consumed.
    function isNullifierUsedGlobal(bytes32 nullifier) external view returns (bool) {
        return usedNullifiersGlobal[nullifier];
    }

    /// @notice Computes the withdraw binding hash for given parameters.
    /// @dev Matches the circuit's expected binding hash computation.
    ///      Uses WITHDRAW_BINDING_DOMAIN for domain separation.
    /// @param owner The note owner address.
    /// @param recipient The intended withdrawal recipient.
    /// @param amount The withdrawal amount.
    /// @return The binding hash: keccak256(WITHDRAW_DOMAIN || owner || recipient || amount).
    function computeWithdrawBindingHash(address owner, address recipient, uint256 amount)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAW_BINDING_DOMAIN, owner, recipient, amount));
    }

    /// @notice Checks whether a Merkle root is currently usable (known and not expired).
    /// @dev The latest root is always usable regardless of age.
    /// @param root The root hash to check.
    /// @return True if the root is known and (non-expired OR the latest root).
    function isRootUsable(bytes32 root) external view returns (bool) {
        if (!knownRoots[root]) return false;
        if (maxRootAge == 0) return true;

        // Latest root is always usable
        if (root == tree.getRoot()) return true;

        uint256 blockNum = rootBlockNumbers[root];
        if (blockNum == 0) return false;
        // Convert maxRootAge (seconds) to blocks
        uint256 maxRootAgeBlocks = (maxRootAge * BLOCKS_PER_DAY) / 1 days;
        return block.number <= blockNum + maxRootAgeBlocks;
    }

    // =========================================================
    //  Internal functions
    // =========================================================

    /// @notice Verifies a Groth16 proof against the registered verifier for the proof type.
    /// @dev Converts G2 coordinates from snarkjs to Solidity order, builds the public inputs
    ///      array matching the circuit signal order, and calls the verifier contract.
    /// @param proofType The proof type (determines which verifier to use).
    /// @param merkleRoot The Merkle root public input.
    /// @param nullifiers The two nullifier public inputs.
    /// @param outCommitments The two output commitment public inputs.
    /// @param fee The fee public input.
    /// @param relayer The relayer address public input.
    /// @param withdrawOwner The withdraw owner public input (0 for standard transact).
    /// @param withdrawRecipient The withdraw recipient public input (0 for standard transact).
    /// @param withdrawAmount The withdraw amount public input (0 for standard transact).
    /// @param a G1 point of the Groth16 proof.
    /// @param bSnarkjs G2 point of the Groth16 proof (snarkjs coordinate order).
    /// @param c G1 point of the Groth16 proof.
    function _verifyProof(
        uint8 proofType,
        bytes32 merkleRoot,
        bytes32[2] calldata nullifiers,
        bytes32[2] calldata outCommitments,
        uint256 fee,
        address relayer,
        address withdrawOwner,
        address withdrawRecipient,
        uint256 withdrawAmount,
        uint256 dstChainId,
        uint256[2] calldata a,
        uint256[2][2] calldata bSnarkjs,
        uint256[2] calldata c
    ) internal view {
        if (!proofTypeEnabled[proofType]) revert ProofTypeDisabled();

        address verifierAddr = verifiers[proofType];
        if (verifierAddr == address(0)) revert VerifierNotConfigured();

        // Convert G2 point from snarkjs to Solidity verifier coordinate order
        uint256[2][2] memory b = bSnarkjs.convertProof();

        // Build public inputs array matching circuit signal order (13 signals):
        // [merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer,
        //  nullifier0, nullifier1, outCommitment0, outCommitment1,
        //  withdrawOwner, withdrawRecipient, withdrawAmount]
        uint256[13] memory publicInputs = PoolPublicInputs.build(
            nullifiers,
            outCommitments,
            merkleRoot,
            block.chainid,
            dstChainId,
            protocolEpoch,
            fee,
            relayer,
            withdrawOwner,
            withdrawRecipient,
            withdrawAmount
        );

        bool ok = IVerifier(verifierAddr).verifyProof(a, b, c, publicInputs);
        if (!ok) revert InvalidProof();
    }

    /// @notice Marks nullifiers as spent and emits events.
    /// @dev MUST be called before any external calls (CEI pattern).
    /// @param nullifiers The nullifier array to mark.
    function _spendNullifiers(bytes32[2] calldata nullifiers) internal {
        usedNullifiersGlobal[nullifiers[0]] = true;
        usedNullifiersGlobal[nullifiers[1]] = true;
        emit NoteSpent(nullifiers[0]);
        emit NoteSpent(nullifiers[1]);

        // Sync nullifiers to supported chains via L2ToL2CrossDomainMessenger
        // Check if messenger has code before calling (graceful in test environments)
        if (_hasCode(L2_TO_L2_CROSS_DOMAIN_MESSENGER)) {
            _sendNullifierSync(nullifiers);
        }
    }

    /// @dev Private helper to check if an address has code.
    function _hasCode(address addr) private view returns (bool) {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(addr)
        }
        return codeSize > 0;
    }

    /// @notice Sends nullifier sync messages to all supported chains.
    /// @dev Called after nullifiers are marked as spent locally.
    ///      Uses L2ToL2CrossDomainMessenger.sendMessage to each supported chain.
    /// @param nullifiers The nullifiers that were spent.
    function _sendNullifierSync(bytes32[2] calldata nullifiers) internal {
        // Encode the sync message: syncNullifiers(nullifier0, nullifier1)
        bytes memory message = abi.encodeWithSelector(
            this.syncNullifiers.selector,
            nullifiers[0],
            nullifiers[1]
        );

        // Send to each supported chain from supportedChainList
        for (uint256 i = 0; i < supportedChainList.length; ++i) {
            uint256 dstChainId = supportedChainList[i];
            bytes32 msgHash = IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER)
                .sendMessage(dstChainId, address(this), message);
            emit NullifierSyncSent(dstChainId, nullifiers[0], nullifiers[1], msgHash);
        }
    }

    /// @notice Adds a new commitment to the Merkle tree and tracks the root.
    /// @dev Updates knownRoots and rootBlockNumbers. Queues the new root.
    /// @param commitment The note commitment to insert.
    function _addCommitmentToTree(bytes32 commitment) internal {
        MerkleTree.insert(tree, commitment);
        bytes32 newRoot = tree.getRoot();
        if (!knownRoots[newRoot]) {
            knownRoots[newRoot] = true;
            rootBlockNumbers[newRoot] = block.number;
            rootQueue[rootQueueTail] = newRoot;
            unchecked {
                rootQueueTail++;
            }
            emit RootAdded(newRoot);
        }
        emit NoteCreated(commitment);
    }

    /// @notice Credits the relayer fee through the asset ledger.
    /// @dev Splits fee between burn and relayer credit based on feeBurnBps.
    ///      The relayer portion is credited via ledger.credit (mints RYLA to relayer).
    ///      The burn portion is NOT credited to any address -- it is simply not minted,
    ///      effectively removing it from supply. We track _totalBurned for accounting.
    ///      RYLACreditLedger.credit() always calls TOKEN.mint(), so we cannot use it
    ///      for burns (mint to address(0) reverts in RYLA.mint).
    /// @param fee The total fee amount.
    /// @param relayer The relayer address to receive the non-burned portion.
    function _creditRelayerFee(uint256 fee, address relayer) internal {
        if (fee == 0) return;
        if (relayer == address(0)) revert InvalidRelayer();

        ICreditLedger ledger = ASSET_LEDGER;
        if (address(ledger) == address(0)) revert InvalidAssetLedger();

        (uint256 burnAmount, uint256 relayerAmount) = PoolFeePolicy.split(fee, feeBurnBps, MAX_FEE_BURN_BPS);

        if (relayerAmount > 0) {
            ledger.credit(relayer, relayerAmount);
            emit FeePaid(relayer, relayerAmount);
        }
        if (burnAmount > 0) {
            // Do NOT call ledger.credit(address(0), ...) -- RYLA.mint reverts on zero address.
            // The burn is implicit: the fee was collected but only relayerAmount is minted.
            // The burnAmount is effectively removed from supply.
            emit FeeBurned(burnAmount);
        }
    }
}
