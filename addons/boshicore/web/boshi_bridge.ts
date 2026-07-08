/**
 * BoshiBridge — JS <-> Godot wallet bridge (stub) for the BoshiCore plan.
 *
 * Extends the existing `window.ShibSession` pattern (web-shell/src/ShibSession.ts,
 * boshi.ts, wagmi.ts) rather than replacing it. ShibSession already carries the
 * connected wallet + primary Boshi PFP; this adds what the *playable-character*
 * flow needs:
 *
 *   1. read ALL owned Boshi token IDs + each token's TRAIT METADATA
 *      (category -> value), shaped for BoshiCompositor.build(metadata) in Godot;
 *   2. push that list onto `window.BoshiBridge` so the Godot HTML5 export can pull
 *      it via JavaScriptBridge (see boshi_bridge.gd);
 *   3. bounty-contract calls (Shadowcat) from this same JS layer via wagmi/ethers.
 *
 * The React shell loads the Godot engine directly (no iframe) so window is shared.
 * On desktop/editor there is no window -> Godot side behaves as a stub.
 *
 * This file is a STUB: fill the marked `// TODO` spots with the project's real
 * wagmi config (wagmi.ts), contract addresses, and ABIs.
 */

import type { Config } from 'wagmi';
import { readContract, writeContract, getAccount } from 'wagmi/actions';
// ethers is used only where a raw provider is easier than wagmi actions.
// import { Contract, JsonRpcProvider } from 'ethers';

// ---- Types shared with Godot (keep in sync with boshi_bridge.gd) ----------------

/** category -> value, already normalized to the trait slots in RIG_SPEC.md §2. */
export type BoshiTraits = Record<string, string>;

export type OwnedBoshi = {
  id: string;               // token id
  name: string | null;      // "Boshi #1234"
  image: string | null;     // PFP fallback
  traits: BoshiTraits;      // { Fur:"gold", Clothing:"suit", Eyes:"laser", ... }
};

export type BoshiBridgeAPI = {
  /** Owned Boshis with resolved traits, or [] (none) / null (couldn't check). */
  ownedBoshis: () => OwnedBoshi[] | null;
  /** JSON string of ownedBoshis() — Godot parses this (JS arrays don't marshal). */
  ownedBoshisJson: () => string;
  /** Force a refresh from chain/explorer; fires 'boshibridge:change' when done. */
  refresh: () => Promise<void>;
  /** Bounty (Shadowcat) — post/accept/claim. Returns tx hash or null. */
  bounty: BountyAPI;
};

export type BountyAPI = {
  /** Post a BONE bounty on beating `targetTimeSec`. */
  post: (targetTimeSec: number, amountWei: string) => Promise<string | null>;
  /** Claim a bounty you beat (server co-signs the proof; see ANTICHEAT_MINT.md). */
  claim: (bountyId: string, proof: string) => Promise<string | null>;
  /** Read open bounties (cached JSON for the Godot leaderboard UI). */
  openJson: () => string;
};

declare global {
  interface Window {
    BoshiBridge?: BoshiBridgeAPI;
  }
}

// ---- Config (wire these to the real project values) -----------------------------

const EXPLORER = 'https://shibariumscan.io';
const BOSHI_CONTRACT = (import.meta.env.VITE_BOSHI_CONTRACT as string | undefined) ?? '';
const SHADOWCAT_BOUNTY = (import.meta.env.VITE_SHADOWCAT_BOUNTY as string | undefined) ?? '';
// TODO import the real ABI: apps/shadowcat-survivors/contracts/ShadowcatBounty_sol_ShadowcatBounty.abi
const SHADOWCAT_BOUNTY_ABI: readonly unknown[] = [];

// The 10k collection attribute schema uses OpenSea-style trait_type/value. We map
// trait_type -> the slot names the compositor expects (RIG_SPEC.md §2).
const SLOT_ALIASES: Record<string, string> = {
  fur: 'Fur', body: 'Body', clothing: 'Clothing', clothes: 'Clothing',
  mouth: 'Mouth', eyes: 'Eyes', headwear: 'Headwear', accessory: 'Accessory',
};

