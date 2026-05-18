// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";

/// @notice Bridge E2E test: mint RYLA via settlement, then bridge to destination chain.
/// @dev Requires:
///      - Deployer has OPERATOR_ROLE on MARKSettlementModule
///      - Proof validation is disabled on the module (staging only)
///
///      Run against OP Sepolia:
///        PRIVATE_KEY=<key> forge script script/ops/bridge/BridgeE2E.s.sol \
///          --rpc-url https://sepolia.optimism.io --broadcast -vv
///
///      Dry-run (no broadcast):
///        forge script script/ops/bridge/BridgeE2E.s.sol \
///          --rpc-url https://sepolia.optimism.io -vv
contract BridgeE2E is Script {
    address constant RYLA_ADDR   = 0xa27360e124B94449249D1E919d3363BfF1c10c02;
    address constant MODULE_ADDR = 0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59;
    address constant BRIDGE_ADDR = 0x5F3823739E510981A821aC5E99235e36f65cBc71;

    uint256 constant DST_CHAIN_ID  = 11155420; // OP Sepolia (same-chain for initial test)
    uint256 constant BRIDGE_AMOUNT = 1e18;     // 1 RYLA

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        RYLA ryla = RYLA(RYLA_ADDR);
        MARKSettlementModule module = MARKSettlementModule(MODULE_ADDR);
        MARKBridgeAdapter bridge = MARKBridgeAdapter(BRIDGE_ADDR);

        console.log("Deployer:", deployer);
        console.log("RYLA balance before:", ryla.balanceOf(deployer));

        // Preflight checks
        require(module.hasRole(module.OPERATOR_ROLE(), deployer), "deployer not operator");
        require(!module.proofValidationEnabled(), "proof validation enabled - disable for staging test");
        require(bridge.destinationEnabled(DST_CHAIN_ID), "destination chain not enabled");

        vm.startBroadcast(deployerKey);

        // 1. Mint RYLA via settleMint (no proof needed when validation disabled)
        bytes32 intentId = keccak256(abi.encodePacked("bridge-e2e", block.timestamp, deployer));
        module.settleMint(deployer, BRIDGE_AMOUNT, intentId, bytes(""));
        console.log("Minted 1 RYLA. Balance:", ryla.balanceOf(deployer));

        // 2. Approve bridge adapter
        ryla.approve(BRIDGE_ADDR, BRIDGE_AMOUNT);

        // 3. Bridge to destination chain
        bridge.bridgeTo(deployer, BRIDGE_AMOUNT, DST_CHAIN_ID);
        console.log("Bridged 1 RYLA to chain", DST_CHAIN_ID);
        console.log("Balance after bridge:", ryla.balanceOf(deployer));
        console.log("TotalSupply after bridge:", ryla.totalSupply());

        vm.stopBroadcast();
        console.log("Bridge E2E PASSED");
    }
}
