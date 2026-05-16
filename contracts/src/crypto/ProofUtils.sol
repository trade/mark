// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library ProofUtils {
    /**
     * @dev Converts snarkjs proof format to Solidity verifier format
     * Fixes G2 point coordinate ordering incompatibility
     */
    function convertProof(uint256[2][2] memory bSnarkjs)
        internal
        pure
        returns (uint256[2][2] memory)
    {
        // Fix G2 point coordinate ordering
        uint256[2][2] memory bFixed = [
            [bSnarkjs[0][1], bSnarkjs[0][0]], // Swap coordinates
            [bSnarkjs[1][1], bSnarkjs[1][0]] // Swap coordinates
        ];

        return bFixed;
    }
}
