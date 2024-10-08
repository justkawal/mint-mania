import { defaultWagmiConfig } from "@web3modal/wagmi/react/config";

import { cookieStorage, createStorage, http } from "wagmi";
import { baseSepolia } from "wagmi/chains";
import { ENTRYPOINT_ADDRESS_V06 } from "permissionless";
import { createPimlicoPaymasterClient } from "permissionless/clients/pimlico";

// Get projectId from https://cloud.walletconnect.com
export const projectId = process.env.NEXT_PUBLIC_PROJECT_ID;

if (!projectId) throw new Error("Project ID is not defined");

export const metadata = {
  name: "Mint Mania",
  description: "Trade tokens along the bonding curve | Fair and simple launch",
  url: "http://localhost:3000",
  icons: [""]
};

// Create wagmiConfig
const chains = [baseSepolia] as const;
export const config = defaultWagmiConfig({
  chains,
  projectId,
  metadata,
  auth: {
    email: true,
    socials: ["google", "github", "discord"]
  },
  coinbasePreference: "smartWalletOnly",
  transports: {
    [baseSepolia.id]: http(process.env.NEXT_PUBLIC_RPC_ETH_HTTP)
  },
  ssr: true,
  storage: createStorage({
    storage: cookieStorage
  })
});