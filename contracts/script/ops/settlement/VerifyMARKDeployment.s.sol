// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";

/// @notice Read-only deployment verification script for the MARK protocol stack (RYLA token + MARK modules).
/// @dev Run with `forge script ... --rpc-url <url>` after setting VERIFY_* env vars.
contract VerifyMARKDeployment is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    uint48 private constant EXPECTED_ADMIN_DELAY = 1 days;

    struct ExpectedConfig {
        address tokenAddress;
        address expectedOwner;
        address adapterAddress;
        address expectedBridgeOperator;
        uint256 expectedDestinationChain;
        uint256 expectedBridgeMaxPerTx;
        uint256 expectedBridgeDailyCap;
        address moduleAddress;
        address expectedSettlementOperator;
        bool expectedProofEnabled;
        bool expectedProductionMode;
        address expectedVerifier;
        address expectedAttester;
    }

    function run() external view {
        ExpectedConfig memory cfg = _loadConfig();
        _runWithConfig(cfg);
    }

    function runWithConfig(ExpectedConfig memory cfg) external view {
        _runWithConfig(cfg);
    }

    function _runWithConfig(ExpectedConfig memory cfg) internal view {
        RYLA token = RYLA(cfg.tokenAddress);

        _assertEq(token.name(), "RYLA Credits", "Token name mismatch");
        _assertEq(token.symbol(), "RYLA", "Token symbol mismatch");
        _assertEq(uint256(token.defaultAdminDelay()), uint256(EXPECTED_ADMIN_DELAY), "Token admin delay mismatch");

        if (cfg.expectedOwner != address(0)) {
            _assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, cfg.expectedOwner), "Token admin missing expected owner");
        }

        console.log("Verified token metadata and owner role:", cfg.tokenAddress);

        if (cfg.adapterAddress != address(0)) {
            MARKBridgeAdapter adapter = MARKBridgeAdapter(cfg.adapterAddress);
            _assertEq(address(adapter.TOKEN()), cfg.tokenAddress, "Bridge adapter token mismatch");
            _assertEq(
                address(adapter.SUPERCHAIN_TOKEN_BRIDGE()),
                PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE,
                "Bridge adapter predeploy mismatch"
            );

            if (cfg.expectedOwner != address(0)) {
                _assertTrue(adapter.hasRole(DEFAULT_ADMIN_ROLE, cfg.expectedOwner), "Adapter admin missing expected owner");
            }
            _assertEq(
                uint256(adapter.defaultAdminDelay()), uint256(EXPECTED_ADMIN_DELAY), "Adapter admin delay mismatch"
            );
            if (cfg.expectedBridgeOperator != address(0)) {
                _assertTrue(
                    adapter.hasRole(adapter.OPERATOR_ROLE(), cfg.expectedBridgeOperator), "Adapter missing expected operator"
                );
            }
            if (cfg.expectedDestinationChain != 0) {
                _assertTrue(
                    adapter.destinationEnabled(cfg.expectedDestinationChain), "Adapter destination chain not enabled"
                );
            }
            if (cfg.expectedBridgeMaxPerTx != 0) {
                _assertEq(adapter.maxPerTx(), cfg.expectedBridgeMaxPerTx, "Bridge adapter maxPerTx mismatch");
            }
            if (cfg.expectedBridgeDailyCap != 0) {
                _assertEq(adapter.dailyCap(), cfg.expectedBridgeDailyCap, "Bridge adapter dailyCap mismatch");
            }

            console.log("Verified bridge adapter wiring:", cfg.adapterAddress);
        }

        if (cfg.moduleAddress != address(0)) {
            MARKSettlementModule module = MARKSettlementModule(cfg.moduleAddress);
            _assertEq(address(module.TOKEN()), cfg.tokenAddress, "Settlement module token mismatch");
            _assertTrue(token.hasRole(token.MINTER_ROLE(), cfg.moduleAddress), "Token missing module minter role");
            _assertTrue(token.hasRole(token.BURNER_ROLE(), cfg.moduleAddress), "Token missing module burner role");

            if (cfg.expectedOwner != address(0)) {
                _assertTrue(module.hasRole(DEFAULT_ADMIN_ROLE, cfg.expectedOwner), "Module admin missing expected owner");
            }
            _assertEq(
                uint256(module.defaultAdminDelay()), uint256(EXPECTED_ADMIN_DELAY), "Module admin delay mismatch"
            );
            if (cfg.expectedSettlementOperator != address(0)) {
                _assertTrue(
                    module.hasRole(module.OPERATOR_ROLE(), cfg.expectedSettlementOperator),
                    "Module missing expected operator"
                );
            }

            _assertEq(module.proofValidationEnabled(), cfg.expectedProofEnabled, "Module proof toggle mismatch");
            _assertEq(module.productionMode(), cfg.expectedProductionMode, "Module production mode mismatch");
            if (module.proofValidationEnabled()) {
                _assertTrue(address(module.verifier()) != address(0), "Module proof enabled but verifier is zero");
            }

            if (cfg.expectedVerifier != address(0)) {
                _assertEq(address(module.verifier()), cfg.expectedVerifier, "Module verifier mismatch");
            }

            console.log("Verified settlement module wiring:", cfg.moduleAddress);
        }

        if (cfg.expectedVerifier != address(0) && cfg.expectedAttester != address(0)) {
            AttestedSettlementVerifier verifier = AttestedSettlementVerifier(cfg.expectedVerifier);
            _assertEq(
                uint256(verifier.defaultAdminDelay()), uint256(EXPECTED_ADMIN_DELAY), "Verifier admin delay mismatch"
            );
            if (cfg.expectedOwner != address(0)) {
                _assertTrue(verifier.hasRole(DEFAULT_ADMIN_ROLE, cfg.expectedOwner), "Verifier admin missing expected owner");
            }
            _assertTrue(
                verifier.hasRole(verifier.ATTESTER_ROLE(), cfg.expectedAttester), "Verifier missing expected attester role"
            );
            console.log("Verified verifier attester role:", cfg.expectedVerifier);
        }

        console.log("MARK protocol deployment verification complete");
    }

    function _loadConfig() internal view returns (ExpectedConfig memory cfg) {
        cfg.tokenAddress = vm.envAddress("VERIFY_MARK_RYLA_TOKEN");
        cfg.expectedOwner = vm.envOr("VERIFY_MARK_RYLA_OWNER", address(0));
        cfg.adapterAddress = vm.envOr("VERIFY_MARK_BRIDGE_ADAPTER", address(0));
        cfg.expectedBridgeOperator = vm.envOr("VERIFY_MARK_BRIDGE_OPERATOR", address(0));
        cfg.expectedDestinationChain = vm.envOr("VERIFY_MARK_BRIDGE_DEST_CHAIN", uint256(0));
        cfg.expectedBridgeMaxPerTx = vm.envOr("VERIFY_MARK_BRIDGE_MAX_PER_TX", uint256(0));
        cfg.expectedBridgeDailyCap = vm.envOr("VERIFY_MARK_BRIDGE_DAILY_CAP", uint256(0));
        cfg.moduleAddress = vm.envOr("VERIFY_MARK_SETTLEMENT_MODULE", address(0));
        cfg.expectedSettlementOperator = vm.envOr("VERIFY_MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.expectedProofEnabled = vm.envOr("VERIFY_MARK_SETTLEMENT_PROOF_ENABLED", false);
        cfg.expectedProductionMode = vm.envOr("VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE", false);
        cfg.expectedVerifier = vm.envOr("VERIFY_MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.expectedAttester = vm.envOr("VERIFY_MARK_SETTLEMENT_ATTESTER", address(0));
    }

    function _assertEq(string memory left, string memory right, string memory err) internal pure {
        if (keccak256(bytes(left)) != keccak256(bytes(right))) {
            revert(err);
        }
    }

    function _assertEq(address left, address right, string memory err) internal pure {
        if (left != right) {
            revert(err);
        }
    }

    function _assertEq(bool left, bool right, string memory err) internal pure {
        if (left != right) {
            revert(err);
        }
    }

    function _assertEq(uint256 left, uint256 right, string memory err) internal pure {
        if (left != right) {
            revert(err);
        }
    }


    function _assertTrue(bool condition, string memory err) internal pure {
        if (!condition) {
            revert(err);
        }
    }
}
