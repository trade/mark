// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Verifier interface for UTXO settlement proofs.
/// @dev Kept generic so different verifier backends can be swapped in.
///      Implementations should bind proofs to `settlementModule` to avoid cross-module replay.
interface IUTXOSettlementVerifier {
    function verifySettlement(
        bytes32 intentId,
        address settlementModule,
        address account,
        uint256 amount,
        bool isMint,
        bytes calldata proof
    ) external view returns (bool);
}
