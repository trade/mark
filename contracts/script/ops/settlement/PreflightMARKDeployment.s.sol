// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";

/// @notice Read-only preflight checks for deploy/setup operations.
/// @dev Set MARK_PREFLIGHT_MODE to:
///      1 => DeployMARKStack
///      2 => DeployMARKSettlementModule
///      3 => PostDeployMARKSetup
contract PreflightMARKDeployment is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 internal constant MODE_STACK = 1;
    uint256 internal constant MODE_SETTLEMENT = 2;
    uint256 internal constant MODE_POSTDEPLOY = 3;

    error InvalidPreflightMode();
    error OwnerRequired();
    error TokenAddressRequired();
    error AdapterAddressRequired();
    error ModuleAddressRequired();
    error VerifierAddressRequired();
    error AddressMustBeContract();
    error MissingAdapterAdminForRequestedConfig();
    error MissingModuleAdminForRequestedConfig();
    error MissingVerifierAdminForRequestedAttester();
    error MissingTokenAdminForRoleGrants();
    error MissingTokenAdminForRequestedConfig();
    error MissingAdapterAdminForRequestedSetup();
    error MissingModuleAdminForRequestedSetup();
    error MissingVerifierAdminForRequestedSetup();
    error ModuleAddressRequiredForVerifierConfig();
    error VerifierRequiredWhenProofEnabled();
    error VerifierRequiredWhenProductionModeEnabled();
    error ProofValidationRequiredWhenProductionModeEnabled();
    error AmbiguousVerifierConfig();

    struct Config {
        uint256 mode;
        uint256 deployerKey;
        address deployer;
        address owner;
        address tokenAddress;
        address adapterAddress;
        address moduleAddress;
        address verifierAddress;
        address bridgeOperator;
        uint256 destinationChainId;
        address settlementOperator;
        address settlementAttester;
        bool proofEnabled;
        bool deployAttestedVerifier;
        bool settlementProductionMode;
    }

    function run() external view {
        Config memory cfg = _loadConfig();
        preflightWithConfig(cfg);
    }

    function preflightWithConfig(Config memory cfg) public view {
        if (cfg.mode == MODE_STACK) {
            _preflightStack(cfg);
        } else if (cfg.mode == MODE_SETTLEMENT) {
            _preflightSettlement(cfg);
        } else if (cfg.mode == MODE_POSTDEPLOY) {
            _preflightPostDeploy(cfg);
        } else {
            revert InvalidPreflightMode();
        }

        console.log("Preflight checks passed. Mode:", cfg.mode);
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.mode = vm.envOr("MARK_PREFLIGHT_MODE", uint256(0));
        cfg.deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.deployer = vm.addr(cfg.deployerKey);

        cfg.owner = vm.envOr("MARK_RYLA_OWNER", cfg.deployer);
        cfg.tokenAddress = vm.envOr("MARK_RYLA_TOKEN", address(0));
        cfg.adapterAddress = vm.envOr("MARK_BRIDGE_ADAPTER", vm.envOr("VERIFY_MARK_BRIDGE_ADAPTER", address(0)));
        cfg.moduleAddress = vm.envOr("MARK_SETTLEMENT_MODULE", vm.envOr("VERIFY_MARK_SETTLEMENT_MODULE", address(0)));
        cfg.verifierAddress = vm.envOr("MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.bridgeOperator = vm.envOr("MARK_BRIDGE_OPERATOR", address(0));
        cfg.destinationChainId = vm.envOr("MARK_BRIDGE_DESTINATION_CHAIN_ID", uint256(0));
        cfg.settlementOperator = vm.envOr("MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.settlementAttester = vm.envOr("MARK_SETTLEMENT_ATTESTER", address(0));
        cfg.proofEnabled = vm.envOr("MARK_SETTLEMENT_PROOF_ENABLED", false);
        cfg.deployAttestedVerifier = vm.envOr("MARK_DEPLOY_ATTESTED_VERIFIER", false);
        cfg.settlementProductionMode = vm.envOr("MARK_SETTLEMENT_PRODUCTION_MODE", false);
    }

    function _preflightStack(Config memory cfg) internal pure {
        if (cfg.owner == address(0)) revert OwnerRequired();

        bool requestedAdapterConfig = cfg.bridgeOperator != address(0) || cfg.destinationChainId != 0;
        if (requestedAdapterConfig && cfg.owner != cfg.deployer) {
            revert MissingAdapterAdminForRequestedConfig();
        }
    }

    function _preflightSettlement(Config memory cfg) internal view {
        if (cfg.owner == address(0)) revert OwnerRequired();
        if (cfg.tokenAddress == address(0)) revert TokenAddressRequired();
        _assertContract(cfg.tokenAddress);

        if (cfg.proofEnabled && cfg.verifierAddress == address(0) && !cfg.deployAttestedVerifier) {
            revert VerifierRequiredWhenProofEnabled();
        }
        if (cfg.settlementProductionMode && cfg.verifierAddress == address(0) && !cfg.deployAttestedVerifier) {
            revert VerifierRequiredWhenProductionModeEnabled();
        }
        if (cfg.settlementProductionMode && !cfg.proofEnabled) {
            revert ProofValidationRequiredWhenProductionModeEnabled();
        }
        if (cfg.deployAttestedVerifier && cfg.verifierAddress != address(0)) {
            revert AmbiguousVerifierConfig();
        }
        if (cfg.verifierAddress != address(0)) {
            _assertContract(cfg.verifierAddress);
        }

        bool requestedModuleConfig =
            cfg.settlementOperator != address(0) || cfg.verifierAddress != address(0) || cfg.proofEnabled;
        if (requestedModuleConfig && cfg.owner != cfg.deployer) {
            revert MissingModuleAdminForRequestedConfig();
        }
        if (cfg.deployAttestedVerifier && cfg.settlementAttester != address(0) && cfg.owner != cfg.deployer) {
            revert MissingVerifierAdminForRequestedAttester();
        }

        if (!RYLA(cfg.tokenAddress).hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingTokenAdminForRoleGrants();
        }
    }

    function _preflightPostDeploy(Config memory cfg) internal view {
        if (cfg.tokenAddress == address(0)) revert TokenAddressRequired();
        if (cfg.adapterAddress == address(0)) revert AdapterAddressRequired();
        if (cfg.moduleAddress == address(0)) revert ModuleAddressRequired();

        _assertContract(cfg.tokenAddress);
        _assertContract(cfg.adapterAddress);
        _assertContract(cfg.moduleAddress);

        RYLA token = RYLA(cfg.tokenAddress);
        MARKBridgeAdapter adapter = MARKBridgeAdapter(cfg.adapterAddress);
        MARKSettlementModule module = MARKSettlementModule(cfg.moduleAddress);

        if (cfg.verifierAddress != address(0)) {
            _assertContract(cfg.verifierAddress);
            if (cfg.moduleAddress == address(0)) revert ModuleAddressRequiredForVerifierConfig();
        }
        if (cfg.proofEnabled && cfg.verifierAddress == address(0)) {
            revert VerifierRequiredWhenProofEnabled();
        }
        if (cfg.settlementProductionMode && cfg.verifierAddress == address(0)) {
            revert VerifierRequiredWhenProductionModeEnabled();
        }
        if (cfg.settlementProductionMode && !cfg.proofEnabled) {
            revert ProofValidationRequiredWhenProductionModeEnabled();
        }

        bool needsTokenSetup = true; // setup always grants module mint/burn roles
        bool needsAdapterSetup = cfg.bridgeOperator != address(0) || cfg.destinationChainId != 0;
        bool needsModuleSetup = cfg.settlementOperator != address(0) || cfg.verifierAddress != address(0)
            || cfg.proofEnabled || cfg.settlementProductionMode;
        bool needsVerifierSetup = cfg.verifierAddress != address(0) && cfg.settlementAttester != address(0);

        if (needsTokenSetup && !token.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingTokenAdminForRequestedConfig();
        }
        if (needsAdapterSetup && !adapter.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingAdapterAdminForRequestedSetup();
        }
        if (needsModuleSetup && !module.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingModuleAdminForRequestedSetup();
        }
        if (needsVerifierSetup) {
            if (cfg.verifierAddress == address(0)) revert VerifierAddressRequired();
            if (!AttestedSettlementVerifier(cfg.verifierAddress).hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
                revert MissingVerifierAdminForRequestedSetup();
            }
        }
    }

    function _assertContract(address target) internal view {
        if (target.code.length == 0) revert AddressMustBeContract();
    }
}
