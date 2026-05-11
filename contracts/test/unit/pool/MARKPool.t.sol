// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {IUTXOVerifier} from "../../../src/pool/interfaces/IUTXOVerifier.sol";
import {PoolErrors} from "../../../src/pool/errors/PoolErrors.sol";

contract MockUTXOVerifier is IUTXOVerifier {
    bool private _result;
    constructor(bool result) { _result = result; }
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[4] calldata
    ) external view returns (bool) { return _result; }
}

contract MARKPoolTest is Test {
    MARKPool internal pool;
    RYLA internal token;
    MockUTXOVerifier internal mockOk;
    MockUTXOVerifier internal mockFail;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal recipient = makeAddr("recipient");

    bytes32 internal constant COMMITMENT = bytes32(uint256(1));
    bytes32 internal constant NULLIFIER = bytes32(uint256(2));
    uint256 internal constant AMOUNT = 10 ether;

    uint256[2] internal A;
    uint256[2][2] internal B;
    uint256[2] internal C;

    function setUp() public {
        vm.startPrank(admin);
        token = new RYLA(admin);
        pool = new MARKPool(admin, address(token));
        mockOk = new MockUTXOVerifier(true);
        mockFail = new MockUTXOVerifier(false);

        pool.setOperator(operator, true);
        pool.setVerifier(address(mockOk));

        token.setMinter(address(pool), true);
        vm.stopPrank();
    }

    function testCommitRegistersNote() public {
        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);
        assertEq(pool.commitments(COMMITMENT), AMOUNT);
    }

    function testCommitRevertsForZeroCommitment() public {
        vm.prank(operator);
        vm.expectRevert(PoolErrors.CommitmentInvalid.selector);
        pool.commit(bytes32(0), AMOUNT);
    }

    function testCommitRevertsForZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(PoolErrors.InvalidAmount.selector);
        pool.commit(COMMITMENT, 0);
    }

    function testCommitRevertsForDuplicate() public {
        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);
        vm.prank(operator);
        vm.expectRevert(PoolErrors.CommitmentDuplicate.selector);
        pool.commit(COMMITMENT, AMOUNT);
    }

    function testWithdrawMintsToRecipient() public {
        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);

        pool.withdraw(recipient, AMOUNT, NULLIFIER, COMMITMENT, A, B, C);

        assertEq(token.balanceOf(recipient), AMOUNT);
        assertTrue(pool.usedNullifiers(NULLIFIER));
        assertEq(pool.commitments(COMMITMENT), 0);
    }

    function testWithdrawRevertsOnInvalidProof() public {
        vm.prank(admin);
        pool.setVerifier(address(mockFail));

        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);

        vm.expectRevert(PoolErrors.InvalidProof.selector);
        pool.withdraw(recipient, AMOUNT, NULLIFIER, COMMITMENT, A, B, C);
    }

    function testWithdrawRevertsOnNullifierReplay() public {
        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);
        pool.withdraw(recipient, AMOUNT, NULLIFIER, COMMITMENT, A, B, C);

        bytes32 commitment2 = bytes32(uint256(3));
        vm.prank(operator);
        pool.commit(commitment2, AMOUNT);

        vm.expectRevert(PoolErrors.NullifierUsed.selector);
        pool.withdraw(recipient, AMOUNT, NULLIFIER, commitment2, A, B, C);
    }

    function testWithdrawRevertsOnAmountMismatch() public {
        vm.prank(operator);
        pool.commit(COMMITMENT, AMOUNT);

        vm.expectRevert(PoolErrors.CommitmentInvalid.selector);
        pool.withdraw(recipient, AMOUNT + 1, NULLIFIER, COMMITMENT, A, B, C);
    }

    function testWithdrawRevertsOnUnregisteredCommitment() public {
        vm.expectRevert(PoolErrors.CommitmentInvalid.selector);
        pool.withdraw(recipient, AMOUNT, NULLIFIER, COMMITMENT, A, B, C);
    }

    function testProductionModeBlocksVerifierChange() public {
        vm.startPrank(admin);
        pool.activateProductionMode();
        vm.expectRevert(PoolErrors.ProductionModeAlreadyEnabled.selector);
        pool.setVerifier(address(mockOk));
        vm.stopPrank();
    }
}
