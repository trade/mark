// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Groth16SettlementVerifier} from "../../../src/settlement/verifier/Groth16SettlementVerifier.sol";
import {IGroth16Verifier} from "../../../src/settlement/interfaces/IGroth16Verifier.sol";

/// @dev Minimal mock that returns a configurable result for any proof.
contract MockGroth16Verifier is IGroth16Verifier {
    bool private _result;

    constructor(bool result) {
        _result = result;
    }

    function verifyProof(bytes calldata, bytes calldata) external view returns (bool) {
        return _result;
    }
}

contract Groth16SettlementVerifierTest is Test {
    Groth16SettlementVerifier internal verifier;
    MockGroth16Verifier internal mockVerifierOk;
    MockGroth16Verifier internal mockVerifierFail;

    address internal owner = makeAddr("owner");
    address internal module = makeAddr("module");
    address internal user = makeAddr("user");

    bytes32 internal constant INTENT = keccak256("intent-1");
    uint256 internal constant AMOUNT = 10 ether;

    function setUp() public {
        vm.prank(owner);
        verifier = new Groth16SettlementVerifier(owner);
        mockVerifierOk = new MockGroth16Verifier(true);
        mockVerifierFail = new MockGroth16Verifier(false);

        vm.prank(owner);
        verifier.setVerifierContract(address(mockVerifierOk));
    }

    function _buildProof(uint256 amount, bool isMint) internal pure returns (bytes memory) {
        // Groth16 proof component: 256 bytes (a, b, c — all zeroed for mock)
        bytes memory proof = new bytes(256);
        // Public signals: nullifierHash, commitmentHash, amount, isMint
        uint256[4] memory sigs;
        sigs[0] = uint256(keccak256("nullifier"));
        sigs[1] = uint256(keccak256("commitment"));
        sigs[2] = amount;
        sigs[3] = isMint ? 1 : 0;
        return abi.encodePacked(proof, abi.encode(sigs));
    }

    function testVerifySettlementReturnsTrueForValidProof() public view {
        bytes memory proof = _buildProof(AMOUNT, true);
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseWhenCircuitVerifierFails() public {
        vm.prank(owner);
        verifier.setVerifierContract(address(mockVerifierFail));
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseWhenNoVerifierSet() public {
        vm.prank(owner);
        Groth16SettlementVerifier fresh = new Groth16SettlementVerifier(owner);
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(fresh.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForAmountMismatch() public view {
        // proof commits to AMOUNT but call passes AMOUNT+1
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT + 1, true, proof));
    }

    function testVerifySettlementReturnsFalseForIsMintMismatch() public view {
        // proof commits to isMint=true but call passes false
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, false, proof));
    }

    function testVerifySettlementReturnsFalseForMalformedProof() public view {
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, hex"1234"));
    }

    function testVerifySettlementReturnsFalseForZeroIntentId() public view {
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(bytes32(0), module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroModule() public view {
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(INTENT, address(0), user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAccount() public view {
        bytes memory proof = _buildProof(AMOUNT, true);
        assertFalse(verifier.verifySettlement(INTENT, module, address(0), AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAmount() public view {
        bytes memory proof = _buildProof(0, true);
        assertFalse(verifier.verifySettlement(INTENT, module, user, 0, true, proof));
    }

    function testSetVerifierContractRevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        verifier.setVerifierContract(address(0));
    }

    function testSetVerifierContractRevertsForEOA() public {
        vm.prank(owner);
        vm.expectRevert();
        verifier.setVerifierContract(makeAddr("eoa"));
    }
}
