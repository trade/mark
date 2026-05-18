// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";

/// @notice Deploys MARKSettlementModule and optionally wires operator/verifier and token roles.
contract DeployMARKSettlementModule is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    error MissingVerifierAdminForRequestedAttester();
    error MissingModuleAdminForRequestedConfig();
    error MissingTokenAdminForRoleGrants();

    struct Config {
        uint256 deployerKey;
        address deployer;
        address tokenAddress;
        address owner;
        address operator;
        address verifierAddress;
        bool deployAttestedVerifier;
        address verifierAttester;
        bool proofEnabled;
        bool groth16DirectionEnforcement;
    }

    function run() external returns (MARKSettlementModule module) {
        Config memory cfg = _loadConfig();
        RYLA token = RYLA(cfg.tokenAddress);

        vm.startBroadcast(cfg.deployerKey);
        module = new MARKSettlementModule(cfg.owner, cfg.tokenAddress);

        if (cfg.deployAttestedVerifier) {
            AttestedSettlementVerifier deployedVerifier = new AttestedSettlementVerifier(cfg.owner);
            cfg.verifierAddress = address(deployedVerifier);
            bool deployerIsVerifierAdmin = deployedVerifier.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer);
            if (cfg.verifierAttester != address(0) && !deployerIsVerifierAdmin) {
                revert MissingVerifierAdminForRequestedAttester();
            }
            if (deployerIsVerifierAdmin && cfg.verifierAttester != address(0)) {
                deployedVerifier.setAttester(cfg.verifierAttester, true);
            }
        }

        bool deployerIsModuleAdmin = module.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer);
        bool moduleNeedsConfig = cfg.operator != address(0) || cfg.verifierAddress != address(0) || cfg.proofEnabled;
        if (moduleNeedsConfig && !deployerIsModuleAdmin) {
            revert MissingModuleAdminForRequestedConfig();
        }

        if (deployerIsModuleAdmin) {
            if (cfg.operator != address(0)) {
                module.setOperator(cfg.operator, true);
            }
            module.setVerifier(cfg.verifierAddress, cfg.proofEnabled);
            if (cfg.verifierAddress != address(0)) {
                _tryConfigureGroth16Verifier(cfg.verifierAddress, address(module), cfg.groth16DirectionEnforcement);
            }
        }

        bool deployerIsTokenAdmin = token.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer);
        if (!deployerIsTokenAdmin) {
            revert MissingTokenAdminForRoleGrants();
        }

        if (deployerIsTokenAdmin) {
            token.setMinter(address(module), true);
            token.setBurner(address(module), true);
        }

        vm.stopBroadcast();

        console.log("MARKSettlementModule:", address(module));
        console.log("SettlementVerifier:", cfg.verifierAddress);
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.deployer = vm.addr(cfg.deployerKey);

        cfg.tokenAddress = vm.envAddress("MARK_RYLA_TOKEN");
        cfg.owner = vm.envOr("MARK_MODULE_OWNER", cfg.deployer);
        cfg.operator = vm.envOr("MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.verifierAddress = vm.envOr("MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.deployAttestedVerifier = vm.envOr("MARK_DEPLOY_ATTESTED_VERIFIER", false);
        cfg.verifierAttester = vm.envOr("MARK_SETTLEMENT_ATTESTER", address(0));
        cfg.proofEnabled = vm.envOr("MARK_SETTLEMENT_PROOF_ENABLED", false);
        cfg.groth16DirectionEnforcement = vm.envOr("MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT", false);
    }

    function _tryConfigureGroth16Verifier(address verifierAddress, address moduleAddress, bool directionEnforcement)
        internal
    {
        (bool hasSetModule,) =
            verifierAddress.staticcall(abi.encodeWithSelector(bytes4(keccak256("settlementModule()"))));
        if (!hasSetModule) return;

        // Must succeed for Groth16 verifier contracts during controlled deployment.
        (bool okSetModule,) = verifierAddress.call(
            abi.encodeWithSelector(bytes4(keccak256("setSettlementModule(address)")), moduleAddress)
        );
        require(okSetModule, "Groth16 setSettlementModule failed");

        (bool okSetDirection,) = verifierAddress.call(
            abi.encodeWithSelector(bytes4(keccak256("setDirectionEnforcementEnabled(bool)")), directionEnforcement)
        );
        require(okSetDirection, "Groth16 setDirectionEnforcementEnabled failed");
    }
}
