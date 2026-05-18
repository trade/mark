// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Minimal Pool surface required by BridgeAdapter.
interface IPoolBridge {
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
    ) external;

    function bridgeIn(uint256 srcChainId, bytes32[2] calldata outCommitments) external;
}
