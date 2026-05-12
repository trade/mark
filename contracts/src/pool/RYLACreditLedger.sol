// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRYLA} from "../interfaces/IRYLA.sol";
import {ICreditLedger} from "../interfaces/ICreditLedger.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RYLACreditLedger
/// @notice Adapter that bridges ICreditLedger to IRYLA for MARKPool.
/// @dev Only the MARKPool contract set at construction may call credit/debit.
///      This contract must hold MINTER_ROLE and BURNER_ROLE on the RYLA token.
///      `debit` requires `from` to have approved this contract for at least `amount` tokens.
contract RYLACreditLedger is ICreditLedger {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error ZeroAddress();

    IRYLA public immutable TOKEN;
    address public immutable POOL;

    uint256 private _totalMinted;
    uint256 private _totalBurned;

    constructor(address token_, address pool_) {
        if (token_ == address(0) || pool_ == address(0)) revert ZeroAddress();
        TOKEN = IRYLA(token_);
        POOL = pool_;
    }

    modifier onlyPool() {
        if (msg.sender != POOL) revert Unauthorized();
        _;
    }

    function credit(address to, uint256 amount) external onlyPool {
        TOKEN.mint(to, amount);
        _totalMinted += amount;
    }

    function debit(address from, uint256 amount) external onlyPool {
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
