// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IUTXOSettlementVerifier} from "../interfaces/IUTXOSettlementVerifier.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title AttestedSettlementVerifier
/// @notice Signature-based verifier for settlement intents.
/// @dev Intended as a production-safe bridge step before zk verifier integration.
///      Proof encoding:
///      `abi.encode(uint256 deadline, bytes32 contextHash, uint8 v, bytes32 r, bytes32 s)`.
///      Settlement digest binds to the calling settlement module address.
contract AttestedSettlementVerifier is IUTXOSettlementVerifier, AccessControlDefaultAdminRules {
    using MessageHashUtils for bytes32;

    bytes32 public constant SETTLEMENT_ATTESTATION_DOMAIN = keccak256("AttestedSettlementVerifier.v1");
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

    constructor(address initialAdmin) AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin) {
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
        if (intentId == bytes32(0) || settlementModule == address(0) || account == address(0) || amount == 0) return false;
        if (proof.length != 160) return false;

        Attestation memory att = abi.decode(proof, (Attestation));
        if (att.deadline < block.timestamp) return false;

        bytes32 digest =
            _settlementDigest(intentId, settlementModule, account, amount, isMint, att.contextHash, att.deadline);
        bytes memory signature = abi.encodePacked(att.r, att.s, att.v);
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer == address(0)) return false;

        return hasRole(ATTESTER_ROLE, signer);
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
        bytes32 settlementHash = keccak256(
            abi.encode(
                SETTLEMENT_ATTESTATION_DOMAIN,
                address(this),
                block.chainid,
                intentId,
                settlementModule,
                account,
                amount,
                isMint,
                contextHash,
                deadline
            )
        );
        return settlementHash.toEthSignedMessageHash();
    }
}
