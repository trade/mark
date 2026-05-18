// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {IVerifier} from "../../../src/interfaces/IVerifier.sol";
import {ICreditLedger} from "../../../src/interfaces/ICreditLedger.sol";
import {PoolErrors} from "../../../src/pool/errors/PoolErrors.sol";

contract AlwaysValidVerifier is IVerifier {
    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[13] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract NoOpLedger is ICreditLedger {
    function credit(address, uint256) external {}
    function debit(address, uint256) external {}

    function creditBalanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function totalCreditsMinted() external pure returns (uint256) {
        return 0;
    }

    function totalCreditsBurned() external pure returns (uint256) {
        return 0;
    }

    function totalCreditsOutstanding() external pure returns (uint256) {
        return 0;
    }

    function maxCredits() external pure returns (uint256) {
        return type(uint256).max;
    }
}

contract MARKPoolHandler is Test {
    MARKPool public immutable POOL;

    // Tracks nullifiers spent during this run
    bytes32[] internal _spentNullifiers;
    // Tracks withdraw bindings recorded: nullifier => binding hash
    mapping(bytes32 => bytes32) internal _recordedBindings;

    uint256 internal _nonce;

    constructor(MARKPool pool) {
        POOL = pool;
    }

    /// @dev Calls transact with unique nullifiers and commitments each time.
    function transact(uint8 seed) external {
        bytes32 root = POOL.getMerkleRoot();
        bytes32 n0 = keccak256(abi.encodePacked("n0", _nonce));
        bytes32 n1 = keccak256(abi.encodePacked("n1", _nonce));
        bytes32 c0 = keccak256(abi.encodePacked("c0", _nonce));
        bytes32 c1 = keccak256(abi.encodePacked("c1", _nonce));
        _nonce++;

        // Skip if nullifiers already used (shouldn't happen with unique nonce)
        if (POOL.isNullifierUsedGlobal(n0) || POOL.isNullifierUsedGlobal(n1)) return;

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;

        bytes32[2] memory nullifiers = [n0, n1];
        bytes32[2] memory commitments = [c0, c1];

        try POOL.transact(root, nullifiers, commitments, 0, address(0), a, b, c) {
            _spentNullifiers.push(n0);
            _spentNullifiers.push(n1);
        } catch {}

        seed; // suppress unused warning
    }

    /// @dev Calls transactWithWithdrawBinding with unique nullifiers.
    function transactWithBinding(uint8 seed, uint64 amount) external {
        if (amount == 0) return;
        bytes32 root = POOL.getMerkleRoot();
        bytes32 n0 = keccak256(abi.encodePacked("bn0", _nonce));
        bytes32 n1 = keccak256(abi.encodePacked("bn1", _nonce));
        bytes32 c0 = keccak256(abi.encodePacked("bc0", _nonce));
        bytes32 c1 = keccak256(abi.encodePacked("bc1", _nonce));
        _nonce++;

        if (POOL.isNullifierUsedGlobal(n0) || POOL.isNullifierUsedGlobal(n1)) return;

        address owner = address(uint160(uint256(keccak256(abi.encodePacked("owner", seed)))));
        address recipient = address(uint160(uint256(keccak256(abi.encodePacked("recipient", seed)))));

        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;

        bytes32[2] memory nullifiers = [n0, n1];
        bytes32[2] memory commitments = [c0, c1];

        bytes32 expectedBinding = POOL.computeWithdrawBindingHash(owner, recipient, amount);

        try POOL.transactWithWithdrawBinding(
            root, nullifiers, commitments, 0, address(0), owner, recipient, amount, a, b, c
        ) {
            _spentNullifiers.push(n0);
            _spentNullifiers.push(n1);
            _recordedBindings[n0] = expectedBinding;
            _recordedBindings[n1] = expectedBinding;
        } catch {}
    }

    function spentNullifiers() external view returns (bytes32[] memory) {
        return _spentNullifiers;
    }

    function recordedBinding(bytes32 nullifier) external view returns (bytes32) {
        return _recordedBindings[nullifier];
    }
}

contract MARKPoolInvariants is StdInvariant, Test {
    MARKPool internal pool;
    MARKPoolHandler internal handler;
    AccessManager internal accessManager;

    address internal admin = makeAddr("admin");

    function setUp() public {
        AlwaysValidVerifier verifier = new AlwaysValidVerifier();
        NoOpLedger ledger = new NoOpLedger();

        vm.startPrank(admin);
        accessManager = new AccessManager(admin);
        address poseidon = deployCode("PoseidonT3.sol:PoseidonT3");
        pool = new MARKPool(address(accessManager), address(verifier), poseidon);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = pool.setAssetLedger.selector;
        selectors[1] = pool.setProofTypeEnabled.selector;
        accessManager.setTargetFunctionRole(address(pool), selectors, 1);
        accessManager.grantRole(1, admin, 0);
        vm.warp(block.timestamp + 1);

        pool.setAssetLedger(address(ledger));
        vm.stopPrank();

        handler = new MARKPoolHandler(pool);
        targetContract(address(handler));
    }

    /// @dev Once a nullifier is spent, it stays spent.
    function invariant_nullifiersAreNeverUnspent() public view {
        bytes32[] memory spent = handler.spentNullifiers();
        for (uint256 i = 0; i < spent.length; i++) {
            assertTrue(pool.isNullifierUsedGlobal(spent[i]), "nullifier was unspent");
        }
    }

    /// @dev Withdraw bindings are immutable once recorded.
    function invariant_withdrawBindingsAreImmutable() public view {
        bytes32[] memory spent = handler.spentNullifiers();
        for (uint256 i = 0; i < spent.length; i++) {
            bytes32 recorded = handler.recordedBinding(spent[i]);
            if (recorded == bytes32(0)) continue;
            assertEq(pool.nullifierWithdrawBinding(spent[i]), recorded, "withdraw binding changed");
        }
    }

    /// @dev Root queue tail only grows — roots are never removed from the queue.
    function invariant_rootQueueOnlyGrows() public view {
        assertGe(pool.rootQueueTail(), pool.rootQueueHead(), "root queue tail behind head");
    }
}
