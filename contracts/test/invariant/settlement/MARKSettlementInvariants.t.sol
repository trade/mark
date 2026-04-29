// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {SettlementErrors} from "../../../src/errors/SettlementErrors.sol";

contract MARKSettlementHandler is Test {
    RYLA public immutable token;
    MARKSettlementModule public immutable module;
    address public immutable operator;

    address[] internal users;

    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public successfulMintCount;
    uint256 public successfulBurnCount;
    uint256 internal nonce;
    bytes32 internal lastMintIntentId;
    address internal lastMintRecipient;
    uint256 internal lastMintAmount;

    constructor(RYLA _token, MARKSettlementModule _module, address _operator) {
        token = _token;
        module = _module;
        operator = _operator;

        users.push(makeAddr("userA"));
        users.push(makeAddr("userB"));
        users.push(makeAddr("userC"));
    }

    function settleMint(uint96 rawAmount, uint8 userSeed) external {
        uint256 amount = _clamp(uint256(rawAmount), 1, 1_000_000 ether);
        address recipient = _user(userSeed);
        bytes32 intentId = keccak256(abi.encodePacked("mint", nonce++));

        vm.prank(operator);
        module.settleMint(recipient, amount, intentId, bytes(""));

        totalMinted += amount;
        successfulMintCount += 1;
        lastMintIntentId = intentId;
        lastMintRecipient = recipient;
        lastMintAmount = amount;
    }

    function settleBurn(uint96 rawAmount, uint8 userSeed) external {
        address account = _user(userSeed);
        uint256 balance = token.balanceOf(account);
        if (balance == 0) return;

        uint256 amount = _clamp(uint256(rawAmount), 1, balance);
        bytes32 intentId = keccak256(abi.encodePacked("burn", nonce++));

        vm.prank(account);
        token.approve(address(module), amount);

        vm.prank(operator);
        module.settleBurn(account, amount, intentId, bytes(""));

        totalBurned += amount;
        successfulBurnCount += 1;
    }

    function replayLastMintIntent() external {
        if (lastMintIntentId == bytes32(0)) return;

        vm.prank(operator);
        vm.expectRevert(SettlementErrors.IntentAlreadyConsumed.selector);
        module.settleMint(lastMintRecipient, lastMintAmount, lastMintIntentId, bytes(""));
    }

    function unauthorizedSettleMint(uint96 rawAmount, uint8 userSeed) external {
        uint256 amount = _clamp(uint256(rawAmount), 1, 1_000_000 ether);
        address recipient = _user(userSeed);
        bytes32 intentId = keccak256(abi.encodePacked("unauthMint", nonce++));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), module.OPERATOR_ROLE()
            )
        );
        module.settleMint(recipient, amount, intentId, bytes(""));
    }

    function unauthorizedTokenMint(uint96 rawAmount, uint8 userSeed) external {
        uint256 amount = _clamp(uint256(rawAmount), 1, 1_000_000 ether);
        address recipient = _user(userSeed);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), token.MINTER_ROLE()
            )
        );
        token.mint(recipient, amount);
    }

    function unauthorizedTokenBurn(uint96 rawAmount) external {
        uint256 amount = _clamp(uint256(rawAmount), 1, 1_000_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), token.BURNER_ROLE()
            )
        );
        token.burn(amount);
    }

    function trackedUserBalanceSum() external view returns (uint256 sum) {
        uint256 length = users.length;
        for (uint256 i = 0; i < length; ++i) {
            sum += token.balanceOf(users[i]);
        }
    }

    function _user(uint8 seed) internal view returns (address) {
        return users[uint256(seed) % users.length];
    }

    function _clamp(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        unchecked {
            return min + (x % (max - min + 1));
        }
    }
}

contract MARKSettlementInvariants is StdInvariant, Test {
    RYLA internal token;
    MARKSettlementModule internal module;
    MARKSettlementHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");

    function setUp() public {
        vm.prank(owner);
        token = new RYLA(owner);

        vm.prank(owner);
        module = new MARKSettlementModule(owner, address(token));

        vm.startPrank(owner);
        token.setMinter(address(module), true);
        token.setBurner(address(module), true);
        module.setOperator(operator, true);
        vm.stopPrank();

        handler = new MARKSettlementHandler(token, module, operator);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = MARKSettlementHandler.settleMint.selector;
        selectors[1] = MARKSettlementHandler.settleBurn.selector;
        selectors[2] = MARKSettlementHandler.unauthorizedSettleMint.selector;
        selectors[3] = MARKSettlementHandler.unauthorizedTokenMint.selector;
        selectors[4] = MARKSettlementHandler.unauthorizedTokenBurn.selector;
        selectors[5] = MARKSettlementHandler.replayLastMintIntent.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalSupplyMatchesNetSettlements() public view {
        assertEq(token.totalSupply(), handler.totalMinted() - handler.totalBurned(), "supply != minted-burned");
    }

    function invariant_totalSupplyMatchesTrackedBalances() public view {
        assertEq(token.totalSupply(), handler.trackedUserBalanceSum(), "supply != tracked balances");
    }

    function invariant_settlementCountersStayConsistent() public view {
        assertEq(module.totalSettledMint(), handler.totalMinted(), "module mint total mismatch");
        assertEq(module.totalSettledBurn(), handler.totalBurned(), "module burn total mismatch");
        assertGe(module.totalSettledMint(), module.totalSettledBurn(), "burn exceeds mint");
    }

    function invariant_moduleRemainsExclusiveIssuer() public view {
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(module)), "module missing minter role");
        assertTrue(token.hasRole(token.BURNER_ROLE(), address(module)), "module missing burner role");
        assertFalse(token.hasRole(token.MINTER_ROLE(), address(handler)), "handler unexpectedly minter");
        assertFalse(token.hasRole(token.BURNER_ROLE(), address(handler)), "handler unexpectedly burner");
    }

    function invariant_moduleDoesNotAccumulateTokens() public view {
        assertEq(token.balanceOf(address(module)), 0, "module balance leak");
    }
}
