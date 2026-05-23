// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {IVerifier} from "../../../src/interfaces/IVerifier.sol";

contract MockVerifier is IVerifier {
    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[13] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract MARKPoolIntegrationTest is Test {
    MARKPool internal pool;
    RYLACreditLedger internal ledger;
    RYLA internal token;
    MockVerifier internal verifier;
    AccessManager internal accessManager;

    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");

    bytes32 internal constant C0 = bytes32(uint256(1));
    bytes32 internal constant C1 = bytes32(uint256(2));
    bytes32 internal constant N0 = bytes32(uint256(3));
    bytes32 internal constant N1 = bytes32(uint256(4));

    uint256[2] internal A;
    uint256[2][2] internal B;
    uint256[2] internal C;

    function setUp() public {
        verifier = new MockVerifier();

        vm.startPrank(admin);
        token = new RYLA(admin);
        accessManager = new AccessManager(admin);
        address poseidon = deployCode("PoseidonT3.sol:PoseidonT3");
        pool = new MARKPool(address(accessManager), address(verifier), poseidon);
        ledger = new RYLACreditLedger(address(token), address(pool));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = pool.setAssetLedger.selector;
        accessManager.setTargetFunctionRole(address(pool), selectors, 1);
        accessManager.grantRole(1, admin, 0);
        vm.warp(block.timestamp + 1);

        pool.setAssetLedger(address(ledger));
        token.setMinter(address(ledger), true);
        vm.stopPrank();
    }

    function testIntegrationTransactWithRelayerFee() public {
        bytes32 root = pool.getMerkleRoot();
        bytes32[2] memory nullifiers = [N0, N1];
        bytes32[2] memory commitments = [C0, C1];
        uint256 fee = 100;

        pool.transact(root, nullifiers, commitments, fee, relayer, A, B, C);

        assertEq(ledger.creditBalanceOf(relayer), fee);
        assertTrue(pool.isNullifierUsedGlobal(N0));
        assertTrue(pool.isNullifierUsedGlobal(N1));
    }

    function testIntegrationMultipleTransactions() public {
        bytes32 root = pool.getMerkleRoot();

        bytes32[2] memory nullifiers1 = [bytes32(uint256(10)), bytes32(uint256(11))];
        bytes32[2] memory commitments1 = [bytes32(uint256(20)), bytes32(uint256(21))];
        pool.transact(root, nullifiers1, commitments1, 0, address(0), A, B, C);

        bytes32 newRoot = pool.getMerkleRoot();
        assertTrue(newRoot != root);

        bytes32[2] memory nullifiers2 = [bytes32(uint256(12)), bytes32(uint256(13))];
        bytes32[2] memory commitments2 = [bytes32(uint256(22)), bytes32(uint256(23))];
        pool.transact(newRoot, nullifiers2, commitments2, 0, address(0), A, B, C);

        assertTrue(pool.isNullifierUsedGlobal(nullifiers1[0]));
        assertTrue(pool.isNullifierUsedGlobal(nullifiers2[0]));
    }
}
