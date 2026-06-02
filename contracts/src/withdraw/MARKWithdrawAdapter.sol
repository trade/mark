// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ICreditLedger} from "../interfaces/ICreditLedger.sol";
import {IPoolNullifier} from "../interfaces/IPoolNullifier.sol";
import {MARKWithdrawErrors} from "./MARKWithdrawErrors.sol";

/// @notice Native-token payout adapter backed by credit debits.
/// @dev Amount/recipient are bound to per-nullifier Pool withdraw bindings.
///      Owner authorization still relies on signatures; the circuit does not bind owner to note secret.
contract MARKWithdrawAdapter is AccessManaged, Pausable, ReentrancyGuard, MARKWithdrawErrors {
    bytes32 public constant WITHDRAW_INTENT_DOMAIN = keccak256("MARKWithdrawAdapter.Intent.v1");
    uint256 public constant DEFAULT_MAX_INTENT_VALIDITY = 1 hours;

    ICreditLedger public immutable ASSET_LEDGER;
    IPoolNullifier public immutable PROOF_POOL;
    uint256 public maxIntentValidity;
    uint256 public totalNativePaid;
    mapping(address => uint256) public withdrawNonce;
    mapping(bytes32 => bool) public claimedNullifiers;
    mapping(address => bool) public intentSigners;

    event NativeReceived(address indexed from, uint256 amount, uint256 resultingBalance);
    event MaxIntentValiditySet(uint256 previousMaxIntentValidity, uint256 newMaxIntentValidity);
    event IntentSignerSet(address indexed signer, bool previousEnabled, bool newEnabled);
    event NullifierClaimed(bytes32 indexed nullifier, address indexed owner);
    event WithdrawIntentAuthorized(address indexed signer, bytes32 indexed intentHash, address indexed owner);
    event WithdrawExecuted(
        address indexed creditOwner,
        address indexed recipient,
        uint256 amount,
        uint256 nonce,
        bytes32 indexed intentHash,
        address caller
    );

    constructor(address initialAuthority, address ledgerAddress, address poolAddress) AccessManaged(initialAuthority) {
        if (ledgerAddress == address(0)) revert InvalidAssetLedger();
        if (poolAddress == address(0)) revert InvalidProofPool();
        if (ledgerAddress.code.length == 0) revert AssetLedgerMustBeContract();
        if (poolAddress.code.length == 0) revert ProofPoolMustBeContract();
        ASSET_LEDGER = ICreditLedger(ledgerAddress);
        PROOF_POOL = IPoolNullifier(poolAddress);
        maxIntentValidity = DEFAULT_MAX_INTENT_VALIDITY;
        emit MaxIntentValiditySet(0, DEFAULT_MAX_INTENT_VALIDITY);
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value, address(this).balance);
    }

    function pause() external restricted {
        if (paused()) revert AlreadyPaused();
        _pause();
    }

    function unpause() external restricted {
        if (!paused()) revert NotPaused();
        _unpause();
    }

    function setMaxIntentValidity(uint256 newMaxIntentValidity) external restricted {
        if (newMaxIntentValidity == 0) revert InvalidMaxIntentValidity();
        uint256 previous = maxIntentValidity;
        if (newMaxIntentValidity == previous) revert NoStateChange();
        maxIntentValidity = newMaxIntentValidity;
        emit MaxIntentValiditySet(previous, newMaxIntentValidity);
    }

    function setIntentSigner(address signer, bool enabled) external restricted {
        if (signer == address(0)) revert InvalidSigner();
        bool previousEnabled = intentSigners[signer];
        if (enabled == previousEnabled) revert NoStateChange();
        intentSigners[signer] = enabled;
        emit IntentSignerSet(signer, previousEnabled, enabled);
    }

    function computeWithdrawIntentHash(
        address creditOwner,
        address recipient,
        uint256 amount,
        bytes32[2] memory nullifiers,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                WITHDRAW_INTENT_DOMAIN,
                address(this),
                block.chainid,
                address(ASSET_LEDGER),
                address(PROOF_POOL),
                creditOwner,
                recipient,
                amount,
                nullifiers[0],
                nullifiers[1],
                nonce,
                deadline
            )
        );
    }

    /// @notice Returns the EIP-191 personal_sign digest for a withdraw intent.
    /// @dev Uses toEthSignedMessageHash (personal_sign) intentionally — signers use
    ///      eth_sign or personal_sign, not eth_signTypedData. The intent hash is a
    ///      structured keccak256 hash; wrapping it in EIP-191 prevents raw-hash signing
    ///      attacks while keeping wallet compatibility broad.
    function computeWithdrawIntentDigest(
        address creditOwner,
        address recipient,
        uint256 amount,
        bytes32[2] calldata nullifiers,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32) {
        bytes32 intentHash = computeWithdrawIntentHash(creditOwner, recipient, amount, nullifiers, nonce, deadline);
        return MessageHashUtils.toEthSignedMessageHash(intentHash);
    }

    function withdrawWithSig(
        address creditOwner,
        address recipient,
        uint256 amount,
        bytes32[2] calldata nullifiers,
        uint256 nonce,
        uint256 deadline,
        bytes calldata ownerSignature,
        bytes calldata intentSignature
    ) external nonReentrant whenNotPaused {
        _validateWithdrawRequest(creditOwner, recipient, amount, nonce, deadline, ownerSignature, intentSignature);
        _validateNullifierState(nullifiers);
        _requireWithdrawBindingMatch(nullifiers, creditOwner, recipient, amount);

        (bytes32 intentHash, address intentSigner) = _requireSignatures(
            creditOwner, recipient, amount, nullifiers, nonce, deadline, ownerSignature, intentSignature
        );

        withdrawNonce[creditOwner] = nonce + 1;
        claimedNullifiers[nullifiers[0]] = true;
        claimedNullifiers[nullifiers[1]] = true;
        emit WithdrawIntentAuthorized(intentSigner, intentHash, creditOwner);
        emit NullifierClaimed(nullifiers[0], creditOwner);
        emit NullifierClaimed(nullifiers[1], creditOwner);
        totalNativePaid += amount;

        // Transfer ETH before burning RYLA — if the transfer fails, RYLA is not burned.
        (bool ok, ) = payable(recipient).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        // Debit RYLA from owner's account.
        ASSET_LEDGER.debit(creditOwner, amount);

        emit WithdrawExecuted(creditOwner, recipient, amount, nonce, intentHash, msg.sender);
        }

    function _validateWithdrawRequest(
        address creditOwner,
        address recipient,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata ownerSignature,
        bytes calldata intentSignature
    ) internal view {
        if (creditOwner == address(0)) revert InvalidCreditOwner();
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (ownerSignature.length == 0) revert MissingOwnerSignature();
        if (intentSignature.length == 0) revert MissingIntentSignature();
        if (deadline == 0) revert InvalidIntentDeadline();
        // nosemgrep: mark-timestamp-in-withdraw - Deadline validation, not in ZK proof circuit
        if (deadline < block.timestamp) revert IntentExpired();
        // nosemgrep: mark-timestamp-in-withdraw - Deadline validation, not in ZK proof circuit
        if (deadline - block.timestamp > maxIntentValidity) revert IntentExceedsMaxValidity();
        if (address(this).balance < amount) revert InsufficientLiquidity();
        if (nonce != withdrawNonce[creditOwner]) revert NonceMismatch();
    }

    function _validateNullifierState(bytes32[2] calldata nullifiers) internal view {
        if (nullifiers[0] == bytes32(0)) revert NullifierInvalid();
        if (nullifiers[1] == bytes32(0)) revert NullifierInvalid();
        if (nullifiers[0] == nullifiers[1]) revert NullifierDuplicate();
        if (!PROOF_POOL.isNullifierUsedGlobal(nullifiers[0])) revert NullifierNotConsumed();
        if (!PROOF_POOL.isNullifierUsedGlobal(nullifiers[1])) revert NullifierNotConsumed();
        if (claimedNullifiers[nullifiers[0]]) revert NullifierAlreadyClaimed();
        if (claimedNullifiers[nullifiers[1]]) revert NullifierAlreadyClaimed();
    }

    function _requireWithdrawBindingMatch(
        bytes32[2] calldata nullifiers,
        address owner,
        address recipient,
        uint256 amount
    ) internal view {
        bytes32 expectedBinding = PROOF_POOL.computeWithdrawBindingHash(owner, recipient, amount);
        if (PROOF_POOL.nullifierWithdrawBinding(nullifiers[0]) != expectedBinding) revert WithdrawBindingMismatch();
        if (PROOF_POOL.nullifierWithdrawBinding(nullifiers[1]) != expectedBinding) revert WithdrawBindingMismatch();
    }

    function _requireSignatures(
        address creditOwner,
        address recipient,
        uint256 amount,
        bytes32[2] calldata nullifiers,
        uint256 nonce,
        uint256 deadline,
        bytes calldata ownerSignature,
        bytes calldata intentSignature
    ) internal view returns (bytes32 intentHash, address intentSigner) {
        intentHash = computeWithdrawIntentHash(creditOwner, recipient, amount, nullifiers, nonce, deadline);
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(intentHash);

        address ownerSigner = ECDSA.recover(digest, ownerSignature);
        if (ownerSigner != creditOwner) revert InvalidOwnerSigner();

        intentSigner = ECDSA.recover(digest, intentSignature);
        if (!intentSigners[intentSigner]) revert UnauthorizedIntentSigner();
        if (intentSigner == creditOwner) revert OwnerCannotCoSign();
    }
}
