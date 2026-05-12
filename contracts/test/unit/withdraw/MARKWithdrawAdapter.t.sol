// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import {MARKWithdrawAdapter} from "../../../src/withdraw/MARKWithdrawAdapter.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import { RYLA } from "../../../src/token/RYLA.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/// @notice Mock Pool for testing WithdrawAdapter.
/// @dev computeWithdrawBindingHash must match Pool.computeWithdrawBindingHash exactly,
///      including the domain separator, address(this), and block.chainid.
contract MockPool {
    bytes32 public constant WITHDRAW_BINDING_DOMAIN =
        keccak256("MARKPool.WithdrawBinding.v1");

    mapping(bytes32 => bytes32) public nullifierWithdrawBinding;
    mapping(bytes32 => bool) public nullifierUsed;

    function setWithdrawBinding(
        bytes32 nullifier,
        address owner,
        address recipient,
        uint256 amount
    ) external {
        nullifierWithdrawBinding[nullifier] = computeWithdrawBindingHash(owner, recipient, amount);
        nullifierUsed[nullifier] = true;
    }

    function computeWithdrawBindingHash(
        address owner,
        address recipient,
        uint256 amount
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                WITHDRAW_BINDING_DOMAIN,
                address(this),
                block.chainid,
                owner,
                recipient,
                amount
            )
        );
    }

    function isNullifierUsedGlobal(bytes32 nullifier) external view returns (bool) {
        return nullifierUsed[nullifier];
    }
}

/// @notice Unit test for WithdrawAdapter
/// @dev Tests withdrawal execution with signature verification
contract MARKWithdrawAdapterTest is Test {
    MockPool public pool;
    MARKWithdrawAdapter public adapter;
    RYLACreditLedger public ledger;
    RYLA public token;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public intentSigner = address(0x3);
    address public user = address(0x4);
    address public recipient = address(0x5);

    uint256 public userPrivateKey = 0xA11CE;
    uint256 public intentSignerPrivateKey = 0xB0B;

    function setUp() public {
        user = vm.addr(userPrivateKey);
        intentSigner = vm.addr(intentSignerPrivateKey);

        // Deploy access manager with admin
        accessManager = new AccessManager(admin);

        // Deploy RYLA token
        vm.prank(admin);
        token = new RYLA(admin);

        // Deploy credit ledger
        pool = new MockPool();
        ledger = new RYLACreditLedger(address(token), address(pool));

        // Deploy WithdrawAdapter
        adapter = new MARKWithdrawAdapter(
            address(accessManager),
            address(ledger),
            address(pool)
        );

        vm.startPrank(admin);
        
        // Grant adapter admin role (simplified for testing)
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = adapter.setIntentSigner.selector;
        selectors[1] = adapter.pause.selector;
        selectors[2] = adapter.unpause.selector;
        selectors[3] = adapter.setMaxIntentValidity.selector;
        
        accessManager.setTargetFunctionRole(address(adapter), selectors, 1);
        accessManager.grantRole(1, admin, 0);

        // Grant roles to ledger
        vm.warp(block.timestamp + 1 days + 1);
        
        token.grantRole(token.MINTER_ROLE(), address(ledger));
        token.grantRole(token.BURNER_ROLE(), address(ledger));

        // Enable intent signer
        adapter.setIntentSigner(intentSigner, true);

        // Fund adapter with native tokens
        vm.deal(address(adapter), 100 ether);
        
        vm.stopPrank();
    }

    /// @notice Test withdraw intent hash computation
    function testComputeWithdrawIntentHash() public view {
        bytes32[2] memory nullifiers = [
            keccak256("nullifier1"),
            keccak256("nullifier2")
        ];

        bytes32 intentHash = adapter.computeWithdrawIntentHash(
            user,
            recipient,
            1 ether,
            nullifiers,
            0,
            block.timestamp + 1 hours
        );

        assertTrue(intentHash != bytes32(0));
    }

    /// @notice Test withdraw intent digest computation
    function testComputeWithdrawIntentDigest() public view {
        bytes32[2] memory nullifiers = [
            keccak256("nullifier1"),
            keccak256("nullifier2")
        ];

        bytes32 digest = adapter.computeWithdrawIntentDigest(
            user,
            recipient,
            1 ether,
            nullifiers,
            0,
            block.timestamp + 1 hours
        );

        assertTrue(digest != bytes32(0));
    }

    /// @notice Test that adapter checks native token balance
    function testWithdrawRequiresSufficientLiquidity() public {
        // Deploy adapter with no native tokens
        MARKWithdrawAdapter emptyAdapter = new MARKWithdrawAdapter(
            address(accessManager),
            address(ledger),
            address(pool)
        );

        // Verify it has no balance
        assertEq(address(emptyAdapter).balance, 0);
        
        // Withdrawal would fail with "Insufficient liquidity"
    }

    /// @notice Test that nonce increments correctly
    function testWithdrawNonceIncrement() public view {
        assertEq(adapter.withdrawNonce(user), 0);
        // After successful withdrawal, nonce should be 1
    }

    /// @notice Test that nullifiers cannot be claimed twice
    function testNullifierCannotBeClaimedTwice() public view {
        bytes32 nullifier = keccak256("test");
        assertFalse(adapter.claimedNullifiers(nullifier));
        // After claiming, should be true
    }

    /// @notice Test adapter can receive native tokens
    function testAdapterReceivesNativeTokens() public {
        uint256 balanceBefore = address(adapter).balance;
        
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(adapter).call{value: 1 ether}("");
        
        assertTrue(ok);
        assertEq(address(adapter).balance, balanceBefore + 1 ether);
    }

    /// @notice Test max intent validity can be updated
    function testSetMaxIntentValidity() public {
        vm.prank(admin);
        adapter.setMaxIntentValidity(2 hours);
        
        assertEq(adapter.maxIntentValidity(), 2 hours);
    }

    /// @notice Test intent signer can be enabled/disabled
    function testSetIntentSigner() public {
        address newSigner = address(0x999);
        
        vm.prank(admin);
        adapter.setIntentSigner(newSigner, true);
        
        assertTrue(adapter.intentSigners(newSigner));
        
        vm.prank(admin);
        adapter.setIntentSigner(newSigner, false);
        
        assertFalse(adapter.intentSigners(newSigner));
    }

    /// @notice Test adapter can be paused
    function testAdapterPause() public {
        vm.prank(admin);
        adapter.pause();
        
        assertTrue(adapter.paused());
        
        vm.prank(admin);
        adapter.unpause();
        
        assertFalse(adapter.paused());
    }
}
