// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../src/settlement/verifier/AttestedSettlementVerifier.sol";

contract MARKAdminDelayTest is Test {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal owner = makeAddr("owner");
    address internal newOwner = makeAddr("newOwner");
    address internal tokenAddress;

    RYLA internal token;
    MARKBridgeAdapter internal adapter;
    MARKSettlementModule internal module;
    AttestedSettlementVerifier internal verifier;

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);
        tokenAddress = address(token);

        vm.prank(owner);
        adapter = new MARKBridgeAdapter(owner, tokenAddress);

        vm.prank(owner);
        module = new MARKSettlementModule(owner, tokenAddress);

        vm.prank(owner);
        verifier = new AttestedSettlementVerifier(owner);
    }

    function testAdminTransferRequiresDelayAcrossCoreContracts() public {
        _assertAdminTransfer(address(token));
        _assertAdminTransfer(address(adapter));
        _assertAdminTransfer(address(module));
        _assertAdminTransfer(address(verifier));
    }

    function testCancelAdminTransferKeepsCurrentAdmin() public {
        vm.startPrank(owner);
        token.beginDefaultAdminTransfer(newOwner);
        token.cancelDefaultAdminTransfer();
        vm.stopPrank();

        (address pendingAdmin, uint48 schedule) = token.pendingDefaultAdmin();
        assertEq(pendingAdmin, address(0));
        assertEq(schedule, 0);

        vm.warp(block.timestamp + token.defaultAdminDelay() + 1);
        vm.prank(newOwner);
        vm.expectRevert();
        token.acceptDefaultAdminTransfer();

        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }

    function _assertAdminTransfer(address contractAddress) internal {
        RYLALike target = RYLALike(contractAddress);

        vm.prank(owner);
        target.beginDefaultAdminTransfer(newOwner);

        (address pendingAdmin, uint48 schedule) = target.pendingDefaultAdmin();
        assertEq(pendingAdmin, newOwner);
        assertEq(schedule, uint48(block.timestamp + target.defaultAdminDelay()));

        vm.prank(newOwner);
        vm.expectRevert();
        target.acceptDefaultAdminTransfer();

        vm.warp(block.timestamp + target.defaultAdminDelay() + 1);
        vm.prank(newOwner);
        target.acceptDefaultAdminTransfer();

        assertFalse(target.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(target.hasRole(DEFAULT_ADMIN_ROLE, newOwner));
    }
}

interface RYLALike {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function beginDefaultAdminTransfer(address newAdmin) external;
    function cancelDefaultAdminTransfer() external;
    function acceptDefaultAdminTransfer() external;
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
    function defaultAdminDelay() external view returns (uint48);
}

