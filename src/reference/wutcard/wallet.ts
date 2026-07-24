import { useCallback, useEffect, useState } from 'react';
import { SHIBARIUM_CHAIN_ID_HEX, RPC_ENDPOINTS } from './eth';
import { resolveShibName, lookupShibName } from './sns';
import { Eip1193Provider, ProviderDetail, getProviders, subscribe } from './walletProviders';
import { isWalletConnectEnabled } from './walletConnect';

const WC_RDNS = 'walletconnect';

declare global {
  interface Window {
    ethereum?: Eip1193Provider & Record<string, unknown>;
  }
}

const STORAGE_ADDR = 'wutcardboshi.wallet';
const STORAGE_RDNS = 'wutcardboshi.wallet.rdns';

export interface WalletState {
  address: string | null;
  chainId: number | null;
  shibName: string | null;
}

let activeProvider: Eip1193Provider | null = null;

export function setActiveProvider(p: Eip1193Provider | null) {
  activeProvider = p;
}
export function getActiveProvider(): Eip1193Provider | null {
  return activeProvider;
}
/** The connected wallet address (lowercased), for modules that need identity
 *  without the React hook (e.g. authenticated service calls). */
export function getWalletAddress(): string | null {
  return walletState.address;
}

// ── Singleton wallet state ─────────────────────────────────────────────────
// useWallet() is called from multiple components (App.tsx, WalletButton).
// Each call would otherwise own its own React state, so a successful
// connect in WalletButton wouldn't update the address that App.tsx is
// passing to ChatPanel / TradePanel / etc. — and the user would see a
// "connect a wallet" prompt even though the header chip is connected.
// Lift the wallet state into a module-level singleton with pub/sub so
// every useWallet() hook subscribes to and renders from the same value.
let walletState: WalletState = { address: null, chainId: null, shibName: null };
const walletListeners = new Set<(s: WalletState) => void>();
function setWalletState(next: WalletState) {
  walletState = next;
  walletListeners.forEach((fn) => fn(next));
}

