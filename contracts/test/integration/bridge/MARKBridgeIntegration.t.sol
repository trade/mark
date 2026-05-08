// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";

/// @notice Integration test for MARKBridgeAdapter against live supersim chains.
/// @dev Requires two running supersim L2 forks:
///      CHAIN_A_RPC_URL (default: http://127.0.0.1:9545) — source chain
///      CHAIN_B_RPC_URL (default: http://127.0.0.1:9546) — destination chain
///
///      Run with:
///        CHAIN_A_RPC_URL=http://127.0.0.1:9545 \
///        CHAIN_B_RPC_URL=http://127.0.0.1:9546 \
///        FOUNDRY_PROFILE=integration forge test --match-path 'test/integration/**/*.t.sol' -vv
contract MARKBridgeIntegrationTest is Test {
    string internal chainAUrl;
    string internal chainBUrl;

    uint256 internal forkA;
    uint256 internal forkB;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal recipient = makeAddr("recipient");

    RYLA internal token;
    MARKBridgeAdapter internal adapter;

    function setUp() public {
        chainAUrl = vm.envOr("CHAIN_A_RPC_URL", string("http://127.0.0.1:9545"));
        chainBUrl = vm.envOr("CHAIN_B_RPC_URL", string("http://127.0.0.1:9546"));

        forkA = vm.createFork(chainAUrl);
        forkB = vm.createFork(chainBUrl);

        // Deploy on chain A.
        vm.selectFork(forkA);
        uint256 destChainId = vm.envOr("CHAIN_B_CHAIN_ID", uint256(902));

        vm.startPrank(owner);
        token = new RYLA(owner);
        token.setMinter(owner, true);
        token.mint(operator, 100 ether);

        adapter = new MARKBridgeAdapter(owner, address(token));
        adapter.setOperator(operator, true);
        adapter.setDestination(destChainId, true);
        vm.stopPrank();

        vm.prank(operator);
        token.approve(address(adapter), type(uint256).max);
    }

    /// @notice Verifies that bridgeTo burns tokens on chain A and the recipient
    ///         receives them on chain B via SuperchainTokenBridge auto-relay.
    function testBridgeToTransfersTokensCrossChain() public {
        vm.selectFork(forkA);
        uint256 destChainId = vm.envOr("CHAIN_B_CHAIN_ID", uint256(902));
        uint256 amount = 10 ether;

        uint256 operatorBalanceBefore = token.balanceOf(operator);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(operator);
        adapter.bridgeTo(recipient, amount, destChainId);

        // Tokens are burned on chain A by SuperchainTokenBridge.
        assertEq(token.balanceOf(operator), operatorBalanceBefore - amount, "operator balance not reduced");
        assertEq(token.totalSupply(), supplyBefore - amount, "supply not reduced on chain A");

        // Supersim auto-relays the message; verify recipient balance on chain B.
        vm.selectFork(forkB);
        // RYLA is a SuperchainERC20 — same address on both chains via CREATE2.
        address tokenOnB = address(token);
        assertEq(RYLA(tokenOnB).balanceOf(recipient), amount, "recipient did not receive tokens on chain B");
    }

    /// @notice Verifies that rate limits are enforced even against the live bridge.
    function testBridgeToEnforcesMaxPerTxOnLiveFork() public {
        vm.selectFork(forkA);
        uint256 destChainId = vm.envOr("CHAIN_B_CHAIN_ID", uint256(902));

        vm.prank(owner);
        adapter.setBridgeLimits(5 ether, 0);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("MaxPerTxExceeded()"));
        adapter.bridgeTo(recipient, 6 ether, destChainId);
    }
}
