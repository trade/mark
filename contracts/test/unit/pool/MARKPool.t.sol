// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {PoolErrors} from "../../../src/pool/errors/PoolErrors.sol";
import {IVerifier} from "../../../src/interfaces/IVerifier.sol";
import {ICreditLedger} from "../../../src/interfaces/ICreditLedger.sol";

contract MockVerifier is IVerifier {
    bool private _result;

    constructor(bool result) {
        _result = result;
    }

    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[13] calldata)
        external
        view
        returns (bool)
    {
        return _result;
    }
}

contract MockLedger is ICreditLedger {
    mapping(address => uint256) public balances;
    uint256 public minted;
    uint256 public burned;

    function credit(address to, uint256 amount) external {
        balances[to] += amount;
        minted += amount;
    }

    function debit(address from, uint256 amount) external {
        require(balances[from] >= amount, "MockLedger: insufficient balance");
        balances[from] -= amount;
        burned += amount;
    }

    function creditBalanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function totalCreditsMinted() external view returns (uint256) {
        return minted;
    }

    function totalCreditsBurned() external view returns (uint256) {
        return burned;
    }

    function totalCreditsOutstanding() external view returns (uint256) {
        return minted - burned;
    }

    function maxCredits() external pure returns (uint256) {
        return type(uint256).max;
    }
}

