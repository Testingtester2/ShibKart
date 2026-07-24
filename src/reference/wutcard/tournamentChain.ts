/**
 * On-chain wiring for WutTournament (V2) — sponsor escrow, join, claim.
 *
 * DORMANT until VITE_TOURNAMENT_CONTRACT is set: every call throws a clear
 * "not configured" error and the UI hides the on-chain paths, so the app
 * runs its off-chain (Supabase) tournaments unchanged. Set the env var after
 * deploying contracts/WutTournament.sol and the escrow flow lights up.
 *
 * Prize is native BONE (msg.value). Settlement is by the match server's
 * signature (see supabase/functions/tourney-sign) → claimPrize().
 */

import { rpc } from './eth';
import { getActiveProvider } from './wallet';

export const TOURNAMENT_CONTRACT =
  ((import.meta as any).env?.VITE_TOURNAMENT_CONTRACT as string | undefined) ?? '';

export const isTournamentChainEnabled = () => !!TOURNAMENT_CONTRACT;

// keccak256 selectors — see scripts note in this repo's history.
const SEL = {
  createTournament: '0x1519964b',   // (uint16,bool)
  join:             '0x049878f3',   // (uint256)
  lock:             '0xdd467064',   // (uint256)
  claimPrize:       '0x0f33aebe',   // (uint256,address,uint8,bytes32,bytes32)
  cancel:           '0x40e58ee5',   // (uint256)
  reclaimAbandoned: '0x79ffa8ce',   // (uint256)
  addToAllowlist:   '0x93a4011c',   // (uint256,address[])
  tournaments:      '0x7503e1b7',   // (uint256) view
};
const TOPIC_CREATED = '0x0079395b7c2a4f8ac00fe94664f5aaecf9227a24b9f6de50a46fc80e2eb95655';

const pad = (v: bigint | number | string): string => {
  const n = typeof v === 'string' ? BigInt(v) : BigInt(v);
  return n.toString(16).padStart(64, '0');
};
const padAddr = (a: string) => a.toLowerCase().replace(/^0x/, '').padStart(64, '0');
const padHex = (h: string) => h.toLowerCase().replace(/^0x/, '').padStart(64, '0');

function provider() {
  const p = getActiveProvider();
  if (!p) throw new Error('No wallet connected. Click Connect first.');
  return p;
}
async function from(): Promise<string> {
  const p = provider();
  const accounts = (await p.request({ method: 'eth_accounts' })) as string[];
  if (!accounts?.[0]) throw new Error('No wallet account available.');
  return accounts[0];
}
async function send(to: string, data: string, valueWei = 0n): Promise<string> {
  const p = provider();
  return (await p.request({
    method: 'eth_sendTransaction',
    params: [{ from: await from(), to, data, value: '0x' + valueWei.toString(16) }],
  })) as string;
}

export interface ReceiptLog { topics: string[]; data: string }
export interface Receipt { status?: string; logs?: ReceiptLog[] }

/** Poll for a receipt until mined or timeout. */
export async function waitReceipt(txHash: string, timeoutMs = 90_000): Promise<Receipt | null> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const r = await rpc<Receipt | null>({ method: 'eth_getTransactionReceipt', params: [txHash] });
    if (r) return r;
    await new Promise((res) => setTimeout(res, 3000));
  }
  return null;
}

/** Sponsor an event: escrow prizeWei, return {txHash, chainTid} once mined.
 *  chainTid = the indexed id from the TournamentCreated log. */
export async function createTournamentOnChain(maxPlayers: number, closed: boolean, prizeWei: bigint):
  Promise<{ txHash: string; chainTid: number }> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  const data = SEL.createTournament + pad(maxPlayers) + pad(closed ? 1 : 0);
  const txHash = await send(TOURNAMENT_CONTRACT, data, prizeWei);
  const receipt = await waitReceipt(txHash);
  if (!receipt) throw new Error('create tx did not confirm in time');
  if (receipt.status && receipt.status !== '0x1') throw new Error('create tx reverted');
  const log = receipt.logs?.find((l) => l.topics?.[0]?.toLowerCase() === TOPIC_CREATED);
  if (!log) throw new Error('no TournamentCreated event in receipt');
  const chainTid = Number(BigInt(log.topics[1]));   // indexed id
  return { txHash, chainTid };
}

