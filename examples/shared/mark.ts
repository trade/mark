import { createConfig, http } from 'wagmi';
import { optimismSepolia } from 'wagmi/chains';
import {
  createPublicClient,
  createWalletClient,
  formatUnits,
  http as viemHttp,
  parseUnits,
} from 'viem';
import type { Address, Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

export const OP_SEPOLIA_CHAIN_ID = 11155420;

export const markAddresses = {
  rylA: '0xa27360e124B94449249D1E919d3363BfF1c10c02',
  settlementModule: '0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59',
  bridgeAdapter: '0x5F3823739E510981A821aC5E99235e36f65cBc71',
  attestedSettlementVerifier: '0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260',
  markPoolVerifier: '0xEE8aE1d7FE8193411AAfC8eC6a53D7897BB3581a',
  markPool: '0xD73594f95Cd154a79252d0187C0704D744bFFCAA',
  rylACreditLedger: '0x68F3D477FBb82b5cF835F31015532275E5d6fc5B',
  withdrawAdapter: '0xC5fD2Aef37606D34d1DC978AEbB8521980E72328',
} as const satisfies Record<string, Address>;

export const erc20Abi = [
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'decimals',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
] as const;

export const settlementModuleAbi = [
  {
    type: 'function',
    name: 'settleMint',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'intentId', type: 'bytes32' },
      { name: 'proof', type: 'bytes' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'consumedIntents',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'totalSettledMint',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const bridgeAdapterAbi = [
  {
    type: 'function',
    name: 'bridgeTo',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'recipient', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'destinationChainId', type: 'uint256' },
    ],
    outputs: [{ name: 'messageHash', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'destinationEnabled',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'maxPerTx',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'dailyCap',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const markPoolAbi = [
  {
    type: 'function',
    name: 'getMerkleRoot',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'protocolEpoch',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'transact',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'merkleRoot', type: 'bytes32' },
      { name: 'nullifiers', type: 'bytes32[2]' },
      { name: 'outCommitments', type: 'bytes32[2]' },
      { name: 'fee', type: 'uint256' },
      { name: 'relayer', type: 'address' },
      { name: 'a', type: 'uint256[2]' },
      { name: 'bSnarkjs', type: 'uint256[2][2]' },
      { name: 'c', type: 'uint256[2]' },
    ],
    outputs: [],
  },
] as const;

export const wagmiConfig = createConfig({
  chains: [optimismSepolia],
  transports: {
    [optimismSepolia.id]: http(env('OP_SEPOLIA_RPC_URL', false)),
  },
});

export function env(name: string, required = true): string {
  const value = process.env[name];
  if (!value && required) {
    throw new Error(`Missing ${name}. Add it to your environment before running this example.`);
  }
  return value ?? '';
}

export function envAddress(name: string, fallback?: Address): Address {
  const value = env(name, !fallback) || fallback;
  if (!value?.startsWith('0x')) {
    throw new Error(`${name} must be a 0x-prefixed address.`);
  }
  return value as Address;
}

export function envHex(name: string, fallback?: Hex): Hex {
  const value = env(name, !fallback) || fallback;
  if (!value?.startsWith('0x')) {
    throw new Error(`${name} must be 0x-prefixed hex.`);
  }
  return value as Hex;
}

export function envBigInt(name: string, fallback: bigint): bigint {
  const value = env(name, false);
  return value ? BigInt(value) : fallback;
}

export function envTokenAmount(name: string, decimals: number, fallback = '1'): bigint {
  return parseUnits(env(name, false) || fallback, decimals);
}

export function opSepoliaClients() {
  const rpcUrl = env('OP_SEPOLIA_RPC_URL');
  const account = privateKeyToAccount(envHex('PRIVATE_KEY'));
  const transport = viemHttp(rpcUrl);

  return {
    account,
    publicClient: createPublicClient({
      chain: optimismSepolia,
      transport,
    }),
    walletClient: createWalletClient({
      account,
      chain: optimismSepolia,
      transport,
    }),
  };
}

export function opSepoliaPublicClient() {
  return createPublicClient({
    chain: optimismSepolia,
    transport: viemHttp(env('OP_SEPOLIA_RPC_URL')),
  });
}

export function printTokenAmount(label: string, amount: bigint, decimals: number) {
  console.log(`${label}: ${formatUnits(amount, decimals)} RYLA`);
}
