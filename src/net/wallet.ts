// Wallet login via WalletConnect (same lib as WutCardBoshi). Safe no-op until
// VITE_WALLETCONNECT_PROJECT_ID is set — the game runs fine without a wallet.
const PROJECT_ID = (import.meta as any).env?.VITE_WALLETCONNECT_PROJECT_ID as string | undefined;
const CHAIN_ID = Number((import.meta as any).env?.VITE_CHAIN_ID ?? 1);

let provider: any = null;
let address: string | null = null;

export function walletConfigured() { return !!PROJECT_ID; }
export function walletAddress() { return address; }

export async function connectWallet(): Promise<string | null> {
  if (!PROJECT_ID) { console.info("[ShibKart] set VITE_WALLETCONNECT_PROJECT_ID to enable wallet login"); return null; }
  try {
    const mod: any = await import("@walletconnect/ethereum-provider");
    const EthereumProvider = mod.EthereumProvider ?? mod.default;
    provider = await EthereumProvider.init({ projectId: PROJECT_ID, chains: [CHAIN_ID], showQrModal: true });
    await provider.enable();
    address = provider.accounts?.[0] ?? null;
    return address;
  } catch (e) { console.warn("[ShibKart] wallet connect failed", e); return null; }
}
export function getProvider() { return provider; }
