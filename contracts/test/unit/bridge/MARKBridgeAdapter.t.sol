// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {BridgeErrors} from "../../../src/errors/BridgeErrors.sol";
import {ISuperchainTokenBridge} from "@interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";

contract MARKBridgeAdapterTest is Test {
    RYLA internal token;
    MARKBridgeAdapter internal adapter;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant DST_CHAIN_ID = 902;
    address internal constant SUPERCHAIN_BRIDGE = PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE;

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);

        vm.startPrank(owner);
        token.setMinter(owner, true);
        token.mint(operator, 500 ether);
        adapter = new MARKBridgeAdapter(owner, address(token));
        adapter.setOperator(operator, true);
        adapter.setDestination(DST_CHAIN_ID, true);
        vm.stopPrank();

        vm.prank(operator);
        IERC20(address(token)).approve(address(adapter), type(uint256).max);
    }

    function testBridgeToRevertsWhenCallerNotOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), adapter.OPERATOR_ROLE()
            )
        );
        adapter.bridgeTo(recipient, 1 ether, DST_CHAIN_ID);
    }

    function testBridgeToRevertsWhenDestinationDisabled() public {
        vm.prank(owner);
        adapter.setDestination(DST_CHAIN_ID, false);

        vm.prank(operator);
        vm.expectRevert(BridgeErrors.DestinationDisabled.selector);
        adapter.bridgeTo(recipient, 1 ether, DST_CHAIN_ID);
    }

    function testBridgeToCallsSuperchainBridge() public {
        uint256 amount = 25 ether;
        bytes32 expectedHash = keccak256("bridge-hash-1");

        bytes memory callData = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, amount, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData, abi.encode(expectedHash));
        vm.expectCall(SUPERCHAIN_BRIDGE, callData);

        vm.prank(operator);
        bytes32 messageHash = adapter.bridgeTo(recipient, amount, DST_CHAIN_ID);

        assertEq(messageHash, expectedHash);
        assertEq(token.balanceOf(operator), 475 ether);
        assertEq(token.balanceOf(address(adapter)), amount);
    }

    function testBridgeToEnforcesMaxPerTx() public {
        vm.prank(owner);
        adapter.setBridgeLimits(10 ether, 0);

        vm.prank(operator);
        vm.expectRevert(BridgeErrors.MaxPerTxExceeded.selector);
        adapter.bridgeTo(recipient, 11 ether, DST_CHAIN_ID);
    }

    function testBridgeToEnforcesAndResetsDailyCap() public {
        vm.prank(owner);
        adapter.setBridgeLimits(0, 100 ether);

        bytes memory callData40 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, 40 ether, DST_CHAIN_ID
        );
        bytes memory callData60 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, 60 ether, DST_CHAIN_ID
        );

        vm.mockCall(SUPERCHAIN_BRIDGE, callData40, abi.encode(keccak256("h40")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, 40 ether, DST_CHAIN_ID);

        vm.prank(operator);
        vm.expectRevert(BridgeErrors.DailyCapExceeded.selector);
        adapter.bridgeTo(recipient, 70 ether, DST_CHAIN_ID);

        vm.warp(block.timestamp + 1 days + 1);

        vm.mockCall(SUPERCHAIN_BRIDGE, callData60, abi.encode(keccak256("h60")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, 60 ether, DST_CHAIN_ID);

        assertEq(adapter.bridgedInDailyCapEpoch(), 60 ether);
    }

    function testSetBridgeLimitsResetsEpochAccumulatorMidEpoch() public {
        vm.prank(owner);
        adapter.setBridgeLimits(0, 100 ether);

        bytes memory callData = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, 60 ether, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData, abi.encode(keccak256("h1")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, 60 ether, DST_CHAIN_ID);
        assertEq(adapter.bridgedInDailyCapEpoch(), 60 ether);

        // reset limits mid-epoch — accumulator and epoch should clear
        vm.prank(owner);
        adapter.setBridgeLimits(0, 200 ether);
        assertEq(adapter.bridgedInDailyCapEpoch(), 0);
        assertEq(adapter.dailyCapEpoch(), 0);

        // should now allow bridging up to new cap from zero
        bytes memory callData2 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, 150 ether, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData2, abi.encode(keccak256("h2")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, 150 ether, DST_CHAIN_ID);
        assertEq(adapter.bridgedInDailyCapEpoch(), 150 ether);
    }

    function testBridgeToRevertsWithBridgeFailedAndClearsApprovalOnSendERC20Revert() public {
        uint256 amount = 25 ether;

        bytes memory callData = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, amount, DST_CHAIN_ID
        );
        vm.mockCallRevert(SUPERCHAIN_BRIDGE, callData, "bridge down");

        vm.prank(operator);
        vm.expectRevert(BridgeErrors.BridgeFailed.selector);
        adapter.bridgeTo(recipient, amount, DST_CHAIN_ID);

        assertEq(token.allowance(address(adapter), SUPERCHAIN_BRIDGE), 0);
    }

    function testFuzz_BridgeLimitsRespectCapsAndDayReset(
        uint96 firstRaw,
        uint96 secondRaw,
        uint96 thirdRaw
    ) public {
        vm.prank(owner);
        adapter.setBridgeLimits(100 ether, 150 ether);

        uint256 first = bound(uint256(firstRaw), 1, 100 ether);
        uint256 second = bound(uint256(secondRaw), 1, 100 ether);
        uint256 third = bound(uint256(thirdRaw), 1, 100 ether);

        bytes memory callData1 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, first, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData1, abi.encode(keccak256("f1")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, first, DST_CHAIN_ID);

        bytes memory callData2 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, second, DST_CHAIN_ID
        );
        if (first + second > 150 ether) {
            vm.prank(operator);
            vm.expectRevert(BridgeErrors.DailyCapExceeded.selector);
            adapter.bridgeTo(recipient, second, DST_CHAIN_ID);
        } else {
            vm.mockCall(SUPERCHAIN_BRIDGE, callData2, abi.encode(keccak256("f2")));
            vm.prank(operator);
            adapter.bridgeTo(recipient, second, DST_CHAIN_ID);
            assertEq(adapter.bridgedInDailyCapEpoch(), first + second);
        }

        vm.warp(block.timestamp + 1 days + 1);

        bytes memory callData3 = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), recipient, third, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData3, abi.encode(keccak256("f3")));
        vm.prank(operator);
        adapter.bridgeTo(recipient, third, DST_CHAIN_ID);
        assertEq(adapter.bridgedInDailyCapEpoch(), third);
    }
}
