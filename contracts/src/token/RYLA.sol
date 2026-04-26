// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {SuperchainERC20} from "@interop-lib/SuperchainERC20.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";
import {TokenErrors} from "../errors/TokenErrors.sol";

/// @title RYLA (Ʀ)
/// @notice Superchain-compatible standard credit token.
/// @dev Cross-chain mint/burn is handled by SuperchainTokenBridge via SuperchainERC20.
contract RYLA is SuperchainERC20, AccessControlDefaultAdminRules, TokenErrors {

    event MinterUpdated(address indexed account, bool enabled);
    event BurnerUpdated(address indexed account, bool enabled);

    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(address initialAdmin) AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin) {
        if (initialAdmin == address(0)) revert ZeroAddress();
    }

    function name() public pure override returns (string memory) {
        return "RYLA";
    }

    function symbol() public pure override returns (string memory) {
        return "RYLA";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlDefaultAdminRules, SuperchainERC20)
        returns (bool)
    {
        return AccessControlDefaultAdminRules.supportsInterface(interfaceId)
            || SuperchainERC20.supportsInterface(interfaceId);
    }

    function setMinter(address account, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (enabled) {
            _grantRole(MINTER_ROLE, account);
        } else {
            _revokeRole(MINTER_ROLE, account);
        }
        emit MinterUpdated(account, enabled);
    }

    function setBurner(address account, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (enabled) {
            _grantRole(BURNER_ROLE, account);
        } else {
            _revokeRole(BURNER_ROLE, account);
        }
        emit BurnerUpdated(account, enabled);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        _mint(to, amount);
    }

    /// @notice Burns tokens from the caller balance (typically a burner module).
    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        if (amount == 0) revert InvalidAmount();
        _burn(msg.sender, amount);
    }
}
