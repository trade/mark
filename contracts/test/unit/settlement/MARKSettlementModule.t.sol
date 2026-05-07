// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {IUTXOSettlementVerifier} from "../../../src/settlement/interfaces/IUTXOSettlementVerifier.sol";
import {SettlementErrors} from "../../../src/errors/SettlementErrors.sol";

contract MockUTXOSettlementVerifier is IUTXOSettlementVerifier {
    bool public shouldVerify = true;

    function setShouldVerify(bool value) external {
        shouldVerify = value;
    }

    function verifySettlement(bytes32, address, address, uint256, bool, bytes calldata) external view returns (bool) {
        return shouldVerify;
    }
}

contract MARKSettlementModuleTest is Test {
    RYLA internal token;
    MARKSettlementModule internal module;
    MockUTXOSettlementVerifier internal verifier;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal user = makeAddr("user");
    bytes32 internal constant INTENT_M1 = keccak256("m-1");
    bytes32 internal constant INTENT_M2 = keccak256("m-2");
    bytes32 internal constant INTENT_M3 = keccak256("m-3");
    bytes32 internal constant INTENT_M4 = keccak256("m-4");
    bytes32 internal constant INTENT_M5 = keccak256("m-5");
    bytes32 internal constant INTENT_B1 = keccak256("b-1");
    bytes32 internal constant INTENT_B2 = keccak256("b-2");

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);

        vm.prank(owner);
        module = new MARKSettlementModule(owner, address(token));

        vm.startPrank(owner);
        token.setMinter(address(module), true);
        token.setBurner(address(module), true);
        module.setOperator(operator, true);
        vm.stopPrank();

        verifier = new MockUTXOSettlementVerifier();
    }

    function testSettleMintRevertsWhenCallerNotOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), module.OPERATOR_ROLE()
            )
        );
        module.settleMint(user, 1 ether, INTENT_M1, bytes(""));
    }

    function testSettleMintConsumesIntentAndMints() public {
        vm.prank(operator);
        module.settleMint(user, 5 ether, INTENT_M1, bytes(""));
        assertEq(token.balanceOf(user), 5 ether);
        assertEq(module.totalSettledMint(), 5 ether);
        assertTrue(module.consumedIntents(INTENT_M1));

        vm.prank(operator);
        vm.expectRevert(SettlementErrors.IntentAlreadyConsumed.selector);
        module.settleMint(user, 1 ether, INTENT_M1, bytes(""));
    }

    function testSettleBurnConsumesIntentAndBurns() public {
        vm.prank(operator);
        module.settleMint(user, 9 ether, INTENT_M2, bytes(""));
        assertEq(token.balanceOf(user), 9 ether);

        vm.prank(user);
        bool ok = token.approve(address(module), 4 ether);
        assertTrue(ok);

        vm.prank(operator);
        module.settleBurn(user, 4 ether, INTENT_B1, bytes(""));
        assertEq(token.balanceOf(user), 5 ether);
        assertEq(token.totalSupply(), 5 ether);
        assertEq(token.balanceOf(address(module)), 0);
        assertEq(module.totalSettledBurn(), 4 ether);
        assertTrue(module.consumedIntents(INTENT_B1));
    }

    function testSetVerifierAndEnforceValidation() public {
        vm.prank(owner);
        module.setVerifier(address(verifier), true);

        verifier.setShouldVerify(false);
        vm.prank(operator);
        vm.expectRevert(SettlementErrors.VerificationFailed.selector);
        module.settleMint(user, 1 ether, INTENT_M3, hex"1234");

        verifier.setShouldVerify(true);
        vm.prank(operator);
        module.settleMint(user, 1 ether, INTENT_M4, hex"1234");
        assertEq(token.balanceOf(user), 1 ether);
    }

    function testSetVerifierRejectsValidationWithoutVerifier() public {
        vm.prank(owner);
        vm.expectRevert(SettlementErrors.VerifierRequired.selector);
        module.setVerifier(address(0), true);
    }

    function testActivateProductionModeRequiresEnabledVerifier() public {
        vm.prank(owner);
        vm.expectRevert(SettlementErrors.ProductionModeRequiresProofValidation.selector);
        module.activateProductionMode();

        vm.prank(owner);
        module.setVerifier(address(verifier), true);
        vm.prank(owner);
        module.activateProductionMode();
        assertTrue(module.productionMode());

        vm.prank(owner);
        vm.expectRevert(SettlementErrors.ProductionModeAlreadyEnabled.selector);
        module.activateProductionMode();
    }

    function testProductionModePreventsDisablingProofValidation() public {
        vm.prank(owner);
        module.setVerifier(address(verifier), true);
        vm.prank(owner);
        module.activateProductionMode();

        vm.prank(owner);
        vm.expectRevert(SettlementErrors.ProductionModeRequiresProofValidation.selector);
        module.setVerifier(address(0), false);
    }

    function testProductionModePreventsVerifierSwapWithProofDisabled() public {
        vm.prank(owner);
        module.setVerifier(address(verifier), true);
        vm.prank(owner);
        module.activateProductionMode();

        vm.prank(owner);
        vm.expectRevert(SettlementErrors.ProductionModeRequiresProofValidation.selector);
        module.setVerifier(address(verifier), false);
    }

    function testTotalSettledAccumulatesAcrossMultipleIntents() public {
        vm.startPrank(operator);
        module.settleMint(user, 3 ether, keccak256("acc-m1"), bytes(""));
        module.settleMint(user, 7 ether, keccak256("acc-m2"), bytes(""));
        vm.stopPrank();
        assertEq(module.totalSettledMint(), 10 ether);

        vm.prank(user);
        token.approve(address(module), 10 ether);

        vm.startPrank(operator);
        module.settleBurn(user, 4 ether, keccak256("acc-b1"), bytes(""));
        module.settleBurn(user, 2 ether, keccak256("acc-b2"), bytes(""));
        vm.stopPrank();
        assertEq(module.totalSettledBurn(), 6 ether);
        assertEq(token.balanceOf(user), 4 ether);
    }

    function testSetVerifierRejectsEOAAddress() public {
        address eoa = makeAddr("eoa");
        vm.prank(owner);
        vm.expectRevert(SettlementErrors.VerifierRequired.selector);
        module.setVerifier(eoa, true);
    }

    function testProductionModeStillEnforcesBurnProofValidation() public {
        vm.startPrank(owner);
        module.setVerifier(address(verifier), true);
        module.activateProductionMode();
        vm.stopPrank();

        vm.prank(operator);
        module.settleMint(user, 3 ether, INTENT_M5, hex"1234");

        vm.prank(user);
        assertTrue(token.approve(address(module), 3 ether));

        verifier.setShouldVerify(false);
        vm.prank(operator);
        vm.expectRevert(SettlementErrors.VerificationFailed.selector);
        module.settleBurn(user, 1 ether, INTENT_B2, hex"1234");
    }
}
