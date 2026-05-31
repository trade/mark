# MARK Protocol Tutorial: End-to-End Transaction Flow

This tutorial walks you through a complete transaction flow on the MARK Protocol using the local development environment.

## Prerequisites

Before starting, ensure you have:
1. Completed the [Getting Started](./CONTRIBUTING.md#getting-started) guide
2. Running local development environment: `pnpm dev` (in one terminal)
3. The MARK dashboard accessible at http://localhost:5173

## Overview

This tutorial demonstrates:
1. Depositing RYLA tokens into the bridge contract
2. Creating a settlement intent
3. Generating and verifying a proof
4. Executing settlement on the destination chain

We'll use the local Superchain (L1 + 2 L2 chains) started by `pnpm dev`.

## Step 1: Understanding the Local Network

When you run `pnpm dev`, the following components are started:

- **L1 Chain**: Ethereum-like base layer (Superchain L1)
- **L2A Chain**: Optimism L2 where deposits occur
- **L2B Chain**: Optimism L2 where settlements happen
- **Frontend**: Vite dev server at http://localhost:5173
- **Contracts**: Automatically deployed to L2A and L2B

## Step 2: Deposit RYLA Tokens via Bridge

### 2.1 Get Test Tokens

The local environment pre-funds some addresses with test tokens. Let's check our balance:

```bash
# In a new terminal, switch to the project directory if needed
cd /path/to/mark

# Check balance of first test account on L2A
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545
```

### 2.2 Approve and Deposit

We need to approve the bridge contract to spend our RYLA tokens, then deposit:

```bash
# Get the RYLA token address on L2A (from deployment)
RYLA_L2A=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "token()(address)" --rpc-url http://localhost:8545)
echo "RYLA on L2A: $RYLA_L2A"

# Get the BridgeAdapter address on L2A
BRIDGE_ADAPTER_L2A=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "bridgeAdapter()(address)" --rpc-url http://localhost:8545)
echo "Bridge Adapter on L2A: $BRIDGE_ADAPTER_L2A"

# Approve the bridge to spend 100 RYLA (assuming 18 decimals)
cast send $RYLA_L2A "approve(address,uint256)" $BRIDGE_ADAPTER_L2A 100000000000000000000 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://localhost:8545

# Deposit 10 RYLA from L2A to L2B via the bridge
cast send $BRIDGE_ADAPTER_L2A "deposit(uint256,address)" 10000000000000000000 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://localhost:8545
```

> **Note**: The private key above is for the first test account in the local environment. The destination address `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` is another test account.

### 2.3 Verify Deposit

Check that the tokens arrived on L2B:

```bash
# Get RYLA token address on L2B
RYLA_L2B=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "l2bToken()(address)" --rpc-url http://localhost:8545)
echo "RYLA on L2B: $RYLA_L2B"

# Check balance on L2B
cast balance $RYLA_L2B --rpc-url http://localhost:8546  # L2B RPC port
```

## Step 3: Create Settlement Intent

Now that we have tokens on L2B, we can create a settlement intent to move them back to L2A (or to another address).

### 3.1 Prepare Settlement Data

For this tutorial, we'll create a simple intent to transfer 5 RYLA back to our original address:

```bash
# Settlement Module address on L2B
SETTLEMENT_MODULE_L2B=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "settlementModule()(address)" --rpc-url http://localhost:8546)
echo "Settlement Module on L2B: $SETTLEMENT_MODULE_L2B"

# Create intent hash (simplified - in practice this would involve zk proofs)
# For demonstration, we'll use the AttestedSettlementVerifier which uses signatures

# Get the Attested Settler Verifier
ATTESTED_VERIFIER=$(cast call $SETTLEMENT_MODULE_L2B "verifier()(address)" --rpc-url http://localhost:8546)
echo "Attested Verifier: $ATTESTED_VERIFIER"
```

### 3.2 Generate Signature (Attested Proof)

For the attested verifier, we need to create a signature. In a real implementation, this would come from your off-chain signing service. Here we'll simulate it:

```bash
# Prepare the message to sign (simplified format)
# In practice: abi.encode(uint256 deadline, bytes32 contextHash, uint8 v, bytes32 r, bytes32 s)
DEADLINE=$(( $(date +%s) + 3600 ))  # 1 hour from now
CONTEXT_HASH=$(cast keccak "abi.encode((address,address,uint256,uint256),0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,5,10000000000000000000)")

# Sign with our private key (this is just for demo - never expose keys like this in production!)
SIGNATURE=$(cast sign --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 $CONTEXT_HASH)
echo "Signature: $SIGNATURE"

# Extract v, r, s components
V=$(cast to-hex $(cast to-int ${SIGNATURE:130:2}))
R=${SIGNATURE:2:64}
S=${SIGNATURE:66:64}
```

### 3.3 Submit Settlement Intent

Now submit the intent to the settlement module:

```bash
# Submit intent with attested proof
cast send $SETTLEMENT_MODULE_L2B "settleWithAttestedProof((address,address,uint256,uint256,uint8,bytes32,bytes32),bytes)" \
  "(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,5,10000000000000000000,$V,$R,$S)" \
  "0x" \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8546
```

## Step 4: Verify and Execute Settlement

### 4.1 Check Intent Status

Verify the intent was processed:

```bash
# Check if intent was recorded (simplified)
INTENT_ID=$(cast keccak "abi.encode((address,address,uint256,uint256),0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,5,10000000000000000000)")
cast call $SETTLEMENT_MODULE_L2B "intents(bytes32)(bool)" $INTENT_ID --rpc-url http://localhost:8546
```

### 4.2 Execute Settlement on L2A

Now execute the settlement on L2A to mint/burn tokens accordingly:

```bash
# Settlement Module on L2A
SETTLEMENT_MODULE_L2A=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "settlementModule()(address)" --rpc-url http://localhost:8545)
echo "Settlement Module on L2A: $SETTLEMENT_MODULE_L2A"

# Execute settlement (this would typically be called by a relayer or keeper)
cast send $SETTLEMENT_MODULE_L2A "executeSettlement(bytes32)" $INTENT_ID \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8545
```

### 4.3 Verify Final Balances

Check that tokens moved as expected:

```bash
# Check L2A balance (should have +5 RYLA from mint)
cast balance $RYLA_L2A --rpc-url http://localhost:8545

# Check L2B balance (should have -5 RYLA from burn)
cast balance $RYLA_L2B --rpc-url http://localhost:8546
```

## Step 5: Using the Frontend Dashboard

While we've done everything via command line, you can also monitor transactions through the frontend:

1. Visit http://localhost:5173
2. Connect your wallet (use MetaMask with custom RPCs):
   - L2A: http://localhost:8545
   - L2B: http://localhost:8546
   - Use private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
3. Navigate to the "Bridge" or "Settlement" sections to see transaction history

## Troubleshooting

### Common Issues

1. **"Transaction underpriced"**: Increase the gas price in your cast send command
2. **"Nonce too low"**: Wait a moment and retry, or increment the nonce manually
3. **"Contract reverts"**: Check the revert reason by adding `--verbose` to cast commands
4. **Port conflicts**: Ensure no other services are running on ports 8545, 8546, 5173

### Debugging Tips

- Use `cast tx <tx-hash>` to see transaction details
- Check contract events with `cast logs --address <contract> --from-block <num>`
- View Superchain logs: `tail -f supersim-logs/*.log`

## Next Steps

Once you've completed this tutorial:
1. Experiment with different amounts and addresses
2. Try using the Groth16 verifier instead of AttestedSettlementVerifier
3. Explore the circuit code in `circuits/` to understand how zero-knowledge proofs work
4. Look at the frontend source in `src/` to see how the dashboard interacts with contracts

## Summary

You've successfully:
- Deposited RYLA tokens from L2A to L2B via the bridge
- Created a settlement intent with an attested proof
- Executed the settlement on L2A
- Verified token movements across chains

This demonstrates the core MARK Protocol flow: private, verifiable transfers between chains using zero-knowledge technology and Superchain infrastructure.

---
*Last updated: $(date)*