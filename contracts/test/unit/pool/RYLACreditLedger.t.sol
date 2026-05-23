// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {RYLA} from "../../../src/token/RYLA.sol";

contract RYLACreditLedgerTest is Test {
    RYLACreditLedger internal ledger;
    RYLA internal token;

    address internal admin = makeAddr("admin");
    address internal pool = makeAddr("pool");
    address internal adapter = makeAddr("adapter");
    address internal user = makeAddr("user");
    address internal other = makeAddr("other");

    function setUp() public {
        // Give pool and adapter contract bytecode so code.length checks pass
        vm.etch(pool, hex"00");
        vm.etch(adapter, hex"00");

        vm.startPrank(admin);
        token = new RYLA(admin);
        ledger = new RYLACreditLedger(address(token), pool);
        ledger.setAdapter(adapter);
        token.setMinter(address(ledger), true);
        token.setBurner(address(ledger), true);
        vm.stopPrank();
    }

    function testCreditMintsToRecipient() public {
        vm.prank(pool);
        ledger.credit(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);
    }

    function testCreditTracksTotal() public {
        vm.prank(pool);
        ledger.credit(user, 100e18);
        assertEq(ledger.totalCreditsMinted(), 100e18);
        assertEq(ledger.totalCreditsOutstanding(), 100e18);
    }

    function testDebitBurnsTokens() public {
        vm.prank(pool);
        ledger.credit(user, 100e18);

        vm.prank(user);
        token.approve(address(ledger), 100e18);

        vm.prank(adapter);
        ledger.debit(user, 100e18);

        assertEq(token.balanceOf(user), 0);
        assertEq(ledger.totalCreditsBurned(), 100e18);
        assertEq(ledger.totalCreditsOutstanding(), 0);
    }

    function testCreditRevertsForNonPool() public {
        vm.prank(other);
        vm.expectRevert(RYLACreditLedger.Unauthorized.selector);
        ledger.credit(user, 100e18);
    }

    function testDebitRevertsForNonAdapter() public {
        vm.prank(other);
        vm.expectRevert(RYLACreditLedger.Unauthorized.selector);
        ledger.debit(user, 100e18);
    }

    function testDebitRevertsForPool() public {
        vm.prank(pool);
        vm.expectRevert(RYLACreditLedger.Unauthorized.selector);
        ledger.debit(user, 100e18);
    }

    function testSetAdapterRevertsIfAlreadySet() public {
        vm.prank(admin);
        vm.expectRevert(RYLACreditLedger.AdapterAlreadySet.selector);
        ledger.setAdapter(makeAddr("other-adapter"));
    }

    function testSetAdapterRevertsOnZeroAddress() public {
        vm.prank(admin);
        RYLACreditLedger fresh = new RYLACreditLedger(address(token), pool);
        vm.prank(admin);
        vm.expectRevert(RYLACreditLedger.ZeroAddress.selector);
        fresh.setAdapter(address(0));
    }

    function testSetAdapterRevertsForNonOwner() public {
        vm.prank(admin);
        RYLACreditLedger fresh = new RYLACreditLedger(address(token), pool);
        vm.prank(other);
        vm.expectRevert(RYLACreditLedger.Unauthorized.selector);
        fresh.setAdapter(makeAddr("attacker"));
    }

    function testConstructorRevertsOnZeroToken() public {
        vm.expectRevert(RYLACreditLedger.ZeroAddress.selector);
        new RYLACreditLedger(address(0), pool);
    }

    function testConstructorRevertsOnZeroPool() public {
        vm.expectRevert(RYLACreditLedger.ZeroAddress.selector);
        new RYLACreditLedger(address(token), address(0));
    }

    function testCreditBalanceOf() public {
        vm.prank(pool);
        ledger.credit(user, 50e18);
        assertEq(ledger.creditBalanceOf(user), 50e18);
    }

    function testConstructorRevertsOnEOAToken() public {
        vm.expectRevert(RYLACreditLedger.InvalidContract.selector);
        new RYLACreditLedger(makeAddr("eoa-token"), pool);
    }

    function testConstructorRevertsOnEOAPool() public {
        vm.expectRevert(RYLACreditLedger.InvalidContract.selector);
        new RYLACreditLedger(address(token), makeAddr("eoa-pool"));
    }

    function testDebitRevertsOnEOA() public {
        vm.prank(admin);
        RYLACreditLedger fresh = new RYLACreditLedger(address(token), pool);
        vm.prank(admin);
        vm.expectRevert(RYLACreditLedger.InvalidContract.selector);
        fresh.setAdapter(makeAddr("eoa-adapter"));
    }

    function testDebitRevertsWithoutApproval() public {
        vm.prank(pool);
        ledger.credit(user, 100e18);

        vm.prank(adapter);
        vm.expectRevert();
        ledger.debit(user, 100e18);
    }

    function testDebitRevertsWithInsufficientApproval() public {
        vm.prank(pool);
        ledger.credit(user, 100e18);

        vm.prank(user);
        token.approve(address(ledger), 50e18);

        vm.prank(adapter);
        vm.expectRevert();
        ledger.debit(user, 100e18);
    }
}
