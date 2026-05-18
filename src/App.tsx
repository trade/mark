import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const CONTRACTS = [
  {
    name: 'RYLA Credits',
    symbol: 'RYLA',
    description:
      'Superchain-compatible credit token. Mintable and burnable only by the settlement module.',
  },
  {
    name: 'MARKSettlementModule',
    description:
      'Operator-gated settlement boundary. Validates proofs and executes RYLA mint/burn with replay protection.',
  },
  {
    name: 'MARKBridgeAdapter',
    description:
      'Operator-gated bridge adapter routing RYLA cross-chain via SuperchainTokenBridge with rate limits.',
  },
  {
    name: 'AttestedSettlementVerifier',
    description:
      'EIP-712 signature-based verifier for settlement intents. Production bridge step before ZK verifier integration.',
  },
];

const LINKS = [
  { label: 'GitHub', href: 'https://github.com/trade/mark' },
  { label: 'Security Policy', href: 'https://github.com/trade/mark/security/policy' },
  {
    label: 'Report a Vulnerability',
    href: 'https://github.com/trade/mark/security/advisories/new',
  },
];

function App() {
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6 p-6">
      <div className="space-y-1">
        <h1 className="text-2xl font-bold tracking-tight">MARK Protocol</h1>
        <p className="text-sm text-muted-foreground">by Trade</p>
      </div>

      <Card>
        <CardContent className="pt-4">
          <div className="flex items-center gap-2 text-sm">
            <span className="rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800">
              Pre-production
            </span>
            <span className="text-muted-foreground">
              Staging on OP Sepolia. Not yet deployed to mainnet.
            </span>
          </div>
        </CardContent>
      </Card>

      <Separator />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold">Contracts</h2>
        <div className="grid gap-3">
          {CONTRACTS.map(contract => (
            <Card key={contract.name}>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">
                  {contract.name}
                  {contract.symbol && (
                    <span className="ml-2 text-sm font-normal text-muted-foreground">
                      ({contract.symbol})
                    </span>
                  )}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground">{contract.description}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>

      <Separator />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold">Resources</h2>
        <div className="flex flex-wrap gap-3">
          {LINKS.map(link => (
            <a
              key={link.label}
              href={link.href}
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-md border px-3 py-2 text-sm transition-colors hover:bg-muted"
            >
              {link.label}
            </a>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