export async function joinOnChain(chainTid: number): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  return send(TOURNAMENT_CONTRACT, SEL.join + pad(chainTid));
}

export async function lockOnChain(chainTid: number): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  return send(TOURNAMENT_CONTRACT, SEL.lock + pad(chainTid));
}

export async function cancelOnChain(chainTid: number): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  return send(TOURNAMENT_CONTRACT, SEL.cancel + pad(chainTid));
}

export async function reclaimAbandonedOnChain(chainTid: number): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  return send(TOURNAMENT_CONTRACT, SEL.reclaimAbandoned + pad(chainTid));
}

/** Curate a closed event's allowlist on-chain (addresses already resolved
 *  from .shib names by the caller). */
export async function addToAllowlistOnChain(chainTid: number, addresses: string[]): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  // (uint256 id, address[] who): head = [id, offset], tail = [len, ...addrs]
  const head = pad(chainTid) + pad(64);
  const tail = pad(addresses.length) + addresses.map(padAddr).join('');
  return send(TOURNAMENT_CONTRACT, SEL.addToAllowlist + head + tail);
}

/** Claim the escrowed prize with the server's signature (anyone can submit). */
export async function claimPrizeOnChain(
  chainTid: number, winner: string, sig: { v: number; r: string; s: string },
): Promise<string> {
  if (!TOURNAMENT_CONTRACT) throw new Error('tournament contract not configured');
  const data = SEL.claimPrize + pad(chainTid) + padAddr(winner) + pad(sig.v) + padHex(sig.r) + padHex(sig.s);
  return send(TOURNAMENT_CONTRACT, data);
}

export interface OnChainTournament {
  sponsor: string; prizeWei: bigint; maxPlayers: number;
  closed: boolean; locked: boolean; settled: boolean; winner: string;
}

/** Read the escrow state (prize, locked, settled…) straight from chain. */
export async function readTournamentOnChain(chainTid: number): Promise<OnChainTournament | null> {
  if (!TOURNAMENT_CONTRACT) return null;
  const out = await rpc<string>({
    method: 'eth_call',
    params: [{ to: TOURNAMENT_CONTRACT, data: SEL.tournaments + pad(chainTid) }, 'latest'],
  });
  if (!out || out === '0x') return null;
  const h = out.replace(/^0x/, '');
  const word = (i: number) => h.slice(i * 64, i * 64 + 64);
  // struct fields returned in declaration order (the dynamic address[] players
  // is NOT returned by the auto-getter, so we stop at `winner`)
  return {
    sponsor: '0x' + word(0).slice(24),
    prizeWei: BigInt('0x' + word(1)),
    maxPlayers: Number(BigInt('0x' + word(2))),
    closed: BigInt('0x' + word(3)) === 1n,
    locked: BigInt('0x' + word(4)) === 1n,
    settled: BigInt('0x' + word(5)) === 1n,
    winner: '0x' + word(7).slice(24),   // word 6 = lockedAt (uint64), word 7 = winner
  };
}

export const boneToWei = (bone: number): bigint => BigInt(Math.round(bone * 1e6)) * 10n ** 12n;
export const weiToBone = (wei: bigint): number => Number(wei / 10n ** 12n) / 1e6;

/** Ask the match server to sign the finished bracket's result. */
export async function fetchWinnerSignature(tournamentId: string):
  Promise<{ winner: string; v: number; r: string; s: string } | null> {
  const url = (import.meta as any).env?.VITE_SUPABASE_URL as string | undefined;
  const key = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY as string | undefined;
  if (!url || !key) return null;
  try {
    const r = await fetch(`${url}/functions/v1/tourney-sign`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ tournamentId }),
    });
    if (!r.ok) return null;
    const j = await r.json();
    if (!j.winner || j.v == null) return null;
    return { winner: String(j.winner), v: Number(j.v), r: String(j.r), s: String(j.s) };
  } catch { return null; }
}
