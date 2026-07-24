/**
 * WalletConnect v2 — connect from a NORMAL mobile browser (Safari/Chrome),
 * not the wallet's in-app browser. This is the fix for MetaMask-mobile's
 * portrait lock: users browse in a rotatable browser and approve in their
 * wallet app via QR (desktop) or deep-link (mobile).
 *
 * The WC provider is EIP-1193 compatible, so once connected it becomes the
 * app's `activeProvider` and every existing tx/sign path (trade, tournament,
 * chain switch) works unchanged. The heavy SDK is lazy-imported — it only
 * downloads when a user actually chooses WalletConnect.
 *
 * Requires VITE_WALLETCONNECT_PROJECT_ID (a public Reown/WalletConnect
 * project id — safe to ship in the bundle). Without it, WC is disabled and
 * the UI hides the option.
 */
import type { Eip1193Provider } from './walletProviders';
import { SHIBARIUM_CHAIN_ID, RPC_ENDPOINTS } from './eth';

const PROJECT_ID = (import.meta as any).env?.VITE_WALLETCONNECT_PROJECT_ID as string | undefined;
export const isWalletConnectEnabled = () => !!PROJECT_ID;

// EthereumProvider instance (also an EIP-1193 provider). Kept as a singleton.
let wc: any = null;

async function init(): Promise<any> {
  if (wc) return wc;
  const { EthereumProvider } = await import('@walletconnect/ethereum-provider');
  wc = await EthereumProvider.init({
    projectId: PROJECT_ID!,
    // Shibarium is our home chain; offer eth as optional so wallets that
    // don't have Shibarium configured still complete the pairing.
    chains: [SHIBARIUM_CHAIN_ID],
    optionalChains: [1],
    rpcMap: { [SHIBARIUM_CHAIN_ID]: RPC_ENDPOINTS[0] },
    showQrModal: true,   // desktop QR + mobile wallet-list deep-links
    metadata: {
      name: 'Eternity Hub',
      description: 'Shiba Eternity on Shibarium — build decks, battle ranked PvP, run tournaments, and trade cards.',
      url: typeof window !== 'undefined' ? window.location.origin : 'https://eternityhub.vercel.app',
      icons: [(typeof window !== 'undefined' ? window.location.origin : 'https://eternityhub.vercel.app') + '/logo.png'],
    },
  });
  return wc;
}

/** Open the WC modal / deep-link and establish a session. Returns the
 *  EIP-1193 provider once a wallet has approved. */
export async function connectWalletConnect(): Promise<Eip1193Provider> {
  if (!PROJECT_ID) throw new Error('WalletConnect is not configured');
  const p = await init();
  if (!p.session) await p.connect();   // no-op if a session was restored
  return p as Eip1193Provider;
}

/** Re-adopt a persisted session on page load (WC restores it inside init()). */
export async function restoreWalletConnect(): Promise<Eip1193Provider | null> {
  if (!PROJECT_ID) return null;
  try {
    const p = await init();
    return p.session ? (p as Eip1193Provider) : null;
  } catch { return null; }
}

/** End the WC session (called from the app's disconnect). */
export async function disconnectWalletConnect(): Promise<void> {
  try { if (wc?.session) await wc.disconnect(); } catch { /* already gone */ }
}
