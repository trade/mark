// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {PreflightMARKDeployment} from "../../script/ops/settlement/PreflightMARKDeployment.s.sol";

contract PreflightMARKDeploymentTest is Test {
    uint256 internal constant MODE_STACK = 1;
    uint256 internal constant MODE_SETTLEMENT = 2;
    uint256 internal constant MODE_POSTDEPLOY = 3;

    address internal deployer = makeAddr("deployer");
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal attester = makeAddr("attester");

    PreflightMARKDeployment internal preflight;
    RYLA internal token;
    MARKBridgeAdapter internal adapter;
    MARKSettlementModule internal module;
    AttestedSettlementVerifier internal verifier;

    function setUp() public {
        preflight = new PreflightMARKDeployment();

        vm.prank(deployer);
        token = new RYLA(deployer);
        vm.prank(deployer);
        adapter = new MARKBridgeAdapter(deployer, address(token));
        vm.prank(deployer);
        module = new MARKSettlementModule(deployer, address(token));
        vm.prank(deployer);
        verifier = new AttestedSettlementVerifier(deployer);
    }

    function testStackPreflightPassesForOwnerDeployer() public view {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_STACK;
        cfg.deployer = deployer;
        cfg.owner = deployer;
        cfg.bridgeOperator = operator;
        cfg.destinationChainId = 10;

        preflight.preflightWithConfig(cfg);
    }

    function testStackPreflightRevertsWhenConfigNeedsAdminButOwnerDiffers() public {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_STACK;
        cfg.deployer = deployer;
        cfg.owner = owner;
        cfg.bridgeOperator = operator;

        vm.expectRevert(PreflightMARKDeployment.MissingAdapterAdminForRequestedConfig.selector);
        preflight.preflightWithConfig(cfg);
    }

    function testSettlementPreflightPassesWithValidConfig() public view {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_SETTLEMENT;
        cfg.deployer = deployer;
        cfg.owner = deployer;
        cfg.tokenAddress = address(token);
        cfg.settlementOperator = operator;
        cfg.verifierAddress = address(verifier);
        cfg.proofEnabled = true;

        preflight.preflightWithConfig(cfg);
    }

    function testSettlementPreflightRevertsWhenProofEnabledWithoutVerifier() public {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_SETTLEMENT;
        cfg.deployer = deployer;
        cfg.owner = deployer;
        cfg.tokenAddress = address(token);
        cfg.proofEnabled = true;

        vm.expectRevert(PreflightMARKDeployment.VerifierRequiredWhenProofEnabled.selector);
        preflight.preflightWithConfig(cfg);
    }

    function testSettlementPreflightRevertsWhenProductionModeWithoutProof() public {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_SETTLEMENT;
        cfg.deployer = deployer;
        cfg.owner = deployer;
        cfg.tokenAddress = address(token);
        cfg.verifierAddress = address(verifier);
        cfg.settlementProductionMode = true;
        cfg.proofEnabled = false;

        vm.expectRevert(PreflightMARKDeployment.ProofValidationRequiredWhenProductionModeEnabled.selector);
        preflight.preflightWithConfig(cfg);
    }

    function testSettlementPreflightRevertsWhenProductionModeWithoutVerifier() public {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_SETTLEMENT;
        cfg.deployer = deployer;
        cfg.owner = deployer;
        cfg.tokenAddress = address(token);
        cfg.settlementProductionMode = true;
        cfg.proofEnabled = true;

        vm.expectRevert(PreflightMARKDeployment.VerifierRequiredWhenProofEnabled.selector);
        preflight.preflightWithConfig(cfg);
    }

    function testPostDeployPreflightPassesWithConfiguredContracts() public view {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_POSTDEPLOY;
        cfg.deployer = deployer;
        cfg.tokenAddress = address(token);
        cfg.adapterAddress = address(adapter);
        cfg.moduleAddress = address(module);
        cfg.bridgeOperator = operator;
        cfg.destinationChainId = 10;
        cfg.settlementOperator = operator;
        cfg.verifierAddress = address(verifier);
        cfg.settlementAttester = attester;
        cfg.proofEnabled = true;

        preflight.preflightWithConfig(cfg);
    }

    function testPostDeployPreflightRevertsWhenVerifierAdminMissing() public {
        vm.prank(deployer);
        AttestedSettlementVerifier externalVerifier = new AttestedSettlementVerifier(owner);

        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_POSTDEPLOY;
        cfg.deployer = deployer;
        cfg.tokenAddress = address(token);
        cfg.adapterAddress = address(adapter);
        cfg.moduleAddress = address(module);
        cfg.verifierAddress = address(externalVerifier);
        cfg.settlementAttester = attester;
        cfg.proofEnabled = true;

        vm.expectRevert(PreflightMARKDeployment.MissingVerifierAdminForRequestedSetup.selector);
        preflight.preflightWithConfig(cfg);
    }

    function testPostDeployPreflightRevertsWhenProductionModeWithoutVerifier() public {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_POSTDEPLOY;
        cfg.deployer = deployer;
        cfg.tokenAddress = address(token);
        cfg.adapterAddress = address(adapter);
        cfg.moduleAddress = address(module);
        cfg.settlementProductionMode = true;
        cfg.proofEnabled = true;

        vm.expectRevert(PreflightMARKDeployment.VerifierRequiredWhenProofEnabled.selector);
        preflight.preflightWithConfig(cfg);
    }
}
