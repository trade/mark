// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MARKWithdrawAdapter} from "../../../src/withdraw/MARKWithdrawAdapter.sol";
import {MARKWithdrawErrors} from "../../../src/withdraw/MARKWithdrawErrors.sol";
import {RYLACreditLedger} from "../../../src/pool/RYLACreditLedger.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/// @notice Mock Pool for testing WithdrawAdapter.
/// @dev computeWithdrawBindingHash must match Pool.computeWithdrawBindingHash exactly,
///      including the domain separator, address(this), and block.chainid.
contract MockPool {
    bytes32 public constant WITHDRAW_BINDING_DOMAIN = keccak256("MARKPool.WithdrawBinding.v1");

    mapping(bytes32 => bytes32) public nullifierWithdrawBinding;
    mapping(bytes32 => bool) public nullifierUsed;

    function setWithdrawBinding(bytes32 nullifier, address owner, address recipient, uint256 amount) external {
        nullifierWithdrawBinding[nullifier] = computeWithdrawBindingHash(owner, recipient, amount);
        nullifierUsed[nullifier] = true;
    }

    function computeWithdrawBindingHash(address owner, address recipient, uint256 amount)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAW_BINDING_DOMAIN, address(this), block.chainid, owner, recipient, amount));
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

        accessManager = new AccessManager(admin);

        vm.prank(admin);
        token = new RYLA(admin);

        pool = new MockPool();
        ledger = new RYLACreditLedger(address(token), address(pool));

        adapter = new MARKWithdrawAdapter(address(accessManager), address(ledger), address(pool));
        ledger.setAdapter(address(adapter));

        vm.startPrank(admin);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = adapter.setIntentSigner.selector;
        selectors[1] = adapter.pause.selector;
        selectors[2] = adapter.unpause.selector;
        selectors[3] = adapter.setMaxIntentValidity.selector;

        accessManager.setTargetFunctionRole(address(adapter), selectors, 1);
        accessManager.grantRole(1, admin, 0);

        vm.warp(block.timestamp + 1 days + 1);

        token.grantRole(token.MINTER_ROLE(), address(ledger));
        token.grantRole(token.BURNER_ROLE(), address(ledger));

        adapter.setIntentSigner(intentSigner, true);

        vm.deal(address(adapter), 100 ether);

        vm.stopPrank();
    }

    function testComputeWithdrawIntentHash() public view {
        bytes32[2] memory nullifiers = [keccak256("nullifier1"), keccak256("nullifier2")];

        bytes32 intentHash =
            adapter.computeWithdrawIntentHash(user, recipient, 1 ether, nullifiers, 0, block.timestamp + 1 hours);

        assertTrue(intentHash != bytes32(0));
    }

    function testComputeWithdrawIntentDigest() public view {
        bytes32[2] memory nullifiers = [keccak256("nullifier1"), keccak256("nullifier2")];

        bytes32 digest =
            adapter.computeWithdrawIntentDigest(user, recipient, 1 ether, nullifiers, 0, block.timestamp + 1 hours);

        assertTrue(digest != bytes32(0));
    }

    function testWithdrawWithSigHappyPathIncrementsNonceAndClaimsNullifiers() public {
        bytes32[2] memory nullifiers = [keccak256("n-happy-1"), keccak256("n-happy-2")];
        uint256 amount = 2 ether;
        uint256 nonce = adapter.withdrawNonce(user);
        uint256 deadline = block.timestamp + 30 minutes;

        _configureBindingAndMint(user, recipient, amount, nullifiers);
        (bytes memory ownerSig, bytes memory intentSig) =
            _signWithdraw(user, recipient, amount, nullifiers, nonce, deadline, userPrivateKey, intentSignerPrivateKey);

        uint256 recipientBefore = recipient.balance;
        uint256 userTokenBefore = token.balanceOf(user);

        adapter.withdrawWithSig(user, recipient, amount, nullifiers, nonce, deadline, ownerSig, intentSig);

        assertEq(adapter.withdrawNonce(user), nonce + 1);
        assertTrue(adapter.claimedNullifiers(nullifiers[0]));
        assertTrue(adapter.claimedNullifiers(nullifiers[1]));
        assertEq(recipient.balance, recipientBefore + amount);
        assertEq(token.balanceOf(user), userTokenBefore - amount);
    }

    function testWithdrawWithSigRevertsForInsufficientLiquidity() public {
        MARKWithdrawAdapter emptyAdapter =
            new MARKWithdrawAdapter(address(accessManager), address(ledger), address(pool));

        bytes32[2] memory nullifiers = [keccak256("n-empty-1"), keccak256("n-empty-2")];
        uint256 amount = 1 ether;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 30 minutes;

        _configureBindingAndMint(user, recipient, amount, nullifiers);

        // Sign using emptyAdapter's domain (address(emptyAdapter) is part of the intent hash)
        (bytes memory ownerSig, bytes memory intentSig) =
            _signWithdrawForAdapter(emptyAdapter, user, recipient, amount, nullifiers, nonce, deadline, userPrivateKey, intentSignerPrivateKey);

        vm.expectRevert(MARKWithdrawErrors.InsufficientLiquidity.selector);
        emptyAdapter.withdrawWithSig(user, recipient, amount, nullifiers, nonce, deadline, ownerSig, intentSig);
    }

    function testWithdrawWithSigRevertsOnReplayByNonce() public {
        bytes32[2] memory nullifiers = [keccak256("n-replay-1"), keccak256("n-replay-2")];
        uint256 amount = 1 ether;
        uint256 nonce = adapter.withdrawNonce(user);
        uint256 deadline = block.timestamp + 30 minutes;

        _configureBindingAndMint(user, recipient, amount, nullifiers);
        (bytes memory ownerSig, bytes memory intentSig) =
            _signWithdraw(user, recipient, amount, nullifiers, nonce, deadline, userPrivateKey, intentSignerPrivateKey);

        adapter.withdrawWithSig(user, recipient, amount, nullifiers, nonce, deadline, ownerSig, intentSig);

        vm.expectRevert(MARKWithdrawErrors.NonceMismatch.selector);
        adapter.withdrawWithSig(user, recipient, amount, nullifiers, nonce, deadline, ownerSig, intentSig);
    }

    function testWithdrawWithSigRevertsOnBindingMismatch() public {
        bytes32[2] memory nullifiers = [keccak256("n-bind-1"), keccak256("n-bind-2")];
        uint256 amount = 1 ether;
        uint256 nonce = adapter.withdrawNonce(user);
        uint256 deadline = block.timestamp + 30 minutes;

        _configureBindingAndMint(user, recipient, amount, nullifiers);
        (bytes memory ownerSig, bytes memory intentSig) =
            _signWithdraw(user, recipient, amount, nullifiers, nonce, deadline, userPrivateKey, intentSignerPrivateKey);

        vm.expectRevert(MARKWithdrawErrors.WithdrawBindingMismatch.selector);
        adapter.withdrawWithSig(
            user, makeAddr("other-recipient"), amount, nullifiers, nonce, deadline, ownerSig, intentSig
        );
    }

    function testWithdrawWithSigRevertsOnUnauthorizedIntentSigner() public {
        bytes32[2] memory nullifiers = [keccak256("n-auth-1"), keccak256("n-auth-2")];
        uint256 amount = 1 ether;
        uint256 nonce = adapter.withdrawNonce(user);
        uint256 deadline = block.timestamp + 30 minutes;

        _configureBindingAndMint(user, recipient, amount, nullifiers);
        (bytes memory ownerSig, bytes memory intentSig) =
            _signWithdraw(user, recipient, amount, nullifiers, nonce, deadline, userPrivateKey, 0xDEAD);

        vm.expectRevert(MARKWithdrawErrors.UnauthorizedIntentSigner.selector);
        adapter.withdrawWithSig(user, recipient, amount, nullifiers, nonce, deadline, ownerSig, intentSig);
    }

    function testAdapterReceivesNativeTokens() public {
        uint256 balanceBefore = address(adapter).balance;

        vm.deal(address(this), 1 ether);
        (bool ok,) = address(adapter).call{value: 1 ether}("");

        assertTrue(ok);
        assertEq(address(adapter).balance, balanceBefore + 1 ether);
    }

    function testSetMaxIntentValidity() public {
        vm.prank(admin);
        adapter.setMaxIntentValidity(2 hours);

        assertEq(adapter.maxIntentValidity(), 2 hours);
    }

    function testSetIntentSigner() public {
        address newSigner = address(0x999);

        vm.prank(admin);
        adapter.setIntentSigner(newSigner, true);

        assertTrue(adapter.intentSigners(newSigner));

        vm.prank(admin);
        adapter.setIntentSigner(newSigner, false);

        assertFalse(adapter.intentSigners(newSigner));
    }

    function testAdapterPause() public {
        vm.prank(admin);
        adapter.pause();

        assertTrue(adapter.paused());

        vm.prank(admin);
        adapter.unpause();

        assertFalse(adapter.paused());
    }

    function _configureBindingAndMint(
        address owner,
        address withdrawRecipient,
        uint256 amount,
        bytes32[2] memory nullifiers
    ) internal {
        pool.setWithdrawBinding(nullifiers[0], owner, withdrawRecipient, amount);
        pool.setWithdrawBinding(nullifiers[1], owner, withdrawRecipient, amount);

        vm.prank(address(pool));
        ledger.credit(owner, amount);

        vm.prank(owner);
        token.approve(address(ledger), type(uint256).max);
    }

    function _signWithdraw(
        address owner,
        address withdrawRecipient,
        uint256 amount,
        bytes32[2] memory nullifiers,
        uint256 nonce,
        uint256 deadline,
        uint256 ownerPk,
        uint256 intentPk
    ) internal view returns (bytes memory ownerSig, bytes memory intentSig) {
        return _signWithdrawForAdapter(adapter, owner, withdrawRecipient, amount, nullifiers, nonce, deadline, ownerPk, intentPk);
    }

    function _signWithdrawForAdapter(
        MARKWithdrawAdapter targetAdapter,
        address owner,
        address withdrawRecipient,
        uint256 amount,
        bytes32[2] memory nullifiers,
        uint256 nonce,
        uint256 deadline,
        uint256 ownerPk,
        uint256 intentPk
    ) internal view returns (bytes memory ownerSig, bytes memory intentSig) {
        bytes32 intentHash = targetAdapter.computeWithdrawIntentHash(
            owner, withdrawRecipient, amount, nullifiers, nonce, deadline
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", intentHash));

        (uint8 ov, bytes32 or_, bytes32 os) = vm.sign(ownerPk, digest);
        (uint8 iv, bytes32 ir, bytes32 is_) = vm.sign(intentPk, digest);

        ownerSig = abi.encodePacked(or_, os, ov);
        intentSig = abi.encodePacked(ir, is_, iv);
    }

    function testWithdrawWithSigRevertsForZeroRecipient() public {
        vm.expectRevert(MARKWithdrawErrors.InvalidRecipient.selector);
        adapter.withdrawWithSig(
            user, address(0), 1 ether, [keccak256("n1"), keccak256("n2")], 0, block.timestamp + 1, bytes(""), bytes("")
        );
    }
}
