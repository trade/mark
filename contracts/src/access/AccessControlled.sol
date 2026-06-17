// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title AccessControlled
/// @notice Base contract providing standardized AccessControlDefaultAdminRules setup.
/// @dev All MARK protocol contracts requiring access control should inherit from this
///      instead of directly from AccessControlDefaultAdminRules. This ensures:
///      - Consistent DEFAULT_ADMIN_DELAY (1 day) across all contracts
///      - Standardized constructor signature
///      - Single point of upgrades for access control logic
contract AccessControlled is AccessControlDefaultAdminRules {
    /// @notice Standard admin delay of 1 day for all MARK protocol contracts.
    /// @dev This aligns with the OP Stack timelock convention and provides a 24-hour
    ///      window for users to react to admin changes before they take effect.
    uint48 public constant DEFAULT_ADMIN_DELAY = 1 days;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address initialAdmin) AccessControlDefaultAdminRules(DEFAULT_ADMIN_DELAY, initialAdmin) {
        if (initialAdmin == address(0)) {
            revert AdminCannotBeZero();
        }
    }

    /// @notice Reverted when attempting to set admin to zero address.
    error AdminCannotBeZero();

    /// @dev Forward supportsInterface to AccessControlDefaultAdminRules.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlDefaultAdminRules)
        returns (bool)
    {
        return AccessControlDefaultAdminRules.supportsInterface(interfaceId);
    }
}