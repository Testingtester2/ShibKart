/**
 * EIP-6963 wallet provider discovery.
 *
 * Modern injected wallets (MetaMask, Rabby, Coinbase, Phantom, OKX, …)
 * announce themselves via window events instead of fighting over the
 * single `window.ethereum` slot. We listen for those announcements and
 * present a picker so the user can choose which wallet to connect.
 *
 * Falls back to `window.ethereum` if a wallet only supports the legacy
 * injection.
 */

export interface Eip1193Provider {
  request(args: { method: string; params?: unknown[] | object }): Promise<unknown>;
  on?(event: string, handler: (...args: unknown[]) => void): void;
  removeListener?(event: string, handler: (...args: unknown[]) => void): void;
}

export interface ProviderInfo {
  uuid: string;
  name: string;
  icon: string;     // data: URL
  rdns: string;     // reverse-DNS (e.g. io.metamask)
}

export interface ProviderDetail {
  info: ProviderInfo;
  provider: Eip1193Provider;
}

const detected = new Map<string, ProviderDetail>();
const listeners = new Set<() => void>();

if (typeof window !== 'undefined') {
  window.addEventListener('eip6963:announceProvider', (e: Event) => {
    const detail = (e as CustomEvent).detail as ProviderDetail | undefined;
    if (!detail?.info?.uuid) return;
    detected.set(detail.info.uuid, detail);
    listeners.forEach((fn) => fn());
  });

  // Ask wallets to announce. Safe to call multiple times.
  const ping = () => window.dispatchEvent(new Event('eip6963:requestProvider'));
  ping();
  // Some wallets attach late. Re-ping a few times to catch them.
  setTimeout(ping, 100);
  setTimeout(ping, 500);
  setTimeout(ping, 1500);
}

export function getProviders(): ProviderDetail[] {
  const list = Array.from(detected.values());
  // If a wallet only injects via window.ethereum (no EIP-6963), surface it
  // as a synthetic provider so the picker still shows it.
  if (list.length === 0 && typeof window !== 'undefined' && (window as any).ethereum) {
    const eth = (window as any).ethereum as Eip1193Provider & Record<string, unknown>;
    list.push({
      info: {
        uuid: 'legacy-window-ethereum',
        name: detectLegacyName(eth),
        icon: '',
        rdns: 'legacy.window.ethereum',
      },
      provider: eth,
    });
  }
  return list;
}

export function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => {
    listeners.delete(fn);
  };
}

function detectLegacyName(eth: Record<string, unknown>): string {
  if (eth.isMetaMask) return 'MetaMask';
  if (eth.isCoinbaseWallet) return 'Coinbase Wallet';
  if (eth.isRabby) return 'Rabby';
  if (eth.isBraveWallet) return 'Brave Wallet';
  if (eth.isTokenPocket) return 'TokenPocket';
  if (eth.isTrust) return 'Trust Wallet';
  if (eth.isBitKeep || eth.isBitget) return 'Bitget Wallet';
  if (eth.isOkxWallet || eth.isOKExWallet) return 'OKX Wallet';
  if (eth.isPhantom) return 'Phantom';
  return 'Browser Wallet';
}
