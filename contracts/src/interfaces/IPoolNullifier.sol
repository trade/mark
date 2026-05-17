// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Minimal Pool surface required by WithdrawAdapter.
interface IPoolNullifier {
    function isNullifierUsedGlobal(bytes32 nullifier)
        external
        view
        returns (bool);

    function nullifierWithdrawBinding(bytes32 nullifier)
        external
        view
        returns (bytes32);

    function computeWithdrawBindingHash(
        address owner,
        address recipient,
        uint256 amount
    ) external view returns (bytes32);
}
