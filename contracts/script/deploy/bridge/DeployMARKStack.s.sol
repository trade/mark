// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";

/// @notice Deploys RYLA token + MARK bridge adapter with optional initial operator/destination wiring.
contract DeployMARKStack is Script {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    error MissingAdapterAdminForRequestedConfig();

    function run() external returns (RYLA token, MARKBridgeAdapter adapter) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address owner = vm.envOr("MARK_RYLA_OWNER", deployer);
        address initialOperator = vm.envOr("MARK_BRIDGE_OPERATOR", address(0));
        uint256 initialDestinationChain = vm.envOr("MARK_BRIDGE_DESTINATION_CHAIN_ID", uint256(0));

        vm.startBroadcast(deployerKey);

        token = new RYLA(owner);
        adapter = new MARKBridgeAdapter(owner, address(token));

        bool deployerIsAdapterAdmin = adapter.hasRole(DEFAULT_ADMIN_ROLE, deployer);
        bool hasRequestedConfig = initialOperator != address(0) || initialDestinationChain != 0;

        if (hasRequestedConfig && !deployerIsAdapterAdmin) {
            revert MissingAdapterAdminForRequestedConfig();
        }

        if (deployerIsAdapterAdmin) {
            _configureAdapter(adapter, initialOperator, initialDestinationChain);
        }

        vm.stopBroadcast();

        console.log("RYLA:", address(token));
        console.log("MARKBridgeAdapter:", address(adapter));
    }

    function _configureAdapter(MARKBridgeAdapter adapter, address initialOperator, uint256 initialDestinationChain)
        internal
    {
        if (initialOperator != address(0)) {
            adapter.setOperator(initialOperator, true);
        }
        if (initialDestinationChain != 0) {
            adapter.setDestination(initialDestinationChain, true);
        }
    }
}
