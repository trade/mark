// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKPool} from "../../src/pool/MARKPool.sol";
import {MARKWithdrawAdapter} from "../../src/withdraw/MARKWithdrawAdapter.sol";
import {RYLACreditLedger} from "../../src/pool/RYLACreditLedger.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {DeployMARKPool} from "../../script/deploy/pool/DeployMARKPool.s.sol";

contract MockVerifier is IVerifier {
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[13] calldata input
    ) external pure returns (bool) {
        return true;
    }
}

contract MARKPoolDeployScriptsTest is Test {
    uint256 internal constant DEPLOYER_PK = 0xA11CE;

    DeployMARKPool internal deployPool;
    MockVerifier internal verifier;

    address internal deployer;
    address internal intentSigner;

    function setUp() public {
        deployPool = new DeployMARKPool();
        verifier = new MockVerifier();

        deployer = vm.addr(DEPLOYER_PK);
        intentSigner = makeAddr("intentSigner");

        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));
        vm.setEnv("MARK_POOL_VERIFIER", vm.toString(address(verifier)));
        // Default to "no intent signer configured"; specific tests may override this env var.
        address defaultIntentSigner = address(0);
        vm.setEnv("MARK_POOL_INTENT_SIGNER", vm.toString(defaultIntentSigner));
        // Deploy local PoseidonT3 (test runner bypasses EIP-170 size check)
        address poseidon = deployCode("PoseidonT3.sol:PoseidonT3");
        vm.setEnv("MARK_POOL_POSEIDON", vm.toString(poseidon));

        // Deploy a default token so MARK_RYLA_TOKEN is always set before any test runs.
        // Individual tests may override this with vm.setEnv.
        vm.prank(deployer);
        RYLA defaultToken = new RYLA(deployer);
        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(defaultToken)));
    }

    function testDeployMARKPoolWiresAllContracts() public {
        vm.prank(deployer);
        RYLA token = new RYLA(deployer);

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));

        DeployMARKPool.Deployed memory d = deployPool.run();

        // Pool wired to ledger
        assertEq(address(d.pool.ASSET_LEDGER()), address(d.ledger));

        // Ledger wired to pool and adapter
        assertEq(d.ledger.POOL(), address(d.pool));
        assertEq(d.ledger.ADAPTER(), address(d.adapter));

        // Adapter wired to ledger and pool
        assertEq(address(d.adapter.ASSET_LEDGER()), address(d.ledger));
        assertEq(address(d.adapter.PROOF_POOL()), address(d.pool));

        // RYLA roles granted to ledger
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(d.ledger)));
        assertTrue(token.hasRole(token.BURNER_ROLE(), address(d.ledger)));
    }

    function testDeployMARKPoolSetsIntentSignerWhenProvided() public {
        vm.prank(deployer);
        RYLA token = new RYLA(deployer);

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        vm.setEnv("MARK_POOL_INTENT_SIGNER", vm.toString(intentSigner));

        DeployMARKPool.Deployed memory d = deployPool.run();

        assertTrue(d.adapter.intentSigners(intentSigner));
    }

    function testDeployMARKPoolRevertsWhenMissingTokenAdmin() public {
        address nonAdmin = makeAddr("nonAdmin");
        vm.prank(nonAdmin);
        RYLA token = new RYLA(nonAdmin);

        vm.setEnv("MARK_RYLA_TOKEN", vm.toString(address(token)));
        // Ensure PRIVATE_KEY is set so _loadConfig() succeeds and the
        // MissingTokenAdminForRoleGrants check is reached. Without this,
        // vm.envUint reverts with no data when gas-check runs in a fresh
        // process where setUp() env vars are not inherited.
        vm.setEnv("PRIVATE_KEY", vm.toString(DEPLOYER_PK));

        vm.expectRevert(DeployMARKPool.MissingTokenAdminForRoleGrants.selector);
        deployPool.run();
    }
}
