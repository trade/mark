// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IUTXOSettlementVerifier} from "../interfaces/IUTXOSettlementVerifier.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title AttestedSettlementVerifier
/// @notice Signature-based verifier for settlement intents using EIP-712 typed data signing.
/// @dev Intended as a production-safe bridge step before zk verifier integration.
///      Proof encoding (160 bytes — 5 × 32-byte ABI words):
///      `abi.encode(uint256 deadline, bytes32 contextHash, uint8 v, bytes32 r, bytes32 s)`.
///      The digest binds to the verifier address, chain id, and settlement module address,
///      preventing cross-verifier and cross-module replay.
///      `contextHash` is an opaque attester-controlled binding value (e.g. off-chain UTXO
///      state root or batch id) included in the signed digest to tie the attestation to
///      external state without exposing that state on-chain.
contract AttestedSettlementVerifier is IUTXOSettlementVerifier, EIP712, AccessControlDefaultAdminRules {
    using ECDSA for bytes32;

    /// @dev EIP-712 type hash for the SettlementAttestation struct.
    bytes32 public constant SETTLEMENT_ATTESTATION_TYPEHASH = keccak256(
        "SettlementAttestation(bytes32 intentId,address verifier,address settlementModule,address account,uint256 amount,bool isMint,bytes32 contextHash,uint256 deadline,uint256 chainId)"
    );

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant ATTESTER_ROLE = keccak256("ATTESTER_ROLE");

    event AttesterUpdated(address indexed attester, bool enabled);

    struct Attestation {
        uint256 deadline;
        bytes32 contextHash;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    constructor(address initialAdmin)
        EIP712("AttestedSettlementVerifier", "1")
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
    }

    function setAttester(address attester, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (attester == address(0)) revert ZeroAddress();
        if (enabled) {
            _grantRole(ATTESTER_ROLE, attester);
        } else {
            _revokeRole(ATTESTER_ROLE, attester);
        }
        emit AttesterUpdated(attester, enabled);
    }

    function verifySettlement(
        bytes32 intentId,
        address settlementModule,
        address account,
        uint256 amount,
        bool isMint,
        bytes calldata proof
    )
        external
        view
        override
        returns (bool)
    {
        if (intentId == bytes32(0) || settlementModule == address(0) || account == address(0) || amount == 0) {
            return false;
        }
        // 160 bytes = 5 × 32-byte ABI words from abi.encode of the Attestation struct
        // (uint8 v is padded to 32 bytes by ABI encoding).
        if (proof.length != 160) return false;

        Attestation memory att = abi.decode(proof, (Attestation));
        if (att.deadline < block.timestamp) return false;

        bytes32 digest = _settlementDigest(intentId, settlementModule, account, amount, isMint, att.contextHash, att.deadline);
        bytes memory signature = abi.encodePacked(att.r, att.s, att.v);
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer == address(0)) return false;

        return hasRole(ATTESTER_ROLE, signer);
    }

    /// @dev Returns the EIP-712 digest for a settlement attestation.
    ///      Exposed so off-chain signers can compute the exact bytes to sign without
    ///      reading internal implementation details.
    function settlementDigest(
        bytes32 intentId,
        address settlementModule,
        address account,
        uint256 amount,
        bool isMint,
        bytes32 contextHash,
        uint256 deadline
    ) external view returns (bytes32) {
        return _settlementDigest(intentId, settlementModule, account, amount, isMint, contextHash, deadline);
    }

    function _settlementDigest(
        bytes32 intentId,
        address settlementModule,
        address account,
        uint256 amount,
        bool isMint,
        bytes32 contextHash,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SETTLEMENT_ATTESTATION_TYPEHASH,
                intentId,
                address(this),
                settlementModule,
                account,
                amount,
                isMint,
                contextHash,
                deadline,
                block.chainid
            )
        );
        return _hashTypedDataV4(structHash);
    }
}
