// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IUTXOSettlementVerifier} from "../interfaces/IUTXOSettlementVerifier.sol";
import {IGroth16Verifier} from "../interfaces/IGroth16Verifier.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title Groth16SettlementVerifier
/// @notice Groth16 proof verifier for UTXO settlement intents.
/// @dev Implements IUTXOSettlementVerifier by delegating to a circuit-generated
///      IGroth16Verifier contract. The verifier contract is produced by snarkjs
///      `exportSolidityVerifier` from the compiled UTXO circuit and encodes the
///      circuit's verification key. Swap circuits by deploying a new verifier
///      contract and calling `setVerifierContract`.
///
///      Proof layout (384 bytes total passed as `proof` to verifySettlement):
///        bytes  [0:256]  — Groth16 proof: abi.encode(uint256[2] a, uint256[2][2] b, uint256[2] c)
///        bytes [256:384] — Public signals: abi.encode(uint256[4])
///          pubSignals[0] nullifierHash  — prevents double-spend of the input UTXO note
///          pubSignals[1] commitmentHash — binds the output note (recipient + amount + blinding)
///          pubSignals[2] amount         — must equal the amount passed to verifySettlement
///          pubSignals[3] isMint         — must equal 1 (mint) or 0 (burn)
///
///      The circuit proves knowledge of a secret note such that:
///        - The note's nullifier has not been seen before (enforced off-chain by operator)
///        - The note's value equals `amount`
///        - The note's direction (mint/burn) matches `isMint`
///      On-chain, this contract verifies the proof and checks that the public signals
///      are consistent with the settlement parameters.
contract Groth16SettlementVerifier is IUTXOSettlementVerifier, AccessControlDefaultAdminRules {
    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;

    /// @dev Length of the Groth16 proof component (a, b, c encoded).
    uint256 private constant PROOF_BYTES = 256;
    /// @dev Length of the public signals component (4 × uint256).
    uint256 private constant PUB_SIGNALS_BYTES = 128;
    /// @dev Total expected proof length passed to verifySettlement.
    uint256 private constant TOTAL_PROOF_BYTES = PROOF_BYTES + PUB_SIGNALS_BYTES;

    event VerifierContractUpdated(address indexed verifierContract);

    /// @notice The circuit-generated Groth16 verifier contract.
    /// @dev address(0) until a real circuit verifier is deployed and set.
    IGroth16Verifier public verifierContract;

    constructor(address initialAdmin)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
    }

    /// @notice Sets the circuit-generated Groth16 verifier contract.
    /// @dev Deploy the verifier produced by `snarkjs exportSolidityVerifier` and pass
    ///      its address here. Rejects EOAs and undeployed addresses.
    function setVerifierContract(address verifierContract_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (verifierContract_ == address(0)) revert ZeroAddress();
        if (verifierContract_.code.length == 0) revert ZeroAddress();
        verifierContract = IGroth16Verifier(verifierContract_);
        emit VerifierContractUpdated(verifierContract_);
    }

    /// @inheritdoc IUTXOSettlementVerifier
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
        if (proof.length != TOTAL_PROOF_BYTES) return false;

        IGroth16Verifier verifier_ = verifierContract;
        if (address(verifier_) == address(0)) return false;

        bytes calldata groth16Proof = proof[0:PROOF_BYTES];
        bytes calldata pubSignalsBytes = proof[PROOF_BYTES:TOTAL_PROOF_BYTES];

        uint256[4] memory pubSignals = abi.decode(pubSignalsBytes, (uint256[4]));

        // Public signal consistency checks — the circuit must commit to these values.
        if (pubSignals[2] != amount) return false;
        if (pubSignals[3] != (isMint ? 1 : 0)) return false;

        return verifier_.verifyProof(groth16Proof, pubSignalsBytes);
    }
}