contract MARKPoolTest is Test {
    MARKPool internal pool;
    MockVerifier internal mockOk;
    MockVerifier internal mockFail;
    MockLedger internal ledger;
    AccessManager internal accessManager;

    address internal admin = makeAddr("admin");

    // Valid BN254 field elements for commitments/nullifiers
    bytes32 internal constant C0 = bytes32(uint256(1));
    bytes32 internal constant C1 = bytes32(uint256(2));
    bytes32 internal constant N0 = bytes32(uint256(3));
    bytes32 internal constant N1 = bytes32(uint256(4));

    uint256[2] internal A;
    uint256[2][2] internal B;
    uint256[2] internal C_PROOF;

    function setUp() public {
        mockOk = new MockVerifier(true);
        mockFail = new MockVerifier(false);
        ledger = new MockLedger();

        vm.startPrank(admin);
        accessManager = new AccessManager(admin);
        address poseidon = deployCode("PoseidonT3.sol:PoseidonT3");
        pool = new MARKPool(address(accessManager), address(mockOk), poseidon);

        // Grant admin all restricted selectors via a custom role (role 1)
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = pool.pause.selector;
        selectors[1] = pool.unpause.selector;
        selectors[2] = pool.pauseWithdrawals.selector;
        selectors[3] = pool.unpauseWithdrawals.selector;
        selectors[4] = pool.setVerifier.selector;
        selectors[5] = pool.setProofTypeEnabled.selector;
        selectors[6] = pool.emergencyDisableProofType.selector;
        selectors[7] = pool.setMaxRootAge.selector;
        selectors[8] = pool.setFeeBurnBps.selector;
        selectors[9] = pool.setMinFee.selector;
        selectors[10] = pool.setProtocolEpoch.selector;
        selectors[11] = pool.setBridgeOutEntrypoint.selector;
        selectors[12] = pool.bridgeIn.selector;
        selectors[13] = pool.setAssetLedger.selector;
        accessManager.setTargetFunctionRole(address(pool), selectors, 1);
        accessManager.grantRole(1, admin, 0);
        // AccessManager role grants become effective after the current timestamp boundary;
        // advance by 1 second so the granted role is active before invoking restricted functions.
        vm.warp(block.timestamp + 1);
        pool.setAssetLedger(address(ledger));
        vm.stopPrank();
    }

    // --- transact ---

    function testTransactHappyPath() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);

        assertTrue(pool.isNullifierUsedGlobal(N0));
        assertTrue(pool.isNullifierUsedGlobal(N1));
    }

    function testTransactRevertsOnNullifierReplay() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);

        // New commitments, same nullifiers
        bytes32[2] memory commitments2 = [bytes32(uint256(5)), bytes32(uint256(6))];
        vm.expectRevert(PoolErrors.NullifierUsed.selector);
        pool.transact(root, nullifiers, commitments2, 0, address(0), A, B, C_PROOF);
    }

    function testTransactRevertsOnUnknownRoot() public {
        bytes32 badRoot = bytes32(uint256(999));
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.UnknownRoot.selector);
        pool.transact(badRoot, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    function testTransactRevertsOnInvalidProof() public {
        // Swap to failing verifier
        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setVerifier(pool.PROOF_TYPE_TRANSFER(), address(mockFail));
        pool.unpauseWithdrawals();
        vm.stopPrank();

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.InvalidProof.selector);
        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    function testTransactRevertsOnDuplicateNullifiers() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N0]; // duplicate
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.NullifierDuplicate.selector);
        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    function testTransactRevertsOnDuplicateCommitments() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C0]; // duplicate

        vm.expectRevert(PoolErrors.CommitmentDuplicate.selector);
        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    function testTransactRevertsWhenWithdrawalsPaused() public {
        vm.prank(admin);
        pool.pauseWithdrawals();

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.WithdrawalsArePaused.selector);
        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    // --- root expiry ---

    function testRootExpiresAfterMaxRootAge() public {
        // First transact to add a new root
        bytes32 initialRoot = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];
        pool.transact(initialRoot, nullifiers, commitments, 0, address(0), A, B, C_PROOF);

        // Set max root age (tightening from 0 requires pause)
        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setMaxRootAge(1 days);
        pool.unpauseWithdrawals();
        vm.stopPrank();

        // Warp past expiry
        vm.warp(block.timestamp + 2 days);

        // initialRoot should now be expired (not the latest root)
        assertFalse(pool.isRootUsable(initialRoot));
    }

    function testLatestRootAlwaysUsable() public {
        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setMaxRootAge(1 days);
        pool.unpauseWithdrawals();
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        // Latest root is always usable regardless of age
        assertTrue(pool.isRootUsable(pool.getMerkleRoot()));
    }

    // --- fee ---

    function testFeeCreditedToRelayer() public {
        address relayer = makeAddr("relayer");
        // feeBurnBps defaults to 0, so all fee goes to relayer — no state change needed

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transact(root, nullifiers, commitments, 100, relayer, A, B, C_PROOF);

        assertEq(ledger.balances(relayer), 100);
    }

    function testFeeRevertsWithZeroRelayerWhenFeeNonZero() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.InvalidRelayer.selector);
        pool.transact(root, nullifiers, commitments, 100, address(0), A, B, C_PROOF);
    }

    function testFeeTooLowReverts() public {
        vm.prank(admin);
        pool.setMinFee(1);

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.FeeTooLow.selector);
        pool.transact(root, nullifiers, commitments, 0, address(0), A, B, C_PROOF);
    }

    // --- pruneRoots ---

    function testPruneRootsRemovesExpiredRoots() public {
        bytes32 initialRoot = pool.getMerkleRoot();

        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setMaxRootAge(1 days);
        pool.unpauseWithdrawals();
        vm.stopPrank();

        // Add a new root
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];
        pool.transact(initialRoot, nullifiers, commitments, 0, address(0), A, B, C_PROOF);

        vm.warp(block.timestamp + 2 days);

        uint256 pruned = pool.pruneRoots(10);
        assertGt(pruned, 0);
        assertFalse(pool.knownRoots(initialRoot));
    }

    // --- bridgeOut access control ---

    function testBridgeOutRevertsWhenEntrypointNotSet() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.BridgeOutDisabled.selector);
        pool.bridgeOut(root, nullifiers, commitments, 0, address(0), 902, A, B, C_PROOF);
    }

    function testBridgeOutRevertsWhenCallerNotEntrypoint() public {
        address entrypoint = makeAddr("entrypoint");
        vm.etch(entrypoint, hex"00");

        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setBridgeOutEntrypoint(entrypoint);
        pool.unpauseWithdrawals();
        vm.stopPrank();

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.UnauthorizedBridgeOutCaller.selector);
        pool.bridgeOut(root, nullifiers, commitments, 0, address(0), 902, A, B, C_PROOF);
    }

    // --- bridgeIn access control ---

    function testBridgeInRevertsWhenCallerNotRestricted() public {
        bytes32[2] memory commitments = [C0, C1];
        vm.expectRevert(abi.encodeWithSignature("AccessManagedUnauthorized(address)", address(this)));
        pool.bridgeIn(901, bytes32(uint256(1)), commitments);
    }

    function testBridgeInRevertsOnSameChain() public {
        bytes32[2] memory commitments = [C0, C1];
        vm.prank(admin);
        vm.expectRevert(PoolErrors.SourceIsDestination.selector);
        pool.bridgeIn(block.chainid, bytes32(uint256(1)), commitments);
    }

    function testBridgeInRevertsOnMessageReplay() public {
        bytes32[2] memory commitments = [C0, C1];
        bytes32 messageId = bytes32(uint256(123));

        vm.prank(admin);
        pool.bridgeIn(901, messageId, commitments);

        vm.prank(admin);
        vm.expectRevert(PoolErrors.BridgeMessageAlreadyProcessed.selector);
        pool.bridgeIn(901, messageId, commitments);
    }

    // --- transactWithWithdrawBinding ---

    function testTransactWithWithdrawBindingRecordsBinding() public {
        address owner = makeAddr("owner");
        address recipient = makeAddr("recipient");
        uint256 amount = 1 ether;

        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        pool.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0), owner, recipient, amount, A, B, C_PROOF
        );

        bytes32 expectedBinding = pool.computeWithdrawBindingHash(owner, recipient, amount);
        assertEq(pool.nullifierWithdrawBinding(N0), expectedBinding);
        assertEq(pool.nullifierWithdrawBinding(N1), expectedBinding);
    }

    function testTransactWithWithdrawBindingRevertsOnZeroAmount() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];

        vm.expectRevert(PoolErrors.InvalidWithdrawAmount.selector);
        pool.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0), makeAddr("o"), makeAddr("r"), 0, A, B, C_PROOF
        );
    }

    // --- admin config ---

    function testSetVerifierRequiresPauseFirst() public {
        // proof type is enabled, withdrawals not paused — setVerifier should revert
        MockVerifier newVerifier = new MockVerifier(true);
        uint8 proofType = pool.PROOF_TYPE_TRANSFER(); // read before expectRevert
        vm.startPrank(admin);
        vm.expectRevert(PoolErrors.WithdrawalsNotPaused.selector);
        pool.setVerifier(proofType, address(newVerifier));
        vm.stopPrank();
    }

    function testSetProtocolEpochCanOnlyIncrease() public {
        vm.startPrank(admin);
        pool.pauseWithdrawals();
        pool.setProtocolEpoch(5);
        vm.expectRevert(PoolErrors.EpochCanOnlyIncrease.selector);
        pool.setProtocolEpoch(3);
        vm.stopPrank();
    }

    function testEmergencyDisableProofType() public {
        vm.startPrank(admin);
        pool.emergencyDisableProofType(pool.PROOF_TYPE_TRANSFER());
        vm.stopPrank();
        assertFalse(pool.proofTypeEnabled(pool.PROOF_TYPE_TRANSFER()));
    }

    function testConstructorRevertsOnZeroPoseidon() public {
        AccessManager am = new AccessManager(admin);
        vm.expectRevert(PoolErrors.InvalidPoseidon.selector);
        new MARKPool(address(am), address(mockOk), address(0));
    }

    function testConstructorRevertsOnEOAPoseidon() public {
        AccessManager am = new AccessManager(admin);
        vm.expectRevert(PoolErrors.PoseidonMustBeContract.selector);
        new MARKPool(address(am), address(mockOk), makeAddr("eoa"));
    }
}
