// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";

contract AttestedSettlementVerifierTest is Test {
    AttestedSettlementVerifier internal verifier;

    address internal owner = makeAddr("owner");
    address internal settlementModule = makeAddr("settlementModule");
    address internal user = makeAddr("user");
    uint256 internal attesterPk = 0xA11CE;
    address internal attester;

    bytes32 internal constant INTENT = keccak256("intent-1");
    bytes32 internal constant CONTEXT = keccak256("ctx-1");

    function setUp() public {
        attester = vm.addr(attesterPk);
        vm.prank(owner);
        verifier = new AttestedSettlementVerifier(owner);
        vm.prank(owner);
        verifier.setAttester(attester, true);
    }

    function testVerifySettlementReturnsTrueForValidAttestation() public view {
        uint256 amount = 25 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _buildProof(INTENT, settlementModule, user, amount, true, CONTEXT, deadline, attesterPk);
        bool ok = verifier.verifySettlement(INTENT, settlementModule, user, amount, true, proof);
        assertTrue(ok);
    }

    function testVerifySettlementReturnsFalseForExpiredAttestation() public view {
        uint256 amount = 25 ether;
        uint256 deadline = block.timestamp - 1;
        bytes memory proof = _buildProof(INTENT, settlementModule, user, amount, true, CONTEXT, deadline, attesterPk);
        bool ok = verifier.verifySettlement(INTENT, settlementModule, user, amount, true, proof);
        assertFalse(ok);
    }

    function testVerifySettlementReturnsFalseForUnauthorizedSigner() public view {
        uint256 amount = 25 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _buildProof(INTENT, settlementModule, user, amount, true, CONTEXT, deadline, 0xB0B);
        bool ok = verifier.verifySettlement(INTENT, settlementModule, user, amount, true, proof);
        assertFalse(ok);
    }

    function testVerifySettlementReturnsFalseForWrongAmount() public view {
        uint256 amount = 25 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _buildProof(INTENT, settlementModule, user, amount, true, CONTEXT, deadline, attesterPk);
        bool ok = verifier.verifySettlement(INTENT, settlementModule, user, amount + 1, true, proof);
        assertFalse(ok);
    }

    function testVerifySettlementReturnsFalseForMalformedProof() public view {
        bool ok = verifier.verifySettlement(INTENT, settlementModule, user, 1 ether, true, hex"1234");
        assertFalse(ok);
    }

    function testVerifySettlementReturnsFalseForZeroIntentId() public view {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof =
            _buildProof(bytes32(0), settlementModule, user, 1 ether, true, CONTEXT, deadline, attesterPk);
        assertFalse(verifier.verifySettlement(bytes32(0), settlementModule, user, 1 ether, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroSettlementModule() public view {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _buildProof(INTENT, address(0), user, 1 ether, true, CONTEXT, deadline, attesterPk);
        assertFalse(verifier.verifySettlement(INTENT, address(0), user, 1 ether, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAccount() public view {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof =
            _buildProof(INTENT, settlementModule, address(0), 1 ether, true, CONTEXT, deadline, attesterPk);
        assertFalse(verifier.verifySettlement(INTENT, settlementModule, address(0), 1 ether, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAmount() public view {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proof = _buildProof(INTENT, settlementModule, user, 0, true, CONTEXT, deadline, attesterPk);
        assertFalse(verifier.verifySettlement(INTENT, settlementModule, user, 0, true, proof));
    }

    function testVerifySettlementReturnsFalseForWrongIsMintFlag() public view {
        uint256 deadline = block.timestamp + 1 hours;
        // proof signed for isMint=true, but called with isMint=false
        bytes memory proof = _buildProof(INTENT, settlementModule, user, 1 ether, true, CONTEXT, deadline, attesterPk);
        assertFalse(verifier.verifySettlement(INTENT, settlementModule, user, 1 ether, false, proof));
    }

    function _buildProof(
        bytes32 intentId,
        address moduleAddress,
        address account,
        uint256 amount,
        bool isMint,
        bytes32 contextHash,
        uint256 deadline,
        uint256 signerPk
    ) internal view returns (bytes memory proof) {
        bytes32 digest = verifier.settlementDigest(
            intentId, moduleAddress, account, amount, isMint, contextHash, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        proof = abi.encode(deadline, contextHash, v, r, s);
    }
}
