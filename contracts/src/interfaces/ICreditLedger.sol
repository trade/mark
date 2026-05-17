// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ICreditLedger {
    function credit(address to, uint256 amount) external;
    function debit(address from, uint256 amount) external;
    function creditBalanceOf(address account) external view returns (uint256);
    function totalCreditsMinted() external view returns (uint256);
    function totalCreditsBurned() external view returns (uint256);
    function totalCreditsOutstanding() external view returns (uint256);
    function maxCredits() external view returns (uint256);
}
