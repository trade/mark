import {
  bridgeAdapterAbi,
  erc20Abi,
  envAddress,
  envBigInt,
  envTokenAmount,
  markAddresses,
  opSepoliaClients,
  printTokenAmount,
} from '../shared/mark';

const { account, publicClient, walletClient } = opSepoliaClients();

const decimals = await publicClient.readContract({
  address: markAddresses.rylA,
  abi: erc20Abi,
  functionName: 'decimals',
});

const recipient = envAddress('BRIDGE_RECIPIENT', account.address);
const amount = envTokenAmount('BRIDGE_AMOUNT', decimals, '1');
const destinationChainId = envBigInt('DESTINATION_CHAIN_ID', 0n);

if (destinationChainId === 0n) {
  throw new Error('Set DESTINATION_CHAIN_ID to an allowlisted Superchain destination chain id.');
}

const destinationEnabled = await publicClient.readContract({
  address: markAddresses.bridgeAdapter,
  abi: bridgeAdapterAbi,
  functionName: 'destinationEnabled',
  args: [destinationChainId],
});

if (!destinationEnabled) {
  throw new Error(`Destination chain ${destinationChainId} is not enabled on MARKBridgeAdapter.`);
}

const [balance, allowance, maxPerTx, dailyCap] = await Promise.all([
  publicClient.readContract({
    address: markAddresses.rylA,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [account.address],
  }),
  publicClient.readContract({
    address: markAddresses.rylA,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [account.address, markAddresses.bridgeAdapter],
  }),
  publicClient.readContract({
    address: markAddresses.bridgeAdapter,
    abi: bridgeAdapterAbi,
    functionName: 'maxPerTx',
  }),
  publicClient.readContract({
    address: markAddresses.bridgeAdapter,
    abi: bridgeAdapterAbi,
    functionName: 'dailyCap',
  }),
]);

if (balance < amount) {
  throw new Error(`Insufficient RYLA balance. Have ${balance}, need ${amount}.`);
}

if (maxPerTx > 0n && amount > maxPerTx) {
  throw new Error(`Amount exceeds bridge maxPerTx limit of ${maxPerTx}.`);
}

printTokenAmount('Bridge amount', amount, decimals);
console.log(`Operator: ${account.address}`);
console.log(`Recipient: ${recipient}`);
console.log(`Destination chain: ${destinationChainId}`);
console.log(`Daily cap: ${dailyCap === 0n ? 'disabled' : dailyCap.toString()}`);

if (allowance < amount) {
  const { request } = await publicClient.simulateContract({
    account,
    address: markAddresses.rylA,
    abi: erc20Abi,
    functionName: 'approve',
    args: [markAddresses.bridgeAdapter, amount],
  });

  const approveHash = await walletClient.writeContract(request);
  console.log(`Approval submitted: ${approveHash}`);
  await publicClient.waitForTransactionReceipt({ hash: approveHash });
}

const { request } = await publicClient.simulateContract({
  account,
  address: markAddresses.bridgeAdapter,
  abi: bridgeAdapterAbi,
  functionName: 'bridgeTo',
  args: [recipient, amount, destinationChainId],
});

const hash = await walletClient.writeContract(request);
console.log(`Bridge transaction submitted: ${hash}`);

const receipt = await publicClient.waitForTransactionReceipt({ hash });
console.log(`Bridge confirmed in block ${receipt.blockNumber}`);
