// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {RYLA} from "../../../src/token/RYLA.sol";
import {MARKBridgeAdapter} from "../../../src/bridge/MARKBridgeAdapter.sol";
import {MARKSettlementModule} from "../../../src/settlement/MARKSettlementModule.sol";
import {AttestedSettlementVerifier} from "../../../src/settlement/verifier/AttestedSettlementVerifier.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice Bridge E2E test: mint RYLA via attested settlement, then bridge.
/// @dev Requires:
///      - PRIVATE_KEY: operator key (must have OPERATOR_ROLE on module)
///      - ATTESTER_KEY: attester key (must have ATTESTER_ROLE on verifier)
///
///      Setup (one-time, run as admin):
///        cast send $MODULE "setOperator(address,bool)" $OPERATOR true --private-key $ADMIN_KEY
///        cast send $VERIFIER "setAttester(address,bool)" $ATTESTER true --private-key $ADMIN_KEY
///
///      Run:
///        PRIVATE_KEY=<op_key> ATTESTER_KEY=<att_key> \
///        forge script script/ops/bridge/BridgeE2E.s.sol \
///          --rpc-url https://sepolia.optimism.io --broadcast -vv
contract BridgeE2E is Script {
    address constant RYLA_ADDR     = 0xa27360e124B94449249D1E919d3363BfF1c10c02;
    address constant MODULE_ADDR   = 0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59;
    address constant BRIDGE_ADDR   = 0x5F3823739E510981A821aC5E99235e36f65cBc71;
    address constant VERIFIER_ADDR = 0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260;

    uint256 constant DST_CHAIN_ID  = 11155420;
    uint256 constant BRIDGE_AMOUNT = 1e18; // 1 RYLA

    function run() external {
        uint256 operatorKey = vm.envUint("PRIVATE_KEY");
        uint256 attesterKey = vm.envOr("ATTESTER_KEY", operatorKey);
        address operator    = vm.addr(operatorKey);

        RYLA ryla = RYLA(RYLA_ADDR);
        MARKSettlementModule module = MARKSettlementModule(MODULE_ADDR);
        MARKBridgeAdapter bridge = MARKBridgeAdapter(BRIDGE_ADDR);
        AttestedSettlementVerifier verifier = AttestedSettlementVerifier(VERIFIER_ADDR);

        console.log("Operator:", operator);
        console.log("RYLA balance before:", ryla.balanceOf(operator));

        // Preflight
        require(module.hasRole(module.OPERATOR_ROLE(), operator), "operator missing OPERATOR_ROLE");
        require(verifier.hasRole(verifier.ATTESTER_ROLE(), vm.addr(attesterKey)), "attester missing ATTESTER_ROLE");
        require(bridge.destinationEnabled(DST_CHAIN_ID), "destination not enabled");

        // Build EIP-712 attestation matching AttestedSettlementVerifier._settlementDigest
        bytes32 intentId    = keccak256(abi.encodePacked("bridge-e2e", block.timestamp, operator));
        uint256 deadline    = block.timestamp + 1 hours;
        bytes32 contextHash = bytes32(0); // opaque attester-controlled value

        bytes32 structHash = keccak256(abi.encode(
            verifier.SETTLEMENT_ATTESTATION_TYPEHASH(),
            intentId,
            VERIFIER_ADDR,   // address(this) in the verifier
            MODULE_ADDR,
            operator,
            BRIDGE_AMOUNT,
            true,            // isMint
            contextHash,
            deadline
        ));

        // Reconstruct domain separator from eip712Domain()
        (,string memory name, string memory version, uint256 chainId, address verifyingContract,,) = verifier.eip712Domain();
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract
        ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSep, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, digest);

        // Encode proof: abi.encode(deadline, contextHash, v, r, s)
        bytes memory proof = abi.encode(deadline, contextHash, v, r, s);

        vm.startBroadcast(operatorKey);

        // 1. Mint RYLA via attested settleMint
        module.settleMint(operator, BRIDGE_AMOUNT, intentId, proof);
        console.log("Minted 1 RYLA. Balance:", ryla.balanceOf(operator));

        // 2. Approve and bridge
        ryla.approve(BRIDGE_ADDR, BRIDGE_AMOUNT);
        bridge.bridgeTo(operator, BRIDGE_AMOUNT, DST_CHAIN_ID);
        console.log("Bridged 1 RYLA to chain", DST_CHAIN_ID);
        console.log("Balance after:", ryla.balanceOf(operator));
        console.log("TotalSupply after:", ryla.totalSupply());

        vm.stopBroadcast();
        console.log("Bridge E2E PASSED");
    }
}
