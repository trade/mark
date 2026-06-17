// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISuperchainTokenBridge} from "@interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";
import {BridgeErrors} from "../errors/BridgeErrors.sol";

/// @title MARKBridgeAdapter
/// @notice Operator-gated bridge-out adapter for RYLA using SuperchainTokenBridge.
/// @dev Uses destination allowlist and optional per-tx / daily caps.
///      No pause mechanism is provided by design: emergency containment is achieved by
///      revoking all OPERATOR_ROLE holders (see RUNBOOK.md section 5), which stops all
///      bridge operations without introducing pause-admin key risk.
contract MARKBridgeAdapter is ReentrancyGuard, AccessControlDefaultAdminRules, BridgeErrors {
    using SafeERC20 for IERC20;

    event OperatorUpdated(address indexed operator, bool enabled);
    event DestinationUpdated(uint256 indexed destinationChainId, bool enabled);
    event BridgeLimitsUpdated(uint256 maxPerTx, uint256 dailyCap);
    event BridgedOut(
        address indexed operator,
        address indexed recipient,
        uint256 indexed destinationChainId,
        uint256 amount,
        bytes32 messageHash
    );

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public immutable TOKEN;
    ISuperchainTokenBridge public constant SUPERCHAIN_TOKEN_BRIDGE =
        ISuperchainTokenBridge(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);

    mapping(uint256 => bool) public destinationEnabled;

    uint256 public maxPerTx;
    uint256 public dailyCap;
    uint64 public dailyCapEpoch;
    uint256 public bridgedInDailyCapEpoch;

    constructor(address initialAdmin, address tokenAddress)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (tokenAddress == address(0)) revert ZeroAddress();
        TOKEN = IERC20(tokenAddress);
    }

    function setOperator(address operator, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (operator == address(0)) revert ZeroAddress();
        if (enabled) {
            _grantRole(OPERATOR_ROLE, operator);
        } else {
            _revokeRole(OPERATOR_ROLE, operator);
        }
        emit OperatorUpdated(operator, enabled);
    }

    function setDestination(uint256 destinationChainId, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (destinationChainId == 0) revert InvalidChainId();
        destinationEnabled[destinationChainId] = enabled;
        emit DestinationUpdated(destinationChainId, enabled);
    }

    /// @notice Sets optional bridge limits. Set `0` to disable each limiter.
    function setBridgeLimits(uint256 maxPerTx_, uint256 dailyCap_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPerTx = maxPerTx_;
        dailyCap = dailyCap_;
        dailyCapEpoch = 0;
        bridgedInDailyCapEpoch = 0;
        emit BridgeLimitsUpdated(maxPerTx_, dailyCap_);
    }

    function bridgeTo(address recipient, uint256 amount, uint256 destinationChainId)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        returns (bytes32 messageHash)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (destinationChainId == 0) revert InvalidChainId();
        if (!destinationEnabled[destinationChainId]) revert DestinationDisabled();

        _consumeLimits(amount);

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        TOKEN.forceApprove(address(SUPERCHAIN_TOKEN_BRIDGE), amount);

        try SUPERCHAIN_TOKEN_BRIDGE.sendERC20(address(TOKEN), recipient, amount, destinationChainId) returns (
            bytes32 hash
        ) {
            messageHash = hash;
        } catch {
            TOKEN.forceApprove(address(SUPERCHAIN_TOKEN_BRIDGE), 0);
            revert BridgeFailed();
        }
        emit BridgedOut(msg.sender, recipient, destinationChainId, amount, messageHash);
    }

    function _consumeLimits(uint256 amount) internal {
        uint256 maxPerTx_ = maxPerTx;
        if (maxPerTx_ > 0 && amount > maxPerTx_) revert MaxPerTxExceeded();

        uint256 dailyCap_ = dailyCap;
        if (dailyCap_ == 0) return;

        // OP Stack L2: ~2s blocks → 1 day ≈ 43200 blocks (not timestamp)
        uint64 epoch = uint64(block.number / 43200);
        if (epoch != dailyCapEpoch) {
            dailyCapEpoch = epoch;
            bridgedInDailyCapEpoch = 0;
        }

        uint256 nextBridged = bridgedInDailyCapEpoch + amount;
        if (nextBridged > dailyCap_) revert DailyCapExceeded();
        bridgedInDailyCapEpoch = nextBridged;
    }
}
