import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { supersimL2A, supersimL2B } from '@eth-optimism/viem/chains';
type ChainInfo = {
  name: string;
  id: number;
  role: string;
};

const MARK_FLOW = [
  'Preflight deployment checks',
  'Release orchestration and artifact generation',
  'Staging rehearsal on canary',
  'Mainnet readiness gate on main',
  'Evidence manifest and signature verification',
];

const CHAINS: ChainInfo[] = [
  { name: supersimL2A.name, id: supersimL2A.id, role: 'source lane' },
  { name: supersimL2B.name, id: supersimL2B.id, role: 'destination lane' },
];

const QuickCommand = ({ label, cmd }: { label: string; cmd: string }) => (
  <div className="rounded-md bg-muted p-3">
    <div className="text-xs text-muted-foreground">{label}</div>
    <div className="font-mono text-sm">{cmd}</div>
  </div>
);

function App() {
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4 p-4">
      <Card>
        <CardHeader>
          <CardTitle>MARK Protocol Workspace</CardTitle>
          <CardDescription>
            This app now tracks protocol operations and release flow.
          </CardDescription>
        </CardHeader>
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Superchain Lanes</CardTitle>
            <CardDescription>Local development network topology.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {CHAINS.map(chain => (
              <div key={chain.id} className="rounded-md border p-3">
                <div className="font-semibold">
                  {chain.name} ({chain.id})
                </div>
                <div className="text-sm text-muted-foreground">{chain.role}</div>
              </div>
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Release Flow</CardTitle>
            <CardDescription>Canonical MARK release checkpoints.</CardDescription>
          </CardHeader>
          <CardContent>
            <ol className="list-decimal space-y-2 pl-5 text-sm">
              {MARK_FLOW.map(step => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </CardContent>
        </Card>
      </div>

      <Separator />

      <Card>
        <CardHeader>
          <CardTitle>Quick Commands</CardTitle>
          <CardDescription>Use contract Make targets for protocol operations.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-2">
          <QuickCommand label="Fast checks" cmd="cd contracts && make ci-fast" />
          <QuickCommand label="Release gate" cmd="cd contracts && make release-gate" />
          <QuickCommand label="Staging rehearsal" cmd="cd contracts && make rehearse-production-lock" />
          <QuickCommand label="Evidence manifest" cmd="cd contracts && make generate-evidence-manifest" />
        </CardContent>
      </Card>
    </div>
  );
}

export default App;
