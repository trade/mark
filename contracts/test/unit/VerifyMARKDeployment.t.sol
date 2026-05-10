// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {VerifyMARKDeployment} from "../../script/ops/settlement/VerifyMARKDeployment.s.sol";

contract VerifyMARKDeploymentTest is Test {
    VerifyMARKDeployment internal verifyScript;
    VerifyMARKDeployment.ExpectedConfig internal cfg;

    address internal owner = makeAddr("owner");
    address internal bridgeOperator = makeAddr("bridgeOperator");
    address internal settlementOperator = makeAddr("settlementOperator");
    address internal attester = makeAddr("attester");

    RYLA internal token;
    MARKBridgeAdapter internal adapter;
    MARKSettlementModule internal module;
    AttestedSettlementVerifier internal verifier;

    function setUp() public {
        verifyScript = new VerifyMARKDeployment();

        vm.prank(owner);
        token = new RYLA(owner);
        vm.prank(owner);
        adapter = new MARKBridgeAdapter(owner, address(token));
        vm.prank(owner);
        module = new MARKSettlementModule(owner, address(token));
        vm.prank(owner);
        verifier = new AttestedSettlementVerifier(owner);

        vm.startPrank(owner);
        token.setMinter(address(module), true);
        token.setBurner(address(module), true);
        adapter.setOperator(bridgeOperator, true);
        adapter.setDestination(902, true);
        adapter.setBridgeLimits(100 ether, 1_000 ether);
        module.setOperator(settlementOperator, true);
        module.setVerifier(address(verifier), true);
        verifier.setAttester(attester, true);
        vm.stopPrank();

        cfg.tokenAddress = address(token);
        cfg.expectedOwner = owner;
        cfg.adapterAddress = address(adapter);
        cfg.expectedBridgeOperator = bridgeOperator;
        cfg.expectedDestinationChain = 902;
        cfg.expectedBridgeMaxPerTx = 100 ether;
        cfg.expectedBridgeDailyCap = 1_000 ether;
        cfg.moduleAddress = address(module);
        cfg.expectedSettlementOperator = settlementOperator;
        cfg.expectedProofEnabled = true;
        cfg.expectedProductionMode = false;
        cfg.expectedVerifier = address(verifier);
        cfg.expectedAttester = attester;
    }

    function testVerifyDeploymentPassesWhenWiringMatches() public view {
        verifyScript.runWithConfig(cfg);
    }

    function testVerifyDeploymentRevertsOnBridgeLimitMismatch() public {
        cfg.expectedBridgeMaxPerTx = 99 ether;

        vm.expectRevert(bytes("Bridge adapter maxPerTx mismatch"));
        verifyScript.runWithConfig(cfg);
    }

    function testVerifyDeploymentPassesWithProductionModeEnabled() public {
        vm.prank(owner);
        module.activateProductionMode();

        cfg.expectedProductionMode = true;
        verifyScript.runWithConfig(cfg);
    }

    function testVerifyDeploymentRevertsOnProductionModeMismatch() public {
        vm.prank(owner);
        module.activateProductionMode();

        vm.expectRevert(bytes("Module production mode mismatch"));
        verifyScript.runWithConfig(cfg);
    }
}
