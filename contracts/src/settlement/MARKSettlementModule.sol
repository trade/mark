// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RYLA} from "../token/RYLA.sol";
import {IUTXOSettlementVerifier} from "./interfaces/IUTXOSettlementVerifier.sol";
import {SettlementErrors} from "../errors/SettlementErrors.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";

/// @title MARKSettlementModule
/// @notice Boundary module for integrating external UTXO/zk accounting with RYLA mint/burn.
/// @dev Holds RYLA minter and burner roles. Replay protection is enforced via `intentId`.
contract MARKSettlementModule is ReentrancyGuard, AccessControlDefaultAdminRules, SettlementErrors {
    using SafeERC20 for IERC20;
    event OperatorUpdated(address indexed operator, bool enabled);
    event VerifierUpdated(address indexed verifier, bool validationEnabled);
    event ProductionModeActivated(address indexed admin);
    event MintSettled(bytes32 indexed intentId, address indexed operator, address indexed recipient, uint256 amount);
    event BurnSettled(bytes32 indexed intentId, address indexed operator, address indexed account, uint256 amount);

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    RYLA public immutable TOKEN;

    mapping(bytes32 => bool) public consumedIntents;
    uint256 public totalSettledMint;
    uint256 public totalSettledBurn;

    IUTXOSettlementVerifier public verifier;
    bool public proofValidationEnabled;
    bool public productionMode;

    constructor(address initialAdmin, address tokenAddress)
        AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (tokenAddress == address(0)) revert ZeroAddress();
        TOKEN = RYLA(tokenAddress);
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

    function setVerifier(address verifierAddress, bool enableValidation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (productionMode && (!enableValidation || verifierAddress == address(0))) {
            revert ProductionModeRequiresProofValidation();
        }
        if (enableValidation && verifierAddress == address(0)) revert VerifierRequired();
        if (verifierAddress != address(0) && verifierAddress.code.length == 0) revert VerifierRequired();

        verifier = IUTXOSettlementVerifier(verifierAddress);
        proofValidationEnabled = enableValidation;
        emit VerifierUpdated(verifierAddress, enableValidation);
    }

    /// @notice Irreversibly enables production mode that forces proof validation to remain active.
    function activateProductionMode() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (productionMode) revert ProductionModeAlreadyEnabled();
        if (!proofValidationEnabled || address(verifier) == address(0)) {
            revert ProductionModeRequiresProofValidation();
        }
        productionMode = true;
        emit ProductionModeActivated(msg.sender);
    }

    function settleMint(address recipient, uint256 amount, bytes32 intentId, bytes calldata proof)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (recipient == address(0)) revert ZeroAddress();
        _consumeAndValidate(intentId, recipient, amount, true, proof);
        TOKEN.mint(recipient, amount);
        totalSettledMint += amount;
        emit MintSettled(intentId, msg.sender, recipient, amount);
    }

    function settleBurn(address account, uint256 amount, bytes32 intentId, bytes calldata proof)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (account == address(0)) revert ZeroAddress();
        _consumeAndValidate(intentId, account, amount, false, proof);

        uint256 moduleBalanceBefore = TOKEN.balanceOf(address(this));
        IERC20(address(TOKEN)).safeTransferFrom(account, address(this), amount);
        uint256 moduleBalanceAfterTransfer = TOKEN.balanceOf(address(this));
        if (moduleBalanceAfterTransfer != moduleBalanceBefore + amount) revert BurnEscrowInvariantFailed();

        TOKEN.burn(amount);
        uint256 moduleBalanceAfterBurn = TOKEN.balanceOf(address(this));
        if (moduleBalanceAfterBurn != moduleBalanceBefore) revert BurnEscrowInvariantFailed();
        totalSettledBurn += amount;
        emit BurnSettled(intentId, msg.sender, account, amount);
    }

    function _consumeAndValidate(bytes32 intentId, address account, uint256 amount, bool isMint, bytes calldata proof)
        internal
    {
        if (intentId == bytes32(0)) revert InvalidIntent();
        if (amount == 0) revert InvalidAmount();
        if (consumedIntents[intentId]) revert IntentAlreadyConsumed();

        if (proofValidationEnabled) {
            IUTXOSettlementVerifier verifier_ = verifier;
            if (address(verifier_) == address(0)) revert VerifierRequired();
            bool ok = verifier_.verifySettlement(intentId, address(this), account, amount, isMint, proof);
            if (!ok) revert VerificationFailed();
        }

        consumedIntents[intentId] = true;
    }
}