function normalizeTraits(
  attrs: Array<{ trait_type?: string; value?: string }> | undefined,
): BoshiTraits {
  const out: BoshiTraits = {};
  for (const a of attrs ?? []) {
    const slot = SLOT_ALIASES[(a.trait_type ?? '').toLowerCase()];
    if (slot && a.value != null) out[slot] = String(a.value);
  }
  return out;
}

// ---- Owned-Boshi + trait resolution --------------------------------------------

let _cache: OwnedBoshi[] | null = null;

/** Read owned tokens + traits. Reuses boshi.ts's key-less explorer technique;
 *  swap to a wagmi `readContract` tokenURI loop if you prefer pure on-chain. */
export async function loadOwnedBoshiTraits(address: string): Promise<OwnedBoshi[] | null> {
  if (!BOSHI_CONTRACT || !address) return null;
  try {
    const params = new URLSearchParams({ holder_address_hash: address.toLowerCase() });
    const r = await fetch(`${EXPLORER}/api/v2/tokens/${BOSHI_CONTRACT}/instances?${params}`, {
      headers: { Accept: 'application/json' },
    });
    if (!r.ok) return null;
    const data = (await r.json()) as {
      items?: Array<{
        id?: string;
        metadata?: { name?: string; image?: string;
          attributes?: Array<{ trait_type?: string; value?: string }> };
      }>;
    };
    const out: OwnedBoshi[] = (data.items ?? [])
      .map((it) => ({
        id: String(it.id ?? ''),
        name: it.metadata?.name ?? null,
        image: it.metadata?.image ?? null,
        traits: normalizeTraits(it.metadata?.attributes),
      }))
      .filter((b) => b.id !== '');
    _cache = out;
    return out;
  } catch {
    return null;
  }
}

// ---- Bounty (Shadowcat) ---------------------------------------------------------

const bounty: BountyAPI = {
  async post(targetTimeSec, amountWei) {
    if (!SHADOWCAT_BOUNTY) return null;
    try {
      const hash = await writeContract(wagmiConfig, {
        address: SHADOWCAT_BOUNTY as `0x${string}`,
        abi: SHADOWCAT_BOUNTY_ABI as never,
        functionName: 'postBounty',
        args: [BigInt(Math.round(targetTimeSec)), BigInt(amountWei)],
        value: BigInt(amountWei),
      });
      return hash;
    } catch {
      return null;
    }
  },
  async claim(bountyId, proof) {
    if (!SHADOWCAT_BOUNTY) return null;
    try {
      return await writeContract(wagmiConfig, {
        address: SHADOWCAT_BOUNTY as `0x${string}`,
        abi: SHADOWCAT_BOUNTY_ABI as never,
        functionName: 'claim',
        args: [BigInt(bountyId), proof],
      });
    } catch {
      return null;
    }
  },
  openJson() {
    // TODO cache from readContract getOpenBounties(); [] until wired.
    return '[]';
  },
};

// wagmiConfig is provided by the shell (web-shell/src/wagmi.ts). Injected at install.
let wagmiConfig: Config;

// ---- Install onto window (called once from the shell after wallet init) ----------

export function installBoshiBridge(cfg: Config): BoshiBridgeAPI {
  wagmiConfig = cfg;
  const api: BoshiBridgeAPI = {
    ownedBoshis: () => _cache,
    ownedBoshisJson: () => JSON.stringify(_cache ?? []),
    async refresh() {
      const acct = getAccount(wagmiConfig);
      if (acct.address) await loadOwnedBoshiTraits(acct.address);
      window.dispatchEvent(new CustomEvent('boshibridge:change'));
    },
    bounty,
  };
  window.BoshiBridge = api;
  return api;
}

export const boshiBridgeConfigured = BOSHI_CONTRACT !== '';
