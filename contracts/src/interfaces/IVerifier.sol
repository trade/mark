// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[13] calldata input
    ) external view returns (bool);
}
