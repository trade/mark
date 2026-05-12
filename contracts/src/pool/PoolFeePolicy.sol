// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Fee policy and split helpers for Pool.
library PoolFeePolicy {
    function split(uint256 fee, uint256 feeBurnBps, uint256 maxFeeBurnBps)
        internal
        pure
        returns (uint256 burnAmount, uint256 relayerAmount)
    {
        burnAmount = fee * feeBurnBps / maxFeeBurnBps;
        relayerAmount = fee - burnAmount;
    }
}
