// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {MARKWithdrawAdapter} from "../../../src/withdraw/MARKWithdrawAdapter.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {DeployMARKPool} from "../../deploy/pool/DeployMARKPool.s.sol";

/// @notice Release orchestrator for the MARKPool stack.
/// @dev Sequence: preflight checks -> deploy -> verify -> artifact.
///
///      Required env vars:
///        PRIVATE_KEY           — deployer private key
///        MARK_RYLA_TOKEN       — deployed RYLA address
///        MARK_POOL_VERIFIER    — deployed MARKPoolVerifier address
///
///      Optional env vars:
///        MARK_POOL_OWNER           — AccessManager admin (defaults to deployer)
///        MARK_POOL_INTENT_SIGNER   — initial intent signer for MARKWithdrawAdapter
///        MARK_POOL_RELEASE_EXECUTE — set true to broadcast (default: false = dry-run)
///        MARK_POOL_RELEASE_WRITE_ARTIFACT — set true to write JSON artifact
///        MARK_POOL_RELEASE_ARTIFACT_PATH  — artifact output path
///        MARK_GIT_COMMIT           — git commit hash for artifact
contract ReleasePool is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    error PreflightFailed(string reason);

    struct ReleaseResult {
        bool execute;
        address deployer;
        address token;
        address accessManager;
        address pool;
        address ledger;
        address adapter;
    }

    function run() external {
        bool execute = vm.envOr("MARK_POOL_RELEASE_EXECUTE", false);
        bool writeArtifact = vm.envOr("MARK_POOL_RELEASE_WRITE_ARTIFACT", false);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address tokenAddress = vm.envAddress("MARK_RYLA_TOKEN");
        address verifierAddress = vm.envAddress("MARK_POOL_VERIFIER");

        // Preflight checks
        _preflight(deployer, tokenAddress, verifierAddress);

        if (!execute) {
            console.log("MARK_POOL_RELEASE_EXECUTE=false. Dry-run complete (no transactions broadcast).");
            if (writeArtifact) {
                _writeArtifact(
                    ReleaseResult({
                        execute: false,
                        deployer: deployer,
                        token: tokenAddress,
                        accessManager: address(0),
                        pool: address(0),
                        ledger: address(0),
                        adapter: address(0)
                    })
                );
            }
            return;
        }

        DeployMARKPool deployPool = new DeployMARKPool();
        DeployMARKPool.Deployed memory d = deployPool.run();

        // Post-deploy verification
        _verify(tokenAddress, d);

        ReleaseResult memory result = ReleaseResult({
            execute: true,
            deployer: deployer,
            token: tokenAddress,
            accessManager: address(d.accessManager),
            pool: address(d.pool),
            ledger: address(d.ledger),
            adapter: address(d.adapter)
        });

        if (writeArtifact) {
            _writeArtifact(result);
        } else {
            console.log("Artifact write disabled (MARK_POOL_RELEASE_WRITE_ARTIFACT=false).");
        }

        console.log("Pool release complete.");
        console.log("  AccessManager:", address(d.accessManager));
        console.log("  MARKPool:     ", address(d.pool));
        console.log("  RYLACreditLedger:", address(d.ledger));
        console.log("  MARKWithdrawAdapter:", address(d.adapter));
    }

    function _preflight(address deployer, address tokenAddress, address verifierAddress) internal view {
        if (tokenAddress == address(0)) revert PreflightFailed("MARK_RYLA_TOKEN not set");
        if (verifierAddress == address(0)) revert PreflightFailed("MARK_POOL_VERIFIER not set");
        if (tokenAddress.code.length == 0) revert PreflightFailed("MARK_RYLA_TOKEN is not a contract");
        if (verifierAddress.code.length == 0) revert PreflightFailed("MARK_POOL_VERIFIER is not a contract");

        RYLA token = RYLA(tokenAddress);
        if (!token.hasRole(DEFAULT_ADMIN_ROLE, deployer)) {
            revert PreflightFailed("deployer does not have DEFAULT_ADMIN_ROLE on RYLA");
        }
    }

    function _verify(address tokenAddress, DeployMARKPool.Deployed memory d) internal view {
        // Pool is wired to the correct ledger
        require(address(d.pool.ASSET_LEDGER()) == address(d.ledger), "pool ASSET_LEDGER mismatch");

        // Ledger is wired to pool and adapter
        require(d.ledger.POOL() == address(d.pool), "ledger POOL mismatch");
        require(d.ledger.ADAPTER() == address(d.adapter), "ledger ADAPTER mismatch");

        // Adapter is wired to ledger and pool
        require(address(d.adapter.ASSET_LEDGER()) == address(d.ledger), "adapter ASSET_LEDGER mismatch");
        require(address(d.adapter.PROOF_POOL()) == address(d.pool), "adapter PROOF_POOL mismatch");

        // RYLA roles granted to ledger
        RYLA token = RYLA(tokenAddress);
        bytes32 minterRole = token.MINTER_ROLE();
        bytes32 burnerRole = token.BURNER_ROLE();
        require(token.hasRole(minterRole, address(d.ledger)), "ledger missing MINTER_ROLE");
        require(token.hasRole(burnerRole, address(d.ledger)), "ledger missing BURNER_ROLE");

        console.log("Post-deploy verification passed.");
    }

    function _writeArtifact(ReleaseResult memory result) internal {
        string memory path =
            vm.envOr("MARK_POOL_RELEASE_ARTIFACT_PATH", string("broadcast/mark-pool-release-latest.json"));
        string memory root = "pool-release";
        _ensureParentDir(path);

        vm.serializeString(root, "protocol", "MARK");
        vm.serializeString(root, "component", "pool");
        vm.serializeBool(root, "execute", result.execute);
        vm.serializeAddress(root, "deployer", result.deployer);
        vm.serializeAddress(root, "token", result.token);
        vm.serializeAddress(root, "accessManager", result.accessManager);
        vm.serializeAddress(root, "pool", result.pool);
        vm.serializeAddress(root, "ledger", result.ledger);
        vm.serializeAddress(root, "adapter", result.adapter);
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeUint(root, "timestamp", block.timestamp);
        string memory json = vm.serializeString(root, "gitCommit", vm.envOr("MARK_GIT_COMMIT", string("unknown")));
        vm.writeJson(json, path);

        console.log("Pool release artifact written:", path);
    }

    function _ensureParentDir(string memory path) internal {
        bytes memory raw = bytes(path);
        uint256 split = type(uint256).max;
        for (uint256 i = raw.length; i > 0; i--) {
            if (raw[i - 1] == "/") split = i - 1;
            break;
        }
        if (split == type(uint256).max || split == 0) return;
        bytes memory parent = new bytes(split);
        for (uint256 j = 0; j < split; j++) {
            parent[j] = raw[j];
        }
        vm.createDir(string(parent), true);
    }
}
