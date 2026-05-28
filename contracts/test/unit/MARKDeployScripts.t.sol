// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../src/settlement/MARKSettlementModule.sol";
import {Groth16SettlementVerifier} from "../../src/settlement/verifier/Groth16SettlementVerifier.sol";
import {IGroth16Verifier} from "../../src/settlement/interfaces/IGroth16Verifier.sol";
import {DeployMARKStack} from "../../script/deploy/bridge/DeployMARKStack.s.sol";
import {DeployMARKSettlementModule} from "../../script/deploy/settlement/DeployMARKSettlementModule.s.sol";

contract MockScriptGroth16Verifier is IGroth16Verifier {
    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[13] calldata)
        external
        pure
        returns (bool)
    {
        return true;
    }
}

contract MARKDeployScriptsTest is Test {
    uint256 internal constant DEPLOYER_PK = 0xA11CE;

    DeployMARKStack internal deployStack;
    DeployMARKSettlementModule internal deploySettlement;

    address internal deployer;
    address internal owner;
    address internal operator;
    address internal outsider;

    function setUp() public {
        deployStack = new DeployMARKStack();
        deploySettlement = new DeployMARKSettlementModule();

        deployer = vm.addr(DEPLOYER_PK);
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        outsider = makeAddr("outsider");

        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));

        // Ensure test isolation for script env-driven behavior.
        vm.setEnv("MARK_RYLA_OWNER", vm.toString(address(0)));
        vm.setEnv("MARK_BRIDGE_OPERATOR", vm.toString(address(0)));
        vm.setEnv("MARK_BRIDGE_DESTINATION_CHAIN_ID", "0");

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(0)));
        vm.setEnv("MARK_MODULE_OWNER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_OPERATOR", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_VERIFIER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_PROOF_ENABLED", "false");
        vm.setEnv("MARK_DEPLOY_ATTESTED_VERIFIER", "false");
        vm.setEnv("MARK_SETTLEMENT_ATTESTER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT", "false");
    }

    function testDeployMARKStackRevertsWhenConfigRequestedWithoutAdapterAdmin() public {
        vm.setEnv("MARK_RYLA_OWNER", vm.toString(owner));
        vm.setEnv("MARK_BRIDGE_OPERATOR", vm.toString(operator));
        vm.setEnv("MARK_BRIDGE_DESTINATION_CHAIN_ID", "902");

        vm.expectRevert(DeployMARKStack.MissingAdapterAdminForRequestedConfig.selector);
        deployStack.run();
    }

    function testDeployMARKStackConfiguresWhenDeployerIsAdmin() public {
        vm.setEnv("MARK_RYLA_OWNER", vm.toString(deployer));
        vm.setEnv("MARK_BRIDGE_OPERATOR", vm.toString(operator));
        vm.setEnv("MARK_BRIDGE_DESTINATION_CHAIN_ID", "902");

        (RYLA token, MARKBridgeAdapter adapter) = deployStack.run();

        assertTrue(token.hasRole(0x00, deployer));
        assertTrue(adapter.hasRole(adapter.OPERATOR_ROLE(), operator));
        assertTrue(adapter.destinationEnabled(902));
    }

    function testDeployMARKSettlementRevertsWhenConfigRequestedWithoutModuleAdmin() public {
        vm.prank(deployer);
        RYLA token = new RYLA(deployer);

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        vm.setEnv("MARK_MODULE_OWNER", vm.toString(owner));
        vm.setEnv("MARK_SETTLEMENT_OPERATOR", vm.toString(operator));
        vm.setEnv("MARK_SETTLEMENT_VERIFIER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_PROOF_ENABLED", "false");
        vm.setEnv("MARK_DEPLOY_ATTESTED_VERIFIER", "false");
        vm.setEnv("MARK_SETTLEMENT_ATTESTER", vm.toString(address(0)));

        vm.expectRevert(DeployMARKSettlementModule.MissingModuleAdminForRequestedConfig.selector);
        deploySettlement.run();
    }

    function testDeployMARKSettlementRevertsWhenMissingTokenAdmin() public {
        vm.prank(outsider);
        RYLA token = new RYLA(outsider);

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        vm.setEnv("MARK_MODULE_OWNER", vm.toString(deployer));
        vm.setEnv("MARK_SETTLEMENT_OPERATOR", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_VERIFIER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_PROOF_ENABLED", "false");
        vm.setEnv("MARK_DEPLOY_ATTESTED_VERIFIER", "false");
        vm.setEnv("MARK_SETTLEMENT_ATTESTER", vm.toString(address(0)));

        vm.expectRevert();
        deploySettlement.run();
    }

    function testDeployMARKSettlementConfiguresAndGrantsRoles() public {
        vm.prank(deployer);
        RYLA token = new RYLA(deployer);

        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));
        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        vm.setEnv("MARK_MODULE_OWNER", vm.toString(deployer));
        vm.setEnv("MARK_SETTLEMENT_OPERATOR", vm.toString(operator));
        vm.setEnv("MARK_SETTLEMENT_VERIFIER", vm.toString(address(0)));
        vm.setEnv("MARK_SETTLEMENT_PROOF_ENABLED", "false");
        vm.setEnv("MARK_DEPLOY_ATTESTED_VERIFIER", "false");
        vm.setEnv("MARK_SETTLEMENT_ATTESTER", vm.toString(address(0)));

        MARKSettlementModule module = deploySettlement.run();

        assertTrue(module.hasRole(module.OPERATOR_ROLE(), operator));
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(module)));
        assertTrue(token.hasRole(token.BURNER_ROLE(), address(module)));
    }

    function testDeployMARKSettlementBindsGroth16VerifierModule() public {
        vm.prank(deployer);
        RYLA token = new RYLA(deployer);

        vm.startPrank(deployer);
        Groth16SettlementVerifier groth = new Groth16SettlementVerifier(deployer);
        MockScriptGroth16Verifier inner = new MockScriptGroth16Verifier();
        groth.setVerifierContract(address(inner));
        vm.stopPrank();

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        vm.setEnv("MARK_MODULE_OWNER", vm.toString(deployer));
        vm.setEnv("MARK_SETTLEMENT_OPERATOR", vm.toString(operator));
        vm.setEnv("MARK_SETTLEMENT_VERIFIER", vm.toString(address(groth)));
        vm.setEnv("MARK_SETTLEMENT_PROOF_ENABLED", "true");
        vm.setEnv("MARK_DEPLOY_ATTESTED_VERIFIER", "false");
        vm.setEnv("MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT", "true");
        assertEq(vm.envAddress("MARK_SETTLEMENT_VERIFIER"), address(groth));

        MARKSettlementModule module = deploySettlement.run();

        assertEq(groth.settlementModule(), address(module));
        assertTrue(groth.directionEnforcementEnabled());
    }
}
