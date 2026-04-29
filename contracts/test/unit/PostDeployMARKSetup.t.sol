// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {PostDeployMARKSetup} from "../../script/ops/settlement/PostDeployMARKSetup.s.sol";

contract PostDeployMARKSetupTest is Test {
    PostDeployMARKSetup internal setupScript;
    RYLA internal token;
    MARKBridgeAdapter internal adapter;
    MARKSettlementModule internal module;
    AttestedSettlementVerifier internal verifier;

    address internal deployer = makeAddr("deployer");

    function setUp() public {
        setupScript = new PostDeployMARKSetup();

        vm.prank(deployer);
        token = new RYLA(deployer);
        vm.prank(deployer);
        adapter = new MARKBridgeAdapter(deployer, address(token));
        vm.prank(deployer);
        module = new MARKSettlementModule(deployer, address(token));
        vm.prank(deployer);
        verifier = new AttestedSettlementVerifier(deployer);
    }

    function testPostDeploySetupRevertsWhenProductionModeWithoutProof() public {
        PostDeployMARKSetup.Config memory cfg = _baseConfig();
        cfg.settlementProductionMode = true;
        cfg.proofEnabled = false;
        cfg.verifierAddress = address(verifier);

        vm.expectRevert(PostDeployMARKSetup.ProductionModeRequiresProofValidation.selector);
        setupScript.validateWithConfig(cfg);
    }

    function testPostDeploySetupRevertsWhenProductionModeWithoutVerifier() public {
        PostDeployMARKSetup.Config memory cfg = _baseConfig();
        cfg.settlementProductionMode = true;
        cfg.proofEnabled = true;
        cfg.verifierAddress = address(0);

        vm.expectRevert(PostDeployMARKSetup.ProductionModeRequiresVerifier.selector);
        setupScript.validateWithConfig(cfg);
    }

    function _baseConfig() internal view returns (PostDeployMARKSetup.Config memory cfg) {
        cfg.deployer = deployer;
        cfg.tokenAddress = address(token);
        cfg.adapterAddress = address(adapter);
        cfg.moduleAddress = address(module);
    }
}
