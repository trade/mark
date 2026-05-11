// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {IUTXOVerifier} from "../../../src/pool/interfaces/IUTXOVerifier.sol";
import {PoolErrors} from "../../../src/pool/errors/PoolErrors.sol";

/// @dev Mock verifier — returns configurable result for any proof.
contract MockUTXOVerifier is IUTXOVerifier {
    bool private _result;
    constructor(bool result) { _result = result; }
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[13] calldata
    ) external view returns (bool) { return _result; }
}

contract MARKPoolTest is Test {
    MARKPool internal pool;
    RYLA internal token;
    MockUTXOVerifier internal mockOk;
    MockUTXOVerifier internal mockFail;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal user = makeAddr("user");
    address internal relayer = makeAddr("relayer");

    // Valid field element commitments/nullifiers (< SNARK_SCALAR_FIELD)
    bytes32 internal C0 = bytes32(uint256(1));
    bytes32 internal C1 = bytes32(uint256(2));
    bytes32 internal N0 = bytes32(uint256(3));
    bytes32 internal N1 = bytes32(uint256(4));

    uint256[2] internal A = [uint256(0), uint256(0)];
    uint256[2][2] internal B = [[uint256(0), uint256(0)], [uint256(0), uint256(0)]];
    uint256[2] internal C_ = [uint256(0), uint256(0)];

    function setUp() public {
        vm.startPrank(admin);
        token = new RYLA(admin);
        pool = new MARKPool(admin, address(token));
        mockOk = new MockUTXOVerifier(true);
        mockFail = new MockUTXOVerifier(false);

        pool.setOperator(operator, true);
        pool.setVerifier(address(mockOk));

        // Grant pool MINTER_ROLE and BURNER_ROLE
        token.setMinter(address(pool), true);
        token.setBurner(address(pool), true);
        vm.stopPrank();

        // Mint tokens to user for deposit tests
        vm.prank(admin);
        token.setMinter(admin, true);
        vm.prank(admin);
        token.mint(user, 100 ether);
    }

    function testDepositInsertsCommitmentAndBurnsTokens() public {
        vm.prank(user);
        token.approve(address(pool), 10 ether);

        vm.prank(operator);
        pool.deposit(user, 10 ether, C0);

        assertEq(token.balanceOf(user), 90 ether);
        assertEq(token.balanceOf(address(pool)), 0); // burned on deposit
    }

    function testDepositRevertsForZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(PoolErrors.InvalidAmount.selector);
        pool.deposit(user, 0, C0);
    }

    function testDepositRevertsForZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert();
        pool.deposit(address(0), 10 ether, C0);
    }

    function testDepositRevertsForInvalidCommitment() public {
        vm.prank(user);
        token.approve(address(pool), 10 ether);
        vm.prank(operator);
        vm.expectRevert(PoolErrors.CommitmentInvalid.selector);
        pool.deposit(user, 10 ether, bytes32(0));
    }

    function testTransactSucceedsWithValidProof() public {
        // Insert commitments so root is known
        _seedCommitments();

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory outCommitments = [bytes32(uint256(5)), bytes32(uint256(6))];

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: nullifiers,
            outCommitments: outCommitments,
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        pool.transact(p);

        assertTrue(pool.usedNullifiers(N0));
        assertTrue(pool.usedNullifiers(N1));
    }

    function testTransactRevertsWithInvalidProof() public {
        vm.prank(admin);
        pool.setVerifier(address(mockFail));

        _seedCommitments();
        bytes32 root = pool.getMerkleRoot();

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        vm.expectRevert(PoolErrors.InvalidProof.selector);
        pool.transact(p);
    }

    function testTransactRevertsOnNullifierReplay() public {
        _seedCommitments();
        bytes32 root = pool.getMerkleRoot();

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        pool.transact(p);

        // Second transact with same nullifiers — new output commitments
        MARKPool.TransactParams memory p2 = MARKPool.TransactParams({
            merkleRoot: pool.getMerkleRoot(),
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(7)), bytes32(uint256(8))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        vm.expectRevert(PoolErrors.NullifierUsed.selector);
        pool.transact(p2);
    }

    function testTransactRevertsOnUnknownRoot() public {
        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: bytes32(uint256(999)),
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        vm.expectRevert(PoolErrors.UnknownRoot.selector);
        pool.transact(p);
    }

    function testTransactRevertsOnExpiredRoot() public {
        _seedCommitments();
        bytes32 root = pool.getMerkleRoot();

        // Warp past MAX_ROOT_AGE
        vm.warp(block.timestamp + pool.MAX_ROOT_AGE() + 1);

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });

        vm.expectRevert(PoolErrors.RootExpired.selector);
        pool.transact(p);
    }

    function testWithdrawBindingAndWithdraw() public {
        _seedCommitments();
        bytes32 root = pool.getMerkleRoot();

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });
        MARKPool.WithdrawBindingParams memory w = MARKPool.WithdrawBindingParams({
            withdrawOwner: user,
            withdrawRecipient: user,
            withdrawAmount: 10 ether
        });

        pool.transactWithWithdrawBinding(p, w);

        assertEq(token.balanceOf(user), 80 ether); // deposited 20, balance is 80

        vm.prank(operator);
        pool.withdraw(N0, user, user, 10 ether);

        assertEq(token.balanceOf(user), 90 ether); // withdrew 10, balance is 90
    }

    function testWithdrawRevertsOnBindingMismatch() public {
        _seedCommitments();
        bytes32 root = pool.getMerkleRoot();

        MARKPool.TransactParams memory p = MARKPool.TransactParams({
            merkleRoot: root,
            nullifiers: [N0, N1],
            outCommitments: [bytes32(uint256(5)), bytes32(uint256(6))],
            fee: 0,
            relayer: address(0),
            a: A,
            b: B,
            c: C_
        });
        MARKPool.WithdrawBindingParams memory w = MARKPool.WithdrawBindingParams({
            withdrawOwner: user,
            withdrawRecipient: user,
            withdrawAmount: 10 ether
        });

        pool.transactWithWithdrawBinding(p, w);

        vm.prank(operator);
        vm.expectRevert(PoolErrors.WithdrawBindingMismatch.selector);
        pool.withdraw(N0, user, makeAddr("other"), 10 ether);
    }

    function testWithdrawRevertsOnBindingNotFound() public {
        vm.prank(operator);
        vm.expectRevert(PoolErrors.WithdrawBindingNotFound.selector);
        pool.withdraw(N0, user, user, 10 ether);
    }

    function testProductionModeBlocksVerifierChange() public {
        vm.startPrank(admin);
        pool.activateProductionMode();
        vm.expectRevert(PoolErrors.ProductionModeAlreadyEnabled.selector);
        pool.setVerifier(address(mockOk));
        vm.stopPrank();
    }

    function testSetProtocolEpochCanOnlyIncrease() public {
        vm.prank(admin);
        pool.setProtocolEpoch(5);

        vm.prank(admin);
        vm.expectRevert(PoolErrors.EpochCanOnlyIncrease.selector);
        pool.setProtocolEpoch(3);
    }

    // Helper: deposit two commitments so the pool has a non-empty tree and known root
    function _seedCommitments() internal {
        vm.prank(user);
        token.approve(address(pool), 20 ether);
        vm.startPrank(operator);
        pool.deposit(user, 10 ether, C0);
        pool.deposit(user, 10 ether, C1);
        vm.stopPrank();
    }
}
