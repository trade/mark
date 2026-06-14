# MARK Protocol Tutorial: End-to-End Transaction Flow

> **Status: Temporarily removed**
>
> This tutorial previously described a transaction flow using outdated contract architecture and function names.
> To avoid confusion, the step-by-step instructions have been removed until a full rewrite is completed.
>
> For current interfaces and method names, see `contracts/src/`.
> For local environment setup, see [Getting Started](../CONTRIBUTING.md#getting-started).

A revised end-to-end tutorial for the current MARK Protocol contracts will be restored in a future update.

The local environment pre-funds some addresses with test tokens. Let's check our balance:

```bash
# In a new terminal, switch to the project directory if needed
cd /path/to/mark

# Check balance of first test account on L2A
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545
```

### 2.2 Approve and Deposit

We need to approve the bridge contract to spend our RYLA tokens, then deposit:

> **🚨 SECURITY WARNING (READ FIRST):**
> The private keys shown below are deterministic local development keys only (for `pnpm dev`/localhost).
> **NEVER** use these keys on any public network (mainnet or testnet), and **NEVER** fund accounts derived from them with real assets.
> Do not import these keys into wallets you use for real funds.

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
cast send $BRIDGE_ADAPTER_L2A "bridgeTo(uint256,address)" 10000000000000000000 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://localhost:8545
```

> **Note**: The private key above is for the first test account in the local environment. The destination address `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` is another test account.

### 2.3 Verify Deposit

Check that the tokens arrived on L2B:

```bash
# Get RYLA token address on L2B
RYLA_L2B=$(cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "l2bToken()(address)" --rpc-url http://localhost:8545)
echo "RYLA on L2B: $RYLA_L2B"

# Check RYLA token balance of the recipient on L2B
cast call $RYLA_L2B "balanceOf(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://localhost:8546
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
CONTEXT_HASH=$(cast abi-encode "(address,address,uint256,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 5 10000000000000000000 | cast keccak -)

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
# Submit mint settlement intent
cast send $SETTLEMENT_MODULE_L2B "settleMint((address,address,uint256,uint256,uint8,bytes32,bytes32),bytes)" \
  "(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,0x70997970C51812dc3A010C7d01b50e0d17dc79C8,5,10000000000000000000,$V,$R,$S)" \
  "0x" \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8546

# Submit burn settlement intent (use this variant for burn flows)
cast send $SETTLEMENT_MODULE_L2B "settleBurn((address,address,uint256,uint256,uint8,bytes32,bytes32),bytes)" \
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
INTENT_ID=$(cast abi-encode "(address,address,uint256,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 5 10000000000000000000 | cast keccak -)
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
# Check L2A RYLA token balance of the recipient (should have +5 RYLA from mint)
cast call $RYLA_L2A "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545

# Check L2B RYLA token balance of the recipient (should have -5 RYLA from burn)
cast call $RYLA_L2B "balanceOf(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://localhost:8546
```

## Step 5: Using the Frontend Dashboard

While we've done everything via command line, you can also monitor transactions through the frontend:

1. Visit http://localhost:5173
2. Connect your wallet (use MetaMask with custom RPCs):
   - L2A: http://localhost:8545
   - L2B: http://localhost:8546
   - Use private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 (⚠️ Local dev key only: never use on real networks)
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

_Last updated: 2026-06-02_
