// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {IVerifier} from "../../../src/interfaces/IVerifier.sol";
import {PoolErrors} from "../../../src/pool/errors/PoolErrors.sol";
import {NullifierErrors} from "../../../src/errors/NullifierErrors.sol";

contract MockVerifier is IVerifier {
    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[13] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

/// @notice Cross-chain double-spend protection test.
/// @dev Verifies that a nullifier spent on one chain cannot be spent on another chain
///      via bridgeIn. The bridgeIn function adds output commitments from the source
///      chain to the destination chain's pool, but does NOT mark nullifiers as spent.
///      If a user tries to spend the same nullifier on the destination chain, it must revert.
contract CrossChainDoubleSpendTest is Test {
    MARKPool internal poolA;
    MARKPool internal poolB;
    RYLACreditLedger internal ledgerA;
    RYLACreditLedger internal ledgerB;
    RYLA internal tokenA;
    RYLA internal tokenB;
    MockVerifier internal verifier;
    AccessManager internal accessManagerA;
    AccessManager internal accessManagerB;

    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");

    // Valid field elements for commitments/nullifiers
    bytes32 internal constant C0 = bytes32(uint256(1));
    bytes32 internal constant C1 = bytes32(uint256(2));
    bytes32 internal constant N0 = bytes32(uint256(3));
    bytes32 internal constant N1 = bytes32(uint256(4));

    uint256[2] internal A;
    uint256[2][2] internal B;
    uint256[2] internal C;

    // Chain IDs for fork simulation
    uint256 internal constant CHAIN_A_ID = 900;
    uint256 internal constant CHAIN_B_ID = 901;

    function setUp() public {
        verifier = new MockVerifier();

        // ============ CHAIN A SETUP ============
        vm.startPrank(admin);
        tokenA = new RYLA(admin);
        accessManagerA = new AccessManager(admin);
        address poseidonA = deployCode("PoseidonT3.sol:PoseidonT3");
        poolA = new MARKPool(address(accessManagerA), address(verifier), poseidonA);
        ledgerA = new RYLACreditLedger(address(tokenA), address(poolA));

        bytes4[] memory selectorsA = new bytes4[](6);
        selectorsA[0] = poolA.setAssetLedger.selector;
        selectorsA[1] = poolA.bridgeIn.selector;
        selectorsA[2] = poolA.pauseWithdrawals.selector;
        selectorsA[3] = poolA.unpauseWithdrawals.selector;
        selectorsA[4] = poolA.setProtocolEpoch.selector;
        selectorsA[5] = poolA.setSupportedChain.selector;
        accessManagerA.setTargetFunctionRole(address(poolA), selectorsA, 1);
        accessManagerA.grantRole(1, admin, 0);
        vm.warp(block.timestamp + 1);

        poolA.setAssetLedger(address(ledgerA));
        tokenA.setMinter(address(ledgerA), true);
        tokenA.setBurner(address(ledgerA), true);
        vm.stopPrank();

        // ============ CHAIN B SETUP ============
        vm.startPrank(admin);
        tokenB = new RYLA(admin);
        accessManagerB = new AccessManager(admin);
        address poseidonB = deployCode("PoseidonT3.sol:PoseidonT3");
        poolB = new MARKPool(address(accessManagerB), address(verifier), poseidonB);
        ledgerB = new RYLACreditLedger(address(tokenB), address(poolB));

        bytes4[] memory selectorsB = new bytes4[](6);
        selectorsB[0] = poolB.setAssetLedger.selector;
        selectorsB[1] = poolB.bridgeIn.selector;
        selectorsB[2] = poolB.pauseWithdrawals.selector;
        selectorsB[3] = poolB.unpauseWithdrawals.selector;
        selectorsB[4] = poolB.setProtocolEpoch.selector;
        selectorsB[5] = poolB.setSupportedChain.selector;
        accessManagerB.setTargetFunctionRole(address(poolB), selectorsB, 1);
        accessManagerB.grantRole(1, admin, 0);
        vm.warp(block.timestamp + 1);

        poolB.setAssetLedger(address(ledgerB));
        tokenB.setMinter(address(ledgerB), true);
        tokenB.setBurner(address(ledgerB), true);
        vm.stopPrank();

        // Enable cross-chain nullifier sync between pools
        vm.prank(admin);
        poolA.setSupportedChain(CHAIN_B_ID, true);

        vm.prank(admin);
        poolB.setSupportedChain(CHAIN_A_ID, true);
    }

    /// @notice Spend nullifier on chain A, then try to spend same nullifier on chain A again.
    function testCrossChainDoubleSpendRevertsOnSamePool() public {
        bytes32 rootA = poolA.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        // Spend on chain A
        poolA.transact(rootA, nullifiers, commitments, 0, address(0), A, B, C);

        // Verify nullifiers marked as spent on chain A
        assertTrue(poolA.isNullifierUsedGlobal(N0));
        assertTrue(poolA.isNullifierUsedGlobal(N1));

        // Attempt to spend SAME nullifiers on chain A again → should fail
        bytes32 newRootA = poolA.getMerkleRoot();
        bytes32[2] memory commitments2 = [bytes32(uint256(5)), bytes32(uint256(6))];
        vm.expectRevert(NullifierErrors.NullifierUsed.selector);
        poolA.transact(newRootA, nullifiers, commitments2, 0, address(0), A, B, C);
    }

    /// @notice Cross-chain double-spend protection via L2ToL2CrossDomainMessenger sync.
    /// @dev Simulated: spend on chain A, sync nullifiers to chain B via cross-chain message,
    ///      then try to spend same nullifier on chain B.
    function testCrossChainDoubleSpendViaNullifierSync() public {
        // 1. Spend on chain A (source chain)
        bytes32 rootA = poolA.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        poolA.transact(rootA, nullifiers, commitments, 0, address(0), A, B, C);

        // 2. Verify nullifiers are spent on chain A
        assertTrue(poolA.isNullifierUsedGlobal(N0));
        assertTrue(poolA.isNullifierUsedGlobal(N1));

        // 3. Simulate cross-chain nullifier sync: Chain B receives sync from Chain A
        //    Using test-only function to bypass cross-domain messenger
        poolB.syncNullifiersForTest(CHAIN_A_ID, N0, N1);

        // 4. Verify nullifiers are now marked as spent on chain B
        assertTrue(poolB.isNullifierUsedGlobal(N0));
        assertTrue(poolB.isNullifierUsedGlobal(N1));

        // 5. TRY TO SPEND THE SAME NULLIFIERS on chain B → MUST FAIL
        bytes32 rootB = poolB.getMerkleRoot();
        bytes32[2] memory commitmentsB = [bytes32(uint256(5)), bytes32(uint256(6))];
        vm.expectRevert(NullifierErrors.NullifierUsed.selector);
        poolB.transact(rootB, nullifiers, commitmentsB, 0, address(0), A, B, C);
    }

    /// @notice BridgeIn replay protection - same messageId cannot be processed twice.
    function testBridgeInReplayReverts() public {
        bytes32[2] memory commitments = [C0, C1];
        bytes32 messageId = bytes32(uint256(999));

        vm.prank(admin);
        poolB.bridgeIn(CHAIN_A_ID, messageId, commitments);

        vm.prank(admin);
        vm.expectRevert(PoolErrors.BridgeMessageAlreadyProcessed.selector);
        poolB.bridgeIn(CHAIN_A_ID, messageId, commitments);
    }

    /// @notice BridgeIn rejects same chain (source == destination).
    function testBridgeInSameChainReverts() public {
        bytes32[2] memory commitments = [C0, C1];

        vm.prank(admin);
        vm.expectRevert(PoolErrors.SourceIsDestination.selector);
        poolB.bridgeIn(block.chainid, bytes32(uint256(1)), commitments);
    }

    /// @notice BridgeIn rejects zero commitments.
    function testBridgeInZeroCommitmentReverts() public {
        bytes32[2] memory commitments = [bytes32(0), C1];

        vm.prank(admin);
        vm.expectRevert(PoolErrors.CommitmentInvalid.selector);
        poolB.bridgeIn(CHAIN_A_ID, bytes32(uint256(1)), commitments);
    }

    /// @notice BridgeIn rejects duplicate commitments.
    function testBridgeInDuplicateCommitmentReverts() public {
        bytes32[2] memory commitments = [C0, C0];

        vm.prank(admin);
        vm.expectRevert(PoolErrors.CommitmentDuplicate.selector);
        poolB.bridgeIn(CHAIN_A_ID, bytes32(uint256(1)), commitments);
    }

    /// @notice SyncNullifiers rejects unsupported chains.
    function testSyncNullifiersRevertsOnUnsupportedChain() public {
        bytes32[2] memory nullifiers = [bytes32(uint256(100)), bytes32(uint256(101))];

        // Chain C (902) is not supported by poolB
        vm.expectRevert(PoolErrors.InvalidSource.selector);
        poolB.syncNullifiersForTest(902, nullifiers[0], nullifiers[1]);
    }

    /// @notice SyncNullifiers only marks nullifiers once (idempotent).
    function testSyncNullifiersIsIdempotent() public {
        // Already enabled in setUp: poolB.setSupportedChain(CHAIN_A_ID, true)

        bytes32 n0 = bytes32(uint256(200));
        bytes32 n1 = bytes32(uint256(201));

        // First sync
        poolB.syncNullifiersForTest(CHAIN_A_ID, n0, n1);
        assertTrue(poolB.isNullifierUsedGlobal(n0));
        assertTrue(poolB.isNullifierUsedGlobal(n1));

        // Second sync with same nullifiers - should not revert, just be idempotent
        poolB.syncNullifiersForTest(CHAIN_A_ID, n0, n1);
        assertTrue(poolB.isNullifierUsedGlobal(n0));
        assertTrue(poolB.isNullifierUsedGlobal(n1));
    }
}