export function useWallet() {
  const [state, setLocalState] = useState<WalletState>(walletState);
  useEffect(() => {
    walletListeners.add(setLocalState);
    return () => {
      walletListeners.delete(setLocalState);
    };
  }, []);

  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [providers, setProviders] = useState<ProviderDetail[]>(() => getProviders());

  useEffect(() => {
    const unsub = subscribe(() => setProviders(getProviders()));
    return unsub;
  }, []);

  const refreshFor = useCallback(async (provider: Eip1193Provider) => {
    try {
      const accounts = (await provider.request({ method: 'eth_accounts' })) as string[];
      const chainId = (await provider.request({ method: 'eth_chainId' })) as string;
      const addr = accounts[0]?.toLowerCase() ?? null;
      // Push the address part of the state first so any UI gated on
      // walletAddress (chat input, trade approval, etc.) updates
      // immediately — don't make it wait for the shibName lookup, which
      // can take seconds or fail entirely in mobile wallet browsers.
      setWalletState({
        address: addr,
        chainId: chainId ? parseInt(chainId, 16) : null,
        shibName: walletState.shibName && walletState.address === addr ? walletState.shibName : null,
      });
      if (addr) {
        localStorage.setItem(STORAGE_ADDR, addr);
        // Now resolve the shibName in the background and patch state.
        lookupShibName(addr)
          .then((name) => {
            if (walletState.address === addr) {
              setWalletState({ ...walletState, shibName: name });
            }
          })
          .catch(() => {});
      }
    } catch {
      /* ignore */
    }
  }, []);

  // shared event wiring for whichever provider becomes active
  const wireProviderEvents = useCallback((provider: Eip1193Provider) => {
    const onAccounts = (...args: unknown[]) => {
      const accs = (args[0] as string[]) ?? [];
      if (!accs.length) { localStorage.removeItem(STORAGE_ADDR); setWalletState({ address: null, chainId: null, shibName: null }); }
      else refreshFor(provider);
    };
    provider.on?.('accountsChanged', onAccounts);
    provider.on?.('chainChanged', () => refreshFor(provider));
    provider.on?.('disconnect', () => {
      localStorage.removeItem(STORAGE_ADDR); localStorage.removeItem(STORAGE_RDNS);
      setActiveProvider(null); setWalletState({ address: null, chainId: null, shibName: null });
    });
  }, [refreshFor]);

  // Auto-reconnect using last-chosen provider.
  useEffect(() => {
    const wantedRdns = localStorage.getItem(STORAGE_RDNS);
    const prev = localStorage.getItem(STORAGE_ADDR);
    if (!prev) return;
    if (wantedRdns === WC_RDNS) return;   // WalletConnect restore is handled below
    const match = providers.find((p) => p.info.rdns === wantedRdns) ?? providers[0];
    if (!match) return;
    setActiveProvider(match.provider);
    refreshFor(match.provider);

    const onAccounts = (...args: unknown[]) => {
      const accs = (args[0] as string[]) ?? [];
      if (!accs.length) {
        localStorage.removeItem(STORAGE_ADDR);
        setWalletState({ address: null, chainId: null, shibName: null });
      } else {
        refreshFor(match.provider);
      }
    };
    const onChain = () => refreshFor(match.provider);
    match.provider.on?.('accountsChanged', onAccounts);
    match.provider.on?.('chainChanged', onChain);
    return () => {
      match.provider.removeListener?.('accountsChanged', onAccounts);
      match.provider.removeListener?.('chainChanged', onChain);
    };
  }, [providers, refreshFor]);

  // Restore a persisted WalletConnect session on load (its own path — WC
  // isn't an injected provider, so it never appears in `providers`).
  useEffect(() => {
    if (localStorage.getItem(STORAGE_RDNS) !== WC_RDNS || !localStorage.getItem(STORAGE_ADDR)) return;
    let alive = true;
    void import('./walletConnect')
      .then(({ restoreWalletConnect }) => restoreWalletConnect())
      .then((provider) => {
        if (!alive || !provider) return;
        setActiveProvider(provider);
        wireProviderEvents(provider);
        refreshFor(provider);
      })
      .catch(() => {});
    return () => { alive = false; };
  }, [refreshFor, wireProviderEvents]);

  const connectWith = useCallback(
    async (detail: ProviderDetail) => {
      setError(null);
      setConnecting(true);
      try {
        // 1) Authorise — this is the only step that should hard-fail the
        //    connect. Mobile wallet browsers ALWAYS support this if the
        //    user actually has an account.
        await detail.provider.request({ method: 'eth_requestAccounts' });
        setActiveProvider(detail.provider);
        localStorage.setItem(STORAGE_RDNS, detail.info.rdns);

        // 2) Try to nudge onto Shibarium, but don't let a chain-switch
        //    error abort the whole connect — many in-wallet browsers
        //    throw quirky RPC errors here (already on the chain, native
        //    add-chain dialog refused, etc.). Surface as a hint instead.
        try {
          await ensureShibariumOn(detail.provider);
        } catch (chainErr: unknown) {
          const c = chainErr as { code?: number; message?: string };
          if (c?.code !== 4001) {
            // eslint-disable-next-line no-console
            console.warn('[wallet] chain switch failed', chainErr);
            setError(
              `Couldn't switch ${detail.info.name} to Shibarium automatically. ` +
                'Open the wallet, pick Shibarium (chain id 109), then come back to this tab.',
            );
          }
        }

        await refreshFor(detail.provider);
      } catch (e: unknown) {
        const err = e as { code?: number; message?: string };
        const msg = err?.message ?? String(e);
        // Hide the generic "user rejected" copy; show everything else.
        const isPlainReject =
          err?.code === 4001 && /user (rejected|denied)/i.test(msg);
        if (!isPlainReject) {
          setError(prettifyWalletError(detail.info.name, msg));
        }
        // eslint-disable-next-line no-console
        console.error('[wallet]', detail.info.name, e);
      } finally {
        setConnecting(false);
      }
    },
    [refreshFor],
  );

  // Connect via WalletConnect — for users in a normal mobile browser (or
  // desktop, by QR). Opens the WC modal / deep-links to the wallet app, then
  // adopts the resulting EIP-1193 provider like any other.
  const connectWalletConnect = useCallback(async () => {
    setError(null);
    setConnecting(true);
    try {
      const { connectWalletConnect } = await import('./walletConnect');
      const provider = await connectWalletConnect();
      setActiveProvider(provider);
      localStorage.setItem(STORAGE_RDNS, WC_RDNS);
      try { await ensureShibariumOn(provider); } catch { /* WC session already targets 109 */ }
      wireProviderEvents(provider);
      await refreshFor(provider);
    } catch (e: unknown) {
      const err = e as { code?: number; message?: string };
      if (err?.code !== 4001) setError(err?.message ?? String(e));
      // eslint-disable-next-line no-console
      console.error('[wallet] walletconnect', e);
    } finally {
      setConnecting(false);
    }
  }, [refreshFor, wireProviderEvents]);

  const disconnect = useCallback(() => {
    const wasWC = localStorage.getItem(STORAGE_RDNS) === WC_RDNS;
    localStorage.removeItem(STORAGE_ADDR);
    localStorage.removeItem(STORAGE_RDNS);
    setActiveProvider(null);
    setWalletState({ address: null, chainId: null, shibName: null });
    if (wasWC) void import('./walletConnect').then(({ disconnectWalletConnect }) => disconnectWalletConnect());
  }, []);

  const switchToShibarium = useCallback(async () => {
    if (!activeProvider) return;
    await ensureShibariumOn(activeProvider);
    await refreshFor(activeProvider);
  }, [refreshFor]);

  const signLoginMessage = useCallback(
    async (statement: string) => {
      if (!state.address || !activeProvider) throw new Error('not connected');
      const nonce = Math.random().toString(36).slice(2);
      const msg = `${statement}\n\nWallet: ${state.address}\nIssued: ${new Date().toISOString()}\nNonce: ${nonce}`;
      const sig = (await activeProvider.request({
        method: 'personal_sign',
        params: [msg, state.address],
      })) as string;
      return { message: msg, signature: sig };
    },
    [state.address],
  );

  return {
    ...state,
    isConnected: !!state.address,
    isOnShibarium: state.chainId === parseInt(SHIBARIUM_CHAIN_ID_HEX, 16),
    connecting,
    error,
    providers,
    hasAnyProvider: providers.length > 0,
    walletConnectEnabled: isWalletConnectEnabled(),
    connectWith,
    connectWalletConnect,
    disconnect,
    switchToShibarium,
    signLoginMessage,
    resolveShibName,
    clearError: () => setError(null),
  };
}

