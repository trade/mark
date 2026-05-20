import {
  erc20Abi,
  envAddress,
  envHex,
  envTokenAmount,
  markAddresses,
  opSepoliaClients,
  printTokenAmount,
  settlementModuleAbi,
} from '../shared/mark';

const { account, publicClient, walletClient } = opSepoliaClients();

const decimals = await publicClient.readContract({
  address: markAddresses.rylA,
  abi: erc20Abi,
  functionName: 'decimals',
});

const recipient = envAddress('SETTLEMENT_RECIPIENT', account.address);
const amount = envTokenAmount('SETTLEMENT_AMOUNT', decimals, '1');
const intentId = envHex('SETTLEMENT_INTENT_ID');
const proof = envHex('SETTLEMENT_PROOF', '0x');

const alreadyConsumed = await publicClient.readContract({
  address: markAddresses.settlementModule,
  abi: settlementModuleAbi,
  functionName: 'consumedIntents',
  args: [intentId],
});

if (alreadyConsumed) {
  throw new Error(`Intent ${intentId} has already been consumed.`);
}

printTokenAmount('Submitting settlement mint amount', amount, decimals);
console.log(`Operator: ${account.address}`);
console.log(`Recipient: ${recipient}`);

const { request } = await publicClient.simulateContract({
  account,
  address: markAddresses.settlementModule,
  abi: settlementModuleAbi,
  functionName: 'settleMint',
  args: [recipient, amount, intentId, proof],
});

const hash = await walletClient.writeContract(request);
console.log(`Settlement transaction submitted: ${hash}`);

const receipt = await publicClient.waitForTransactionReceipt({ hash });
console.log(`Settlement confirmed in block ${receipt.blockNumber}`);

const totalSettledMint = await publicClient.readContract({
  address: markAddresses.settlementModule,
  abi: settlementModuleAbi,
  functionName: 'totalSettledMint',
});

printTokenAmount('Protocol total settled mint', totalSettledMint, decimals);
