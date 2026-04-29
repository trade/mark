// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {DeployMARKStack} from "../../deploy/bridge/DeployMARKStack.s.sol";
import {DeployMARKSettlementModule} from "../../deploy/settlement/DeployMARKSettlementModule.s.sol";
import {PostDeployMARKSetup} from "./PostDeployMARKSetup.s.sol";
import {PreflightMARKDeployment} from "./PreflightMARKDeployment.s.sol";
import {VerifyMARKDeployment} from "./VerifyMARKDeployment.s.sol";

/// @notice Release orchestrator for MARK deployments.
/// @dev Sequence: preflight -> deploy -> optional postdeploy setup -> verify -> artifact.
contract ReleaseMARK is Script {
    uint256 internal constant MODE_STACK = 1;
    uint256 internal constant MODE_SETTLEMENT = 2;
    uint256 internal constant MODE_POSTDEPLOY = 3;

    struct ReleaseResult {
        bool execute;
        bool runPostDeploy;
        address deployer;
        address token;
        address adapter;
        address module;
        address verifier;
    }

    function dryRunWithConfig(
        address deployer,
        address owner,
        address bridgeOperator,
        uint256 destinationChainId,
        bool runPostDeploy
    )
        external
        returns (ReleaseResult memory result)
    {
        PreflightMARKDeployment preflight = new PreflightMARKDeployment();
        _runStackPreflightFromValues(preflight, 0, deployer, owner, bridgeOperator, destinationChainId);

        result = ReleaseResult({
            execute: false,
            runPostDeploy: runPostDeploy,
            deployer: deployer,
            token: address(0),
            adapter: address(0),
            module: address(0),
            verifier: address(0)
        });
    }

    function run() external {
        bool execute = vm.envOr("MARK_RELEASE_EXECUTE", false);
        bool runPostDeploy = vm.envOr("MARK_RELEASE_RUN_POSTDEPLOY", false);
        bool writeArtifact = vm.envOr("MARK_RELEASE_WRITE_ARTIFACT", false);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        PreflightMARKDeployment preflight = new PreflightMARKDeployment();
        VerifyMARKDeployment verifyScript = new VerifyMARKDeployment();

        _runStackPreflight(preflight, deployerKey, deployer);

        if (!execute) {
            console.log("MARK_RELEASE_EXECUTE=false. Dry-run complete (no transactions broadcast).");
            if (writeArtifact) {
                _writeArtifact(
                    ReleaseResult({
                        execute: false,
                        runPostDeploy: runPostDeploy,
                        deployer: deployer,
                        token: address(0),
                        adapter: address(0),
                        module: address(0),
                        verifier: address(0)
                    })
                );
            } else {
                console.log("Artifact write disabled (MARK_RELEASE_WRITE_ARTIFACT=false).");
            }
            return;
        }

        DeployMARKStack deployStack = new DeployMARKStack();
        (RYLA token, MARKBridgeAdapter adapter) = deployStack.run();

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));

        _runSettlementPreflight(preflight, deployerKey, deployer, address(token));

        DeployMARKSettlementModule deploySettlement = new DeployMARKSettlementModule();
        MARKSettlementModule module = deploySettlement.run();

        if (runPostDeploy) {
            vm.setEnv("MARK_BRIDGE_ADAPTER", vm.toString(address(adapter)));
            vm.setEnv("MARK_SETTLEMENT_MODULE", vm.toString(address(module)));

            _runPostDeployPreflight(preflight, deployerKey, deployer, address(token), address(adapter), address(module));

            PostDeployMARKSetup setup = new PostDeployMARKSetup();
            setup.run();
        }

        _runVerify(verifyScript, address(token), address(adapter), address(module));

        ReleaseResult memory result = ReleaseResult({
            execute: true,
            runPostDeploy: runPostDeploy,
            deployer: deployer,
            token: address(token),
            adapter: address(adapter),
            module: address(module),
            verifier: address(module.verifier())
        });
        if (writeArtifact) {
            _writeArtifact(result);
        } else {
            console.log("Artifact write disabled (MARK_RELEASE_WRITE_ARTIFACT=false).");
        }
    }

    function _runStackPreflight(PreflightMARKDeployment preflight, uint256 deployerKey, address deployer) internal view {
        address owner = vm.envOr("MARK_RYLA_OWNER", deployer);
        address bridgeOperator = vm.envOr("MARK_BRIDGE_OPERATOR", address(0));
        uint256 destinationChainId = vm.envOr("MARK_BRIDGE_DESTINATION_CHAIN_ID", uint256(0));
        _runStackPreflightFromValues(preflight, deployerKey, deployer, owner, bridgeOperator, destinationChainId);
    }

    function _runStackPreflightFromValues(
        PreflightMARKDeployment preflight,
        uint256 deployerKey,
        address deployer,
        address owner,
        address bridgeOperator,
        uint256 destinationChainId
    )
        internal
        view
    {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_STACK;
        cfg.deployerKey = deployerKey;
        cfg.deployer = deployer;
        cfg.owner = owner;
        cfg.bridgeOperator = bridgeOperator;
        cfg.destinationChainId = destinationChainId;
        preflight.preflightWithConfig(cfg);
    }

    function _runSettlementPreflight(
        PreflightMARKDeployment preflight,
        uint256 deployerKey,
        address deployer,
        address tokenAddress
    )
        internal
        view
    {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_SETTLEMENT;
        cfg.deployerKey = deployerKey;
        cfg.deployer = deployer;
        cfg.owner = vm.envOr("MARK_MODULE_OWNER", deployer);
        cfg.tokenAddress = tokenAddress;
        cfg.settlementOperator = vm.envOr("MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.verifierAddress = vm.envOr("MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.settlementAttester = vm.envOr("MARK_SETTLEMENT_ATTESTER", address(0));
        cfg.proofEnabled = vm.envOr("MARK_SETTLEMENT_PROOF_ENABLED", false);
        cfg.deployAttestedVerifier = vm.envOr("MARK_DEPLOY_ATTESTED_VERIFIER", false);
        cfg.settlementProductionMode = vm.envOr("MARK_SETTLEMENT_PRODUCTION_MODE", false);
        preflight.preflightWithConfig(cfg);
    }

    function _runPostDeployPreflight(
        PreflightMARKDeployment preflight,
        uint256 deployerKey,
        address deployer,
        address tokenAddress,
        address adapterAddress,
        address moduleAddress
    )
        internal
        view
    {
        PreflightMARKDeployment.Config memory cfg;
        cfg.mode = MODE_POSTDEPLOY;
        cfg.deployerKey = deployerKey;
        cfg.deployer = deployer;
        cfg.tokenAddress = tokenAddress;
        cfg.adapterAddress = adapterAddress;
        cfg.moduleAddress = moduleAddress;
        cfg.bridgeOperator = vm.envOr("MARK_BRIDGE_OPERATOR", address(0));
        cfg.destinationChainId = vm.envOr("MARK_BRIDGE_DESTINATION_CHAIN_ID", uint256(0));
        cfg.settlementOperator = vm.envOr("MARK_SETTLEMENT_OPERATOR", address(0));
        cfg.verifierAddress = vm.envOr("MARK_SETTLEMENT_VERIFIER", address(0));
        cfg.settlementAttester = vm.envOr("MARK_SETTLEMENT_ATTESTER", address(0));
        cfg.proofEnabled = vm.envOr("MARK_SETTLEMENT_PROOF_ENABLED", false);
        cfg.settlementProductionMode = vm.envOr("MARK_SETTLEMENT_PRODUCTION_MODE", false);
        preflight.preflightWithConfig(cfg);
    }

    function _runVerify(
        VerifyMARKDeployment verifyScript,
        address tokenAddress,
        address adapterAddress,
        address moduleAddress
    )
        internal
        view
    {
        bool strictVerify = vm.envOr("MARK_RELEASE_STRICT_VERIFY", true);
        VerifyMARKDeployment.ExpectedConfig memory cfg;
        cfg.tokenAddress = tokenAddress;
        cfg.expectedOwner = vm.envOr("VERIFY_MARK_RYLA_OWNER", vm.envOr("MARK_RYLA_OWNER", address(0)));
        cfg.adapterAddress = adapterAddress;
        cfg.expectedBridgeOperator = vm.envOr("VERIFY_MARK_BRIDGE_OPERATOR", address(0));
        cfg.expectedDestinationChain = vm.envOr("VERIFY_MARK_BRIDGE_DEST_CHAIN", uint256(0));
        cfg.expectedBridgeMaxPerTx = vm.envOr("VERIFY_MARK_BRIDGE_MAX_PER_TX", uint256(0));
        cfg.expectedBridgeDailyCap = vm.envOr("VERIFY_MARK_BRIDGE_DAILY_CAP", uint256(0));
        cfg.moduleAddress = moduleAddress;
        cfg.expectedSettlementOperator = vm.envOr("VERIFY_MARK_SETTLEMENT_OPERATOR", address(0));

        MARKSettlementModule module = MARKSettlementModule(moduleAddress);
        if (strictVerify) {
            cfg.expectedProofEnabled = vm.envBool("VERIFY_MARK_SETTLEMENT_PROOF_ENABLED");
            cfg.expectedProductionMode = vm.envBool("VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE");
            cfg.expectedVerifier = vm.envAddress("VERIFY_MARK_SETTLEMENT_VERIFIER");
        } else {
            cfg.expectedProofEnabled = module.proofValidationEnabled();
            cfg.expectedProductionMode = module.productionMode();
            cfg.expectedVerifier = address(module.verifier());
        }
        cfg.expectedAttester = vm.envOr("VERIFY_MARK_SETTLEMENT_ATTESTER", address(0));

        verifyScript.runWithConfig(cfg);
    }

    function _writeArtifact(ReleaseResult memory result) internal {
        string memory path = vm.envOr("MARK_RELEASE_ARTIFACT_PATH", string("broadcast/mark-release-latest.json"));
        string memory root = "release";
        _ensureParentDir(path);

        vm.serializeString(root, "protocol", "MARK");
        vm.serializeString(root, "tokenSymbol", "RYLA");
        vm.serializeBool(root, "execute", result.execute);
        vm.serializeBool(root, "runPostDeploy", result.runPostDeploy);
        vm.serializeAddress(root, "deployer", result.deployer);
        vm.serializeAddress(root, "token", result.token);
        vm.serializeAddress(root, "adapter", result.adapter);
        vm.serializeAddress(root, "module", result.module);
        vm.serializeAddress(root, "verifier", result.verifier);
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "timestamp", block.timestamp);
        string memory json = vm.serializeString(root, "gitCommit", vm.envOr("MARK_GIT_COMMIT", string("unknown")));
        vm.writeJson(json, path);

        console.log("Release artifact written:", path);
    }

    function _ensureParentDir(string memory path) internal {
        bytes memory raw = bytes(path);
        uint256 split = type(uint256).max;
        for (uint256 i = raw.length; i > 0; i--) {
            if (raw[i - 1] == "/") {
                split = i - 1;
                break;
            }
        }
        if (split == type(uint256).max || split == 0) return;

        bytes memory parent = new bytes(split);
        for (uint256 j = 0; j < split; j++) {
            parent[j] = raw[j];
        }
        vm.createDir(string(parent), true);
    }
}
