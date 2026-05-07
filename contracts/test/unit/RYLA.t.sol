// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../src/token/RYLA.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";
import {Unauthorized} from "@interop-lib/libraries/errors/CommonErrors.sol";
import {ZeroAddress} from "@interop-lib/libraries/errors/CommonErrors.sol";
import {TokenErrors} from "../../src/errors/TokenErrors.sol";

contract RYLATest is Test {
    RYLA internal token;

    address internal owner = makeAddr("owner");
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);
    }

    function testMetadata() public view {
        assertEq(token.name(), "RYLA");
        assertEq(token.symbol(), "RYLA");
        assertEq(token.decimals(), 18);
    }

    function testOwnerCanSetRolesAndMintBurn() public {
        vm.startPrank(owner);
        token.setMinter(minter, true);
        token.setBurner(burner, true);
        vm.stopPrank();

        vm.prank(minter);
        token.mint(user, 10 ether);
        assertEq(token.balanceOf(user), 10 ether);

        vm.prank(user);
        bool ok = token.transfer(burner, 3 ether);
        assertTrue(ok);
        assertEq(token.balanceOf(burner), 3 ether);

        vm.prank(burner);
        token.burn(3 ether);
        assertEq(token.balanceOf(burner), 0);
        assertEq(token.totalSupply(), 7 ether);
    }

    function testMintRevertsForUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.MINTER_ROLE())
        );
        vm.prank(user);
        token.mint(user, 1 ether);
    }

    function testCrosschainMintOnlySuperchainBridge() public {
        vm.expectRevert(Unauthorized.selector);
        token.crosschainMint(user, 1 ether);

        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainMint(user, 2 ether);
        assertEq(token.balanceOf(user), 2 ether);
    }

    function testCrosschainBurnOnlySuperchainBridge() public {
        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainMint(user, 5 ether);
        assertEq(token.balanceOf(user), 5 ether);

        vm.expectRevert(Unauthorized.selector);
        token.crosschainBurn(user, 1 ether);

        vm.prank(PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE);
        token.crosschainBurn(user, 2 ether);
        assertEq(token.balanceOf(user), 3 ether);
    }

    function testSupportsInterface() public view {
        // ERC165
        assertTrue(token.supportsInterface(0x01ffc9a7));
        // IAccessControl
        assertTrue(token.supportsInterface(0x7965db0b));
        // random — should return false
        assertFalse(token.supportsInterface(0xdeadbeef));
    }

    function testSetMinterRevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        token.setMinter(address(0), true);
    }

    function testSetBurnerRevertsForZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        token.setBurner(address(0), true);
    }

    function testBurnRevertsForZeroAmount() public {
        vm.startPrank(owner);
        token.setBurner(burner, true);
        vm.stopPrank();

        vm.prank(burner);
        vm.expectRevert(TokenErrors.InvalidAmount.selector);
        token.burn(0);
    }
}
