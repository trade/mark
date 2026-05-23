// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {ISuperchainTokenBridge} from "@interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";

contract MARKBridgeE2ETest is Test {
    RYLA internal token;
    MARKBridgeAdapter internal adapter;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal user = makeAddr("user");

    uint256 internal constant DST_CHAIN_ID = 902;

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);

        vm.startPrank(owner);
        token.setMinter(owner, true);
        token.mint(operator, 100 ether);
        adapter = new MARKBridgeAdapter(owner, address(token));
        adapter.setOperator(operator, true);
        adapter.setDestination(DST_CHAIN_ID, true);
        vm.stopPrank();

        vm.prank(operator);
        token.approve(address(adapter), type(uint256).max);
    }

    function testE2EBridgeFlow() public {
        uint256 amount = 10 ether;
        
        bytes memory callData = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector,
            address(token),
            user,
            amount,
            DST_CHAIN_ID
        );
        vm.mockCall(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE, callData, abi.encode(keccak256("msg-1")));

        uint256 operatorBalanceBefore = token.balanceOf(operator);
        uint256 adapterBalanceBefore = token.balanceOf(address(adapter));

        vm.prank(operator);
        bytes32 messageHash = adapter.bridgeTo(user, amount, DST_CHAIN_ID);

        assertEq(token.balanceOf(operator), operatorBalanceBefore - amount);
        assertEq(token.balanceOf(address(adapter)), adapterBalanceBefore + amount);
        assertTrue(messageHash != bytes32(0));
    }

    function testE2EBridgeWithRateLimits() public {
        vm.prank(owner);
        adapter.setBridgeLimits(5 ether, 20 ether);

        bytes memory callData1 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector,
            address(token),
            user,
            5 ether,
            DST_CHAIN_ID
        );
        vm.mockCall(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE, callData1, abi.encode(keccak256("msg-1")));

        vm.prank(operator);
        adapter.bridgeTo(user, 5 ether, DST_CHAIN_ID);

        assertEq(adapter.bridgedInDailyCapEpoch(), 5 ether);

        bytes memory callData2 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector,
            address(token),
            user,
            5 ether,
            DST_CHAIN_ID
        );
        vm.mockCall(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE, callData2, abi.encode(keccak256("msg-2")));

        vm.prank(operator);
        adapter.bridgeTo(user, 5 ether, DST_CHAIN_ID);

        assertEq(adapter.bridgedInDailyCapEpoch(), 10 ether);
    }
}
