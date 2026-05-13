// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRYLA} from "../interfaces/IRYLA.sol";
import {ICreditLedger} from "../interfaces/ICreditLedger.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RYLACreditLedger
/// @notice Adapter that bridges ICreditLedger to IRYLA for MARKPool and MARKWithdrawAdapter.
/// @dev credit() is restricted to POOL — called for relayer fee payouts.
///      debit() is restricted to ADAPTER — called to burn RYLA on withdrawal.
///      ADAPTER is set post-construction via setAdapter() to break the circular deploy
///      dependency (adapter constructor requires ledger address, ledger requires adapter address).
///      This contract must hold MINTER_ROLE and BURNER_ROLE on the RYLA token.
///      `debit` requires `from` to have approved this contract for at least `amount` tokens.
contract RYLACreditLedger is ICreditLedger {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error ZeroAddress();
    error AdapterAlreadySet();

    event AdapterSet(address indexed adapter);

    IRYLA public immutable TOKEN;
    address public immutable POOL;
    address public ADAPTER;

    uint256 private _totalMinted;
    uint256 private _totalBurned;

    constructor(address token_, address pool_) {
        if (token_ == address(0) || pool_ == address(0)) revert ZeroAddress();
        TOKEN = IRYLA(token_);
        POOL = pool_;
    }

    /// @notice Sets the adapter address. Can only be called once.
    /// @dev Called post-deployment to break the circular dependency between
    ///      RYLACreditLedger and MARKWithdrawAdapter.
    function setAdapter(address adapter_) external {
        if (ADAPTER != address(0)) revert AdapterAlreadySet();
        if (adapter_ == address(0)) revert ZeroAddress();
        ADAPTER = adapter_;
        emit AdapterSet(adapter_);
    }

    function credit(address to, uint256 amount) external {
        if (msg.sender != POOL) revert Unauthorized();
        TOKEN.mint(to, amount);
        _totalMinted += amount;
    }

    function debit(address from, uint256 amount) external {
        if (msg.sender != ADAPTER) revert Unauthorized();
        IERC20(address(TOKEN)).safeTransferFrom(from, address(this), amount);
        TOKEN.burn(amount);
        _totalBurned += amount;
    }

    function creditBalanceOf(address account) external view returns (uint256) {
        return TOKEN.balanceOf(account);
    }

    function totalCreditsMinted() external view returns (uint256) {
        return _totalMinted;
    }

    function totalCreditsBurned() external view returns (uint256) {
        return _totalBurned;
    }

    function totalCreditsOutstanding() external view returns (uint256) {
        return _totalMinted - _totalBurned;
    }

    function maxCredits() external pure returns (uint256) {
        return type(uint256).max;
    }
}
