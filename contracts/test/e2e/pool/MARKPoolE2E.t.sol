// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {MARKWithdrawAdapter} from "../../../src/withdraw/MARKWithdrawAdapter.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {IVerifier} from "../../../src/interfaces/IVerifier.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract AlwaysValidVerifier is IVerifier {
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[13] calldata
    ) external pure returns (bool) { return true; }
}

/// @notice End-to-end test for the full pool withdrawal flow:
///   1. Operator mints RYLA to user via MARKSettlementModule
///   2. User calls pool.transactWithWithdrawBinding (ZK proof verified by mock)
///   3. User calls adapter.withdrawWithSig (burns RYLA, pays ETH to recipient)
contract MARKPoolE2ETest is Test {
    RYLA internal token;
    MARKPool internal pool;
    RYLACreditLedger internal ledger;
    MARKWithdrawAdapter internal adapter;
    MARKSettlementModule internal settlement;
    AccessManager internal accessManager;
    AlwaysValidVerifier internal verifier;

    address internal admin = makeAddr("admin");
    address internal settlementOperator = makeAddr("settlementOperator");
    address internal recipient = makeAddr("recipient");

    uint256 internal ownerPk = 0xA11CE;
    uint256 internal intentSignerPk = 0xB0B;
    address internal creditOwner;
    address internal intentSigner;

    uint64 internal constant POOL_ADMIN_ROLE = 1;
    uint256 internal constant MINT_AMOUNT = 1 ether;

    // Unique nullifiers and commitments for the pool transact call
    bytes32 internal constant N0 = bytes32(uint256(0xDEAD1));
    bytes32 internal constant N1 = bytes32(uint256(0xDEAD2));
    bytes32 internal constant C0 = bytes32(uint256(0xBEEF1));
    bytes32 internal constant C1 = bytes32(uint256(0xBEEF2));

    uint256[2] internal A;
    uint256[2][2] internal B;
    uint256[2] internal C_PROOF;

    function setUp() public {
        creditOwner = vm.addr(ownerPk);
        intentSigner = vm.addr(intentSignerPk);

        // Deploy token
        vm.prank(admin);
        token = new RYLA(admin);

        // Deploy settlement module (to mint RYLA to creditOwner)
        vm.prank(admin);
        settlement = new MARKSettlementModule(admin, address(token));

        // Deploy pool stack
        verifier = new AlwaysValidVerifier();

        vm.startPrank(admin);
        accessManager = new AccessManager(admin);
        address poseidon = deployCode("PoseidonT3.sol:PoseidonT3");
        pool = new MARKPool(address(accessManager), address(verifier), poseidon);
        ledger = new RYLACreditLedger(address(token), address(pool));
        adapter = new MARKWithdrawAdapter(address(accessManager), address(ledger), address(pool));
        ledger.setAdapter(address(adapter));

        // Configure AccessManager
        accessManager.grantRole(POOL_ADMIN_ROLE, admin, 0);

        bytes4[] memory poolSelectors = new bytes4[](3);
        poolSelectors[0] = pool.setAssetLedger.selector;
        poolSelectors[1] = pool.setProofTypeEnabled.selector;
        poolSelectors[2] = pool.pauseWithdrawals.selector;
        accessManager.setTargetFunctionRole(address(pool), poolSelectors, POOL_ADMIN_ROLE);

        bytes4[] memory adapterSelectors = new bytes4[](2);
        adapterSelectors[0] = adapter.setIntentSigner.selector;
        adapterSelectors[1] = adapter.setMaxIntentValidity.selector;
        accessManager.setTargetFunctionRole(address(adapter), adapterSelectors, POOL_ADMIN_ROLE);

        vm.warp(block.timestamp + 1);

        pool.setAssetLedger(address(ledger));
        adapter.setIntentSigner(intentSigner, true);

        // Wire RYLA roles
        settlement.setOperator(settlementOperator, true);
        token.setMinter(address(settlement), true);
        token.setBurner(address(settlement), true);
        token.setMinter(address(ledger), true);
        token.setBurner(address(ledger), true);
        vm.stopPrank();
    }

    /// @dev Full flow: mint RYLA -> transactWithWithdrawBinding -> withdrawWithSig
    function testFullWithdrawalFlow() public {
        // Step 1: Mint RYLA to creditOwner via settlement module
        vm.prank(settlementOperator);
        settlement.settleMint(creditOwner, MINT_AMOUNT, keccak256("e2e-mint"), bytes(""));
        assertEq(token.balanceOf(creditOwner), MINT_AMOUNT);

        // Step 2: creditOwner approves ledger to burn their RYLA
        vm.prank(creditOwner);
        token.approve(address(ledger), MINT_AMOUNT);

        // Step 3: transactWithWithdrawBinding — records withdraw binding for (creditOwner, recipient, MINT_AMOUNT)
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0),
            creditOwner, recipient, MINT_AMOUNT,
            A, B, C_PROOF
        );

        assertTrue(pool.isNullifierUsedGlobal(N0));
        assertTrue(pool.isNullifierUsedGlobal(N1));
        assertEq(
            pool.nullifierWithdrawBinding(N0),
            pool.computeWithdrawBindingHash(creditOwner, recipient, MINT_AMOUNT)
        );

        // Step 4: Fund adapter with ETH to pay recipient
        vm.deal(address(adapter), MINT_AMOUNT);

        // Step 5: Build signatures for withdrawWithSig
        uint256 nonce = adapter.withdrawNonce(creditOwner);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 intentHash = adapter.computeWithdrawIntentHash(
            creditOwner, recipient, MINT_AMOUNT, nullifiers, nonce, deadline
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(intentHash);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPk, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(intentSignerPk, digest);
        bytes memory ownerSig = abi.encodePacked(r1, s1, v1);
        bytes memory intentSig = abi.encodePacked(r2, s2, v2);

        // Step 6: Execute withdrawal — burns RYLA, sends ETH to recipient
        uint256 recipientEthBefore = recipient.balance;

        adapter.withdrawWithSig(
            creditOwner, recipient, MINT_AMOUNT,
            nullifiers, nonce, deadline,
            ownerSig, intentSig
        );

        // Verify RYLA burned
        assertEq(token.balanceOf(creditOwner), 0);
        assertEq(token.totalSupply(), 0);

        // Verify ETH paid to recipient
        assertEq(recipient.balance, recipientEthBefore + MINT_AMOUNT);

        // Verify nonce incremented
        assertEq(adapter.withdrawNonce(creditOwner), nonce + 1);
    }

    /// @dev Replay of the same nullifiers is rejected by the adapter.
    function testNullifierReplayRejected() public {
        vm.prank(settlementOperator);
        settlement.settleMint(creditOwner, MINT_AMOUNT * 2, keccak256("e2e-mint-2"), bytes(""));

        vm.prank(creditOwner);
        token.approve(address(ledger), MINT_AMOUNT * 2);

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0),
            creditOwner, recipient, MINT_AMOUNT,
            A, B, C_PROOF
        );

        vm.deal(address(adapter), MINT_AMOUNT * 2);

        uint256 nonce = adapter.withdrawNonce(creditOwner);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 intentHash = adapter.computeWithdrawIntentHash(
            creditOwner, recipient, MINT_AMOUNT, nullifiers, nonce, deadline
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(intentHash);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPk, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(intentSignerPk, digest);

        adapter.withdrawWithSig(
            creditOwner, recipient, MINT_AMOUNT,
            nullifiers, nonce, deadline,
            abi.encodePacked(r1, s1, v1),
            abi.encodePacked(r2, s2, v2)
        );

        // Second attempt with same nullifiers must revert with NullifierAlreadyClaimed
        uint256 nonce2 = adapter.withdrawNonce(creditOwner);
        bytes32 intentHash2 = adapter.computeWithdrawIntentHash(
            creditOwner, recipient, MINT_AMOUNT, nullifiers, nonce2, deadline
        );
        bytes32 digest2 = MessageHashUtils.toEthSignedMessageHash(intentHash2);
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(ownerPk, digest2);
        (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(intentSignerPk, digest2);

        vm.expectRevert();
        adapter.withdrawWithSig(
            creditOwner, recipient, MINT_AMOUNT,
            nullifiers, nonce2, deadline,
            abi.encodePacked(r3, s3, v3),
            abi.encodePacked(r4, s4, v4)
        );
    }

    /// @dev Withdraw binding mismatch (wrong recipient) is rejected.
    function testBindingMismatchRejected() public {
        vm.prank(settlementOperator);
        settlement.settleMint(creditOwner, MINT_AMOUNT, keccak256("e2e-mint-3"), bytes(""));

        vm.prank(creditOwner);
        token.approve(address(ledger), MINT_AMOUNT);

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        // Bind to `recipient`
        pool.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0),
            creditOwner, recipient, MINT_AMOUNT,
            A, B, C_PROOF
        );

        vm.deal(address(adapter), MINT_AMOUNT);

        address wrongRecipient = makeAddr("wrong");
        uint256 nonce = adapter.withdrawNonce(creditOwner);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 intentHash = adapter.computeWithdrawIntentHash(
            creditOwner, wrongRecipient, MINT_AMOUNT, nullifiers, nonce, deadline
        );
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(intentHash);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerPk, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(intentSignerPk, digest);

        vm.expectRevert();
        adapter.withdrawWithSig(
            creditOwner, wrongRecipient, MINT_AMOUNT,
            nullifiers, nonce, deadline,
            abi.encodePacked(r1, s1, v1),
            abi.encodePacked(r2, s2, v2)
        );
    }
}
