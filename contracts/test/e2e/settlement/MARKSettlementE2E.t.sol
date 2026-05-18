// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {SettlementErrors} from "../../../src/errors/SettlementErrors.sol";

contract MARKSettlementE2ETest is Test {
    RYLA internal token;
    MARKSettlementModule internal module;
    MARKSettlementModule internal moduleB;
    AttestedSettlementVerifier internal verifier;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal user = makeAddr("user");
    uint256 internal attesterPk = 0xC0FFEE;
    address internal attester;

    bytes32 internal constant INTENT_MINT = keccak256("e2e-mint-1");
    bytes32 internal constant INTENT_BURN = keccak256("e2e-burn-1");
    bytes32 internal constant CONTEXT_MINT = keccak256("e2e-mint-context");
    bytes32 internal constant CONTEXT_BURN = keccak256("e2e-burn-context");

    function setUp() public {
        attester = vm.addr(attesterPk);

        vm.prank(owner);
        token = new RYLA(owner);

        vm.prank(owner);
        verifier = new AttestedSettlementVerifier(owner);

        vm.prank(owner);
        module = new MARKSettlementModule(owner, address(token));
        vm.prank(owner);
        moduleB = new MARKSettlementModule(owner, address(token));

        vm.startPrank(owner);
        verifier.setAttester(attester, true);
        module.setOperator(operator, true);
        moduleB.setOperator(operator, true);
        module.setVerifier(address(verifier), true);
        moduleB.setVerifier(address(verifier), true);
        token.setMinter(address(module), true);
        token.setBurner(address(module), true);
        token.setMinter(address(moduleB), true);
        token.setBurner(address(moduleB), true);
        vm.stopPrank();
    }

    function testMintThenBurnLifecycleWithValidationEnabled() public {
        uint256 mintAmount = 100 ether;
        uint256 mintDeadline = block.timestamp + 1 hours;
        bytes memory mintProof =
            _buildProof(INTENT_MINT, address(module), user, mintAmount, true, CONTEXT_MINT, mintDeadline);

        vm.prank(operator);
        module.settleMint(user, mintAmount, INTENT_MINT, mintProof);
        assertEq(token.balanceOf(user), mintAmount);

        uint256 burnAmount = 40 ether;
        vm.prank(user);
        bool ok = token.approve(address(module), burnAmount);
        assertTrue(ok);

        uint256 burnDeadline = block.timestamp + 1 hours;
        bytes memory burnProof =
            _buildProof(INTENT_BURN, address(module), user, burnAmount, false, CONTEXT_BURN, burnDeadline);

        vm.prank(operator);
        module.settleBurn(user, burnAmount, INTENT_BURN, burnProof);

        assertEq(token.balanceOf(user), 60 ether);
        assertEq(token.totalSupply(), 60 ether);
    }

    function testReplayIntentReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory mintProof = _buildProof(INTENT_MINT, address(module), user, 1 ether, true, CONTEXT_MINT, deadline);

        vm.prank(operator);
        module.settleMint(user, 1 ether, INTENT_MINT, mintProof);

        vm.prank(operator);
        vm.expectRevert(SettlementErrors.IntentAlreadyConsumed.selector);
        module.settleMint(user, 1 ether, INTENT_MINT, mintProof);
    }

    function testInvalidAttestationReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest =
            verifier.settlementDigest(INTENT_MINT, address(module), user, 1 ether, true, CONTEXT_MINT, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, digest);
        bytes memory wrongProof = abi.encode(deadline, CONTEXT_MINT, v, r, s);

        vm.prank(operator);
        vm.expectRevert(SettlementErrors.VerificationFailed.selector);
        module.settleMint(user, 1 ether, INTENT_MINT, wrongProof);
    }

    function testProofBoundToModuleAddressRevertsOnDifferentModule() public {
        uint256 amount = 3 ether;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory proofForModuleA =
            _buildProof(INTENT_MINT, address(module), user, amount, true, CONTEXT_MINT, deadline);

        vm.prank(operator);
        vm.expectRevert(SettlementErrors.VerificationFailed.selector);
        moduleB.settleMint(user, amount, INTENT_MINT, proofForModuleA);
    }

    function _buildProof(
        bytes32 intentId,
        address moduleAddress,
        address account,
        uint256 amount,
        bool isMint,
        bytes32 contextHash,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = verifier.settlementDigest(
            intentId, moduleAddress, account, amount, isMint, contextHash, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterPk, digest);
        return abi.encode(deadline, contextHash, v, r, s);
    }
}
