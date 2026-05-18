// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Groth16SettlementVerifier} from "../../../src/settlement/verifier/Groth16SettlementVerifier.sol";
import {IGroth16Verifier} from "../../../src/settlement/interfaces/IGroth16Verifier.sol";

contract MockGroth16Verifier is IGroth16Verifier {
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

contract MockSettlementModule {}

contract Groth16SettlementVerifierTest is Test {
    Groth16SettlementVerifier internal verifier;
    MockGroth16Verifier internal mockOk;
    MockGroth16Verifier internal mockFail;
    MockSettlementModule internal mockModule;

    address internal owner = makeAddr("owner");
    address internal module = makeAddr("module");
    address internal user = makeAddr("user");

    bytes32 internal constant INTENT = keccak256("intent-1");
    uint256 internal constant AMOUNT = 10 ether;

    function setUp() public {
        vm.prank(owner);
        verifier = new Groth16SettlementVerifier(owner);
        mockOk = new MockGroth16Verifier(true);
        mockFail = new MockGroth16Verifier(false);
        mockModule = new MockSettlementModule();
        vm.prank(owner);
        verifier.setVerifierContract(address(mockOk));
        vm.prank(owner);
        verifier.setSettlementModule(address(mockModule));
        module = address(mockModule);
    }

    function _buildProof(bytes32 intentId, address account, uint256 amount) internal view returns (bytes memory) {
        return _buildProofWithDirection(intentId, account, amount, 0);
    }

    function _buildProofWithDirection(bytes32 intentId, address account, uint256 amount, uint256 direction)
        internal
        view
        returns (bytes memory)
    {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[13] memory signals;
        signals[0] = uint256(intentId);
        signals[1] = block.chainid;
        signals[2] = block.chainid;
        signals[6] = uint256(intentId);
        signals[7] = direction;
        signals[10] = uint256(uint160(account));
        signals[11] = uint256(uint160(account));
        signals[12] = amount;
        return abi.encode(a, b, c, signals);
    }

    function testVerifySettlementReturnsTrueForValidProof() public view {
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseWhenCircuitVerifierFails() public {
        vm.prank(owner);
        verifier.setVerifierContract(address(mockFail));
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseWhenNoVerifierSet() public {
        vm.prank(owner);
        Groth16SettlementVerifier fresh = new Groth16SettlementVerifier(owner);
        vm.prank(owner);
        fresh.setSettlementModule(address(mockModule));
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(fresh.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseWhenSettlementModuleNotConfigured() public {
        vm.prank(owner);
        Groth16SettlementVerifier fresh = new Groth16SettlementVerifier(owner);
        vm.prank(owner);
        fresh.setVerifierContract(address(mockOk));
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(fresh.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForAmountMismatch() public view {
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT + 1, true, proof));
    }

    function testVerifySettlementReturnsFalseForIntentMismatch() public view {
        bytes memory proof = _buildProof(keccak256("other"), user, AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForAccountMismatch() public view {
        bytes memory proof = _buildProof(INTENT, address(0xdead), AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroIntentId() public view {
        bytes memory proof = _buildProof(bytes32(0), user, AMOUNT);
        assertFalse(verifier.verifySettlement(bytes32(0), module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroModule() public view {
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, address(0), user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForModuleMismatch() public {
        bytes memory proof = _buildProof(INTENT, user, AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, makeAddr("other-module"), user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAccount() public view {
        bytes memory proof = _buildProof(INTENT, address(0), AMOUNT);
        assertFalse(verifier.verifySettlement(INTENT, module, address(0), AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForZeroAmount() public view {
        bytes memory proof = _buildProof(INTENT, user, 0);
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

    function testSetSettlementModuleRevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        verifier.setSettlementModule(address(0));
    }

    function testSetSettlementModuleRevertsForEOA() public {
        vm.prank(owner);
        vm.expectRevert();
        verifier.setSettlementModule(makeAddr("eoa"));
    }

    function testVerifySettlementReturnsFalseForChainIdMismatch() public view {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[13] memory signals;
        signals[0] = uint256(INTENT);
        signals[1] = block.chainid + 1;
        signals[2] = block.chainid;
        signals[6] = uint256(INTENT);
        signals[10] = uint256(uint160(user));
        signals[11] = uint256(uint160(user));
        signals[12] = AMOUNT;
        bytes memory proof = abi.encode(a, b, c, signals);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementReturnsFalseForContextSignalMismatch() public view {
        uint256[2] memory a;
        uint256[2][2] memory b;
        uint256[2] memory c;
        uint256[13] memory signals;
        signals[0] = uint256(INTENT);
        signals[1] = block.chainid;
        signals[2] = block.chainid;
        signals[4] = 1; // fee must be zero for settlement mapping
        signals[6] = uint256(INTENT);
        signals[10] = uint256(uint160(user));
        signals[11] = uint256(uint160(user));
        signals[12] = AMOUNT;
        bytes memory proof = abi.encode(a, b, c, signals);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
    }

    function testVerifySettlementDirectionEnforcementDisabledAcceptsLegacyZeroDirection() public view {
        bytes memory proof = _buildProofWithDirection(INTENT, user, AMOUNT, 0);
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, proof));
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, false, proof));
    }

    function testVerifySettlementDirectionEnforcementEnabledAcceptsMatchingDirection() public {
        vm.prank(owner);
        verifier.setDirectionEnforcementEnabled(true);

        bytes memory mintProof = _buildProofWithDirection(INTENT, user, AMOUNT, 1);
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, mintProof));

        bytes memory burnProof = _buildProofWithDirection(INTENT, user, AMOUNT, 0);
        assertTrue(verifier.verifySettlement(INTENT, module, user, AMOUNT, false, burnProof));
    }

    function testVerifySettlementDirectionEnforcementEnabledRejectsMismatchedDirection() public {
        vm.prank(owner);
        verifier.setDirectionEnforcementEnabled(true);

        bytes memory mintProofWithZero = _buildProofWithDirection(INTENT, user, AMOUNT, 0);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, true, mintProofWithZero));

        bytes memory burnProofWithOne = _buildProofWithDirection(INTENT, user, AMOUNT, 1);
        assertFalse(verifier.verifySettlement(INTENT, module, user, AMOUNT, false, burnProofWithOne));
    }

    function testVerifySettlementReturnsFalseForMalformedProof() public view {
        // Malformed proof (wrong length) must return false, not revert.
        bool result = verifier.verifySettlement(INTENT, address(module), user, AMOUNT, true, bytes("malformed"));
        assertFalse(result);
    }

    function testVerifySettlementReturnsFalseForEmptyProof() public view {
        bool result = verifier.verifySettlement(INTENT, address(module), user, AMOUNT, true, bytes(""));
        assertFalse(result);
    }
}
