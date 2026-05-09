// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {ISuperchainTokenBridge} from "@interop-lib/interfaces/ISuperchainTokenBridge.sol";
import {PredeployAddresses} from "@interop-lib/libraries/PredeployAddresses.sol";

contract MARKBridgeHandler is Test {
    RYLA public immutable token;
    MARKBridgeAdapter public immutable adapter;
    address public immutable owner;
    address public immutable operator;

    address internal constant SUPERCHAIN_BRIDGE = PredeployAddresses.SUPERCHAIN_TOKEN_BRIDGE;
    uint256 internal constant DST_CHAIN_ID = 902;

    uint256 internal nonce;

    constructor(RYLA _token, MARKBridgeAdapter _adapter, address _owner, address _operator) {
        token = _token;
        adapter = _adapter;
        owner = _owner;
        operator = _operator;
    }

    function bridge(uint96 rawAmount) external {
        uint256 maxPerTx_ = adapter.maxPerTx();
        uint256 dailyCap_ = adapter.dailyCap();

        uint256 ceiling = maxPerTx_ > 0 ? maxPerTx_ : 1_000_000 ether;
        uint256 amount = bound(uint256(rawAmount), 1, ceiling);

        // Skip if daily cap would be exceeded — lets fuzzer explore more paths.
        if (dailyCap_ > 0) {
            uint64 epoch = uint64(block.timestamp / 1 days);
            uint256 accumulated = epoch == adapter.dailyCapEpoch() ? adapter.bridgedInDailyCapEpoch() : 0;
            if (accumulated + amount > dailyCap_) return;
        }

        vm.prank(owner);
        token.mint(operator, amount);

        bytes memory callData = abi.encodeWithSelector(
            ISuperchainTokenBridge.sendERC20.selector, address(token), operator, amount, DST_CHAIN_ID
        );
        vm.mockCall(SUPERCHAIN_BRIDGE, callData, abi.encode(keccak256(abi.encodePacked(nonce++))));

        vm.prank(operator);
        adapter.bridgeTo(operator, amount, DST_CHAIN_ID);
    }

    function advanceTime(uint32 seconds_) external {
        vm.warp(block.timestamp + bound(uint256(seconds_), 1, 3 days));
    }

    function updateLimits(uint96 rawMaxPerTx, uint96 rawDailyCap) external {
        uint256 maxPerTx_ = bound(uint256(rawMaxPerTx), 0, 1_000_000 ether);
        uint256 dailyCap_ = bound(uint256(rawDailyCap), 0, 10_000_000 ether);
        vm.prank(owner);
        adapter.setBridgeLimits(maxPerTx_, dailyCap_);
    }
}

contract MARKBridgeInvariants is StdInvariant, Test {
    RYLA internal token;
    MARKBridgeAdapter internal adapter;
    MARKBridgeHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");

    uint256 internal constant DST_CHAIN_ID = 902;

    function setUp() public {
        vm.startPrank(owner);
        token = new RYLA(owner);
        token.setMinter(owner, true);

        adapter = new MARKBridgeAdapter(owner, address(token));
        adapter.setOperator(operator, true);
        adapter.setDestination(DST_CHAIN_ID, true);
        adapter.setBridgeLimits(100 ether, 500 ether);
        vm.stopPrank();

        vm.prank(operator);
        IERC20(address(token)).approve(address(adapter), type(uint256).max);

        handler = new MARKBridgeHandler(token, adapter, owner, operator);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MARKBridgeHandler.bridge.selector;
        selectors[1] = MARKBridgeHandler.advanceTime.selector;
        selectors[2] = MARKBridgeHandler.updateLimits.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice bridgedInDailyCapEpoch never exceeds dailyCap within the current epoch.
    function invariant_dailyCapNeverExceeded() public view {
        uint256 dailyCap_ = adapter.dailyCap();
        if (dailyCap_ == 0) return;
        uint64 currentEpoch = uint64(block.timestamp / 1 days);
        if (adapter.dailyCapEpoch() == currentEpoch) {
            assertLe(adapter.bridgedInDailyCapEpoch(), dailyCap_, "daily cap exceeded");
        }
    }

    /// @notice Accumulator is always consistent: never exceeds cap for its stored epoch.
    function invariant_accumulatorConsistentWithCap() public view {
        uint256 dailyCap_ = adapter.dailyCap();
        if (dailyCap_ == 0) return;
        assertLe(adapter.bridgedInDailyCapEpoch(), dailyCap_, "accumulator exceeds cap");
    }

    /// @notice Operator role is never granted to zero address.
    function invariant_operatorRoleNeverZeroAddress() public view {
        assertFalse(adapter.hasRole(adapter.OPERATOR_ROLE(), address(0)), "zero address has operator role");
    }
}
