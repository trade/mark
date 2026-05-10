// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";

/// @notice Deterministic post-deploy configuration for existing MARK protocol contracts.
/// @dev Applies requested role/config updates and verifies resulting state in one broadcast.
contract PostDeployMARKSetup is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    error MissingTokenAdminForRequestedConfig();
    error MissingAdapterAdminForRequestedConfig();
    error MissingModuleAdminForRequestedConfig();
    error MissingVerifierAdminForRequestedConfig();
    error ModuleAddressRequiredForVerifierConfig();
    error ProductionModeRequiresProofValidation();
    error ProductionModeRequiresVerifier();

    struct Config {
        uint256 deployerKey;
        address deployer;
        address tokenAddress;
        address adapterAddress;
        address moduleAddress;
        address verifierAddress;
        address bridgeOperator;
        uint256 destinationChainId;
        address settlementOperator;
        address settlementAttester;
        bool proofEnabled;
        bool settlementProductionMode;
    }

    struct Contracts {
        RYLA token;
        MARKBridgeAdapter adapter;
        MARKSettlementModule module;
        AttestedSettlementVerifier verifier;
    }

    function run() external {
        Config memory cfg = _loadConfig();
        Contracts memory ctr = _bindContracts(cfg);

        _validateConfig(cfg, ctr);

        vm.startBroadcast(cfg.deployerKey);
        _applyConfig(cfg, ctr);
        vm.stopBroadcast();

        _assertConfig(cfg, ctr);
        _logSummary(cfg);
    }

    function validateWithConfig(Config memory cfg) external view {
        Contracts memory ctr = _bindContracts(cfg);
        _validateConfig(cfg, ctr);
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.deployer = vm.addr(cfg.deployerKey);

        cfg.tokenAddress = vm.envAddress("MARK_RYLA_TOKEN");

        cfg.adapterAddress = vm.envOr("MARK_BRIDGE_ADAPTER", address(0));
        if (cfg.adapterAddress == address(0)) {
            cfg.adapterAddress = vm.envOr("VERIFY_MARK_BRIDGE_ADAPTER", address(0));
        }

        cfg.moduleAddress = vm.envOr("MARK_SETTLEMENT_MODULE", address(0));
        if (cfg.moduleAddress == address(0)) {
            cfg.moduleAddress = vm.envOr("VERIFY_MARK_SETTLEMENT_MODULE", address(0));
        }

        cfg.verifierAddress = vm.envOr("MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.proofEnabled = vm.envOr("MARK_SETTLEMENT_PROOF_ENABLED", false);

        cfg.bridgeOperator = vm.envOr("MARK_BRIDGE_OPERATOR", address(0));
        cfg.destinationChainId = vm.envOr("MARK_BRIDGE_DESTINATION_CHAIN_ID", uint256(0));

        cfg.settlementOperator = vm.envOr("MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.settlementAttester = vm.envOr("MARK_SETTLEMENT_ATTESTER", address(0));
        cfg.settlementProductionMode = vm.envOr("MARK_SETTLEMENT_PRODUCTION_MODE", false);
    }

    function _bindContracts(Config memory cfg) internal pure returns (Contracts memory ctr) {
        ctr.token = RYLA(cfg.tokenAddress);
        if (cfg.adapterAddress != address(0)) {
            ctr.adapter = MARKBridgeAdapter(cfg.adapterAddress);
        }
        if (cfg.moduleAddress != address(0)) {
            ctr.module = MARKSettlementModule(cfg.moduleAddress);
        }
        if (cfg.verifierAddress != address(0)) {
            ctr.verifier = AttestedSettlementVerifier(cfg.verifierAddress);
        }
    }

    function _validateConfig(Config memory cfg, Contracts memory ctr) internal view {
        bool needsTokenConfig = cfg.moduleAddress != address(0);
        bool needsAdapterConfig =
            cfg.adapterAddress != address(0) && (cfg.bridgeOperator != address(0) || cfg.destinationChainId != 0);
        bool needsModuleConfig = cfg.moduleAddress != address(0)
            && (
                cfg.settlementOperator != address(0)
                    || cfg.verifierAddress != address(0)
                    || cfg.proofEnabled
                    || cfg.settlementProductionMode
            );
        bool needsVerifierConfig = cfg.verifierAddress != address(0) && cfg.settlementAttester != address(0);

        if (cfg.verifierAddress != address(0) && cfg.moduleAddress == address(0)) {
            revert ModuleAddressRequiredForVerifierConfig();
        }
        if (cfg.settlementProductionMode && !cfg.proofEnabled) {
            revert ProductionModeRequiresProofValidation();
        }
        if (cfg.settlementProductionMode && cfg.verifierAddress == address(0)) {
            revert ProductionModeRequiresVerifier();
        }

        if (needsTokenConfig && !ctr.token.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingTokenAdminForRequestedConfig();
        }
        if (needsAdapterConfig && !ctr.adapter.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingAdapterAdminForRequestedConfig();
        }
        if (needsModuleConfig && !ctr.module.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingModuleAdminForRequestedConfig();
        }
        if (needsVerifierConfig && !ctr.verifier.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) {
            revert MissingVerifierAdminForRequestedConfig();
        }
    }

    function _applyConfig(Config memory cfg, Contracts memory ctr) internal {
        if (cfg.adapterAddress != address(0)) {
            if (cfg.bridgeOperator != address(0)) {
                ctr.adapter.setOperator(cfg.bridgeOperator, true);
            }
            if (cfg.destinationChainId != 0) {
                ctr.adapter.setDestination(cfg.destinationChainId, true);
            }
        }

        if (cfg.moduleAddress != address(0)) {
            ctr.token.setMinter(cfg.moduleAddress, true);
            ctr.token.setBurner(cfg.moduleAddress, true);

            if (cfg.settlementOperator != address(0)) {
                ctr.module.setOperator(cfg.settlementOperator, true);
            }
            if (cfg.verifierAddress != address(0) || cfg.proofEnabled) {
                ctr.module.setVerifier(cfg.verifierAddress, cfg.proofEnabled);
            }
            if (cfg.settlementProductionMode) {
                ctr.module.activateProductionMode();
            }
        }

        if (cfg.verifierAddress != address(0) && cfg.settlementAttester != address(0)) {
            ctr.verifier.setAttester(cfg.settlementAttester, true);
        }
    }

    function _assertConfig(Config memory cfg, Contracts memory ctr) internal view {
        if (cfg.moduleAddress != address(0)) {
            _assertTrue(ctr.token.hasRole(ctr.token.MINTER_ROLE(), cfg.moduleAddress), "Token missing module minter role");
            _assertTrue(ctr.token.hasRole(ctr.token.BURNER_ROLE(), cfg.moduleAddress), "Token missing module burner role");
        }
        if (cfg.adapterAddress != address(0) && cfg.bridgeOperator != address(0)) {
            _assertTrue(ctr.adapter.hasRole(ctr.adapter.OPERATOR_ROLE(), cfg.bridgeOperator), "Adapter missing requested operator role");
        }
        if (cfg.adapterAddress != address(0) && cfg.destinationChainId != 0) {
            _assertTrue(ctr.adapter.destinationEnabled(cfg.destinationChainId), "Adapter destination not enabled");
        }
        if (cfg.moduleAddress != address(0) && cfg.settlementOperator != address(0)) {
            _assertTrue(ctr.module.hasRole(ctr.module.OPERATOR_ROLE(), cfg.settlementOperator), "Module missing requested operator role");
        }
        if (cfg.moduleAddress != address(0) && (cfg.verifierAddress != address(0) || cfg.proofEnabled)) {
            _assertEq(address(ctr.module.verifier()), cfg.verifierAddress, "Module verifier mismatch");
            _assertEq(ctr.module.proofValidationEnabled(), cfg.proofEnabled, "Module proof setting mismatch");
        }
        if (cfg.moduleAddress != address(0) && cfg.settlementProductionMode) {
            _assertTrue(ctr.module.productionMode(), "Module production mode not enabled");
        }
        if (cfg.verifierAddress != address(0) && cfg.settlementAttester != address(0)) {
            _assertTrue(ctr.verifier.hasRole(ctr.verifier.ATTESTER_ROLE(), cfg.settlementAttester), "Verifier missing requested attester role");
        }
    }

    function _logSummary(Config memory cfg) internal pure {
        console.log("PostDeployMARKSetup completed for token:", cfg.tokenAddress);
        if (cfg.adapterAddress != address(0)) console.log("Configured MARKBridgeAdapter:", cfg.adapterAddress);
        if (cfg.moduleAddress != address(0)) console.log("Configured MARKSettlementModule:", cfg.moduleAddress);
        if (cfg.verifierAddress != address(0)) console.log("Configured settlement verifier:", cfg.verifierAddress);
    }

    function _assertEq(address left, address right, string memory err) internal pure {
        if (left != right) revert(err);
    }

    function _assertEq(bool left, bool right, string memory err) internal pure {
        if (left != right) revert(err);
    }

    function _assertTrue(bool condition, string memory err) internal pure {
        if (!condition) revert(err);
    }
}