async function ensureShibariumOn(provider: Eip1193Provider) {
  // Cheap early-out: if the wallet already reports Shibarium, don't ask
  // it to switch — some mobile in-wallet browsers (Shibariumscan-aware
  // wallets in particular) throw an internal RPC error when asked to
  // "switch" to the chain they're already on.
  try {
    const current = (await provider.request({ method: 'eth_chainId' })) as string;
    if (typeof current === 'string' && current.toLowerCase() === SHIBARIUM_CHAIN_ID_HEX.toLowerCase()) {
      return;
    }
  } catch {
    /* fall through to the switch attempt */
  }

  try {
    await provider.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: SHIBARIUM_CHAIN_ID_HEX }],
    });
  } catch (e: unknown) {
    const err = e as { code?: number; message?: string };
    // 4902 = chain not known; some wallets nest it in `data.originalError`
    // or use slightly different copy. Sniff both the code and the message.
    const looksUnknown =
      err?.code === 4902 ||
      /unrecognized chain|chain.*not.*configured|unknown.*chain/i.test(err?.message ?? '');
    if (looksUnknown) {
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: SHIBARIUM_CHAIN_ID_HEX,
            chainName: 'Shibarium',
            nativeCurrency: { name: 'BONE', symbol: 'BONE', decimals: 18 },
            rpcUrls: RPC_ENDPOINTS,
            blockExplorerUrls: ['https://shibariumscan.io'],
          },
        ],
      });
    } else if (err?.code !== 4001) {
      throw e;
    }
  }
}

function prettifyWalletError(walletName: string, raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes('must has at least one account') || lower.includes('no account')) {
    return `${walletName} has no active account. Open the wallet, unlock it, and create or import an account, then try again.`;
  }
  if (lower.includes('locked')) {
    return `${walletName} is locked. Open the extension and enter your password, then try again.`;
  }
  if (lower.includes('already pending') || lower.includes('already processing')) {
    return `Open ${walletName} — there's already a pending request waiting for your approval.`;
  }
  return raw;
}
