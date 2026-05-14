// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKPool} from "../../../src/pool/MARKPool.sol";
import {MARKWithdrawAdapter} from "../../../src/withdraw/MARKWithdrawAdapter.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";

/// @notice Deploys MARKPool, RYLACreditLedger, and MARKWithdrawAdapter.
/// @dev Deployment sequence:
///      1. Deploy AccessManager (admin = owner)
///      2. Deploy MARKPool (authority = AccessManager, verifier)
///      3. Deploy RYLACreditLedger (token, pool) — pool address now known
///      4. Deploy MARKWithdrawAdapter (authority = AccessManager, ledger, pool)
///      5. Configure restricted selectors on pool and adapter via AccessManager
///      6. Call pool.setAssetLedger(ledger) — wires ledger for relayer fee credits
///      7. Grant MINTER_ROLE and BURNER_ROLE on RYLA to RYLACreditLedger
///
///      Required env vars:
///        PRIVATE_KEY         — deployer private key
///        MARK_RYLA_TOKEN     — deployed RYLA address
///        MARK_POOL_VERIFIER  — deployed MARKPoolVerifier address
///
///      Optional env vars:
///        MARK_POOL_OWNER         — AccessManager admin (defaults to deployer)
///        MARK_POOL_INTENT_SIGNER — initial intent signer for MARKWithdrawAdapter
contract DeployMARKPool is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    uint64 private constant POOL_ADMIN_ROLE = 1;

    error MissingTokenAdminForRoleGrants();

    struct Config {
        uint256 deployerKey;
        address deployer;
        address tokenAddress;
        address verifierAddress;
        address owner;
        address intentSigner;
    }

    struct Deployed {
        AccessManager accessManager;
        MARKPool pool;
        RYLACreditLedger ledger;
        MARKWithdrawAdapter adapter;
    }

    function run() external returns (Deployed memory d) {
        Config memory cfg = _loadConfig();
        RYLA token = RYLA(cfg.tokenAddress);

        if (!token.hasRole(DEFAULT_ADMIN_ROLE, cfg.deployer)) revert MissingTokenAdminForRoleGrants();

        vm.startBroadcast(cfg.deployerKey);

        // 1. AccessManager — admin is owner
        d.accessManager = new AccessManager(cfg.owner);

        // 2. MARKPool — no ledger needed at construction
        d.pool = new MARKPool(address(d.accessManager), cfg.verifierAddress);

        // 3. RYLACreditLedger — pool address now known
        d.ledger = new RYLACreditLedger(cfg.tokenAddress, address(d.pool));

        // 4. MARKWithdrawAdapter
        d.adapter = new MARKWithdrawAdapter(
            address(d.accessManager),
            address(d.ledger),
            address(d.pool)
        );

        // Wire adapter into ledger (one-time call — breaks circular deploy dependency)
        d.ledger.setAdapter(address(d.adapter));

        // 5. Grant POOL_ADMIN_ROLE to owner and deployer (deployer needs it for setup calls below)
        d.accessManager.grantRole(POOL_ADMIN_ROLE, cfg.owner, 0);
        if (cfg.deployer != cfg.owner) {
            d.accessManager.grantRole(POOL_ADMIN_ROLE, cfg.deployer, 0);
        }

        // 6. Assign restricted selectors on MARKPool to POOL_ADMIN_ROLE
        bytes4[] memory poolSelectors = new bytes4[](14);
        poolSelectors[0] = MARKPool.pause.selector;
        poolSelectors[1] = MARKPool.unpause.selector;
        poolSelectors[2] = MARKPool.pauseWithdrawals.selector;
        poolSelectors[3] = MARKPool.unpauseWithdrawals.selector;
        poolSelectors[4] = MARKPool.setVerifier.selector;
        poolSelectors[5] = MARKPool.setProofTypeEnabled.selector;
        poolSelectors[6] = MARKPool.emergencyDisableProofType.selector;
        poolSelectors[7] = MARKPool.setMaxRootAge.selector;
        poolSelectors[8] = MARKPool.setFeeBurnBps.selector;
        poolSelectors[9] = MARKPool.setMinFee.selector;
        poolSelectors[10] = MARKPool.setProtocolEpoch.selector;
        poolSelectors[11] = MARKPool.setBridgeOutEntrypoint.selector;
        poolSelectors[12] = MARKPool.bridgeIn.selector;
        poolSelectors[13] = MARKPool.setAssetLedger.selector;
        d.accessManager.setTargetFunctionRole(address(d.pool), poolSelectors, POOL_ADMIN_ROLE);

        // 7. Assign restricted selectors on MARKWithdrawAdapter to POOL_ADMIN_ROLE
        bytes4[] memory adapterSelectors = new bytes4[](4);
        adapterSelectors[0] = MARKWithdrawAdapter.pause.selector;
        adapterSelectors[1] = MARKWithdrawAdapter.unpause.selector;
        adapterSelectors[2] = MARKWithdrawAdapter.setMaxIntentValidity.selector;
        adapterSelectors[3] = MARKWithdrawAdapter.setIntentSigner.selector;
        d.accessManager.setTargetFunctionRole(address(d.adapter), adapterSelectors, POOL_ADMIN_ROLE);

        // 8. Wire ledger into pool (one-time call)
        d.pool.setAssetLedger(address(d.ledger));

        // 9. Set intent signer if provided
        if (cfg.intentSigner != address(0)) {
            d.adapter.setIntentSigner(cfg.intentSigner, true);
        }

        // 10. Grant RYLA roles to ledger
        token.setMinter(address(d.ledger), true);
        token.setBurner(address(d.ledger), true);

        // 11. Revoke deployer's temporary admin role if deployer != owner
        if (cfg.deployer != cfg.owner) {
            d.accessManager.revokeRole(POOL_ADMIN_ROLE, cfg.deployer);
        }

        vm.stopBroadcast();

        console.log("AccessManager:      ", address(d.accessManager));
        console.log("MARKPool:           ", address(d.pool));
        console.log("RYLACreditLedger:   ", address(d.ledger));
        console.log("MARKWithdrawAdapter:", address(d.adapter));
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.deployerKey = vm.envUint("PRIVATE_KEY");
        cfg.deployer = vm.addr(cfg.deployerKey);
        cfg.tokenAddress = vm.envAddress("MARK_RYLA_TOKEN");
        cfg.verifierAddress = vm.envAddress("MARK_POOL_VERIFIER");
        cfg.owner = vm.envOr("MARK_POOL_OWNER", cfg.deployer);
        cfg.intentSigner = vm.envOr("MARK_POOL_INTENT_SIGNER", address(0));
    }
}
