// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Shared bridge adapter custom errors.
abstract contract BridgeErrors {
    error InvalidAmount();
    error InvalidChainId();
    error DestinationDisabled();
    error MaxPerTxExceeded();
    error DailyCapExceeded();
    error BridgeFailed();
}
