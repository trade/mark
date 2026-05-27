import { createConfig, http, WagmiProvider } from "wagmi";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import { optimism, optimismSepolia } from "viem/chains";

const queryClient = new QueryClient();

const config = createConfig({
  chains: [optimism, optimismSepolia],
  transports: {
    [optimism.id]: http(),
    [optimismSepolia.id]: http(),
  },
});

export const Providers = ({ children }: { children: React.ReactNode }) => {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
};
