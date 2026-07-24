import { supabase, isSupabaseConfigured } from '../game/pvp/client';
import { resolveShibName, isShibName } from './sns';
import { getSessionToken } from '../game/pvpAuth';
import { getWalletAddress } from './wallet';

/** All tournament WRITES go through the authenticated `tourney` edge function
 *  (the tables are read-only for clients). It stamps identity from the session
 *  token and gates host-only ops — so a bracket winner can't be forged and
 *  the escrowed prize can't be stolen. */
async function tourneyFn(op: string, extra: Record<string, unknown> = {}): Promise<any | null> {
  if (!isSupabaseConfigured() || !supabase) return null;
  const wallet = getWalletAddress();
  if (!wallet) return null;
  const token = await getSessionToken(wallet);
  if (!token) return null;
  const { data, error } = await supabase.functions.invoke('tourney', { body: { op, token, ...extra } });
  if (error) { console.warn('[tourney]', op, error); return null; }
  return data;
}

/**
 * Streaming tournament mode — events, entrants, single-elimination brackets.
 *
 * Tables (supabase/migrations/0005_tournaments.sql):
 *   tournaments / tournament_players / tournament_matches
 *
 * Trust model v1: anyone can READ everything (logged in or not); event
 * creation + bracket control are gated to TOURNEY_ADMINS in the client.
 * Phase 2 moves prize/entry to a Shibarium contract (see docs/TOURNAMENTS.md).
 */

// wallets allowed to create/start/score events (lowercased).
// mazrael.shib — resolved + verified on-chain via Blockscout ens_info & D3 DoH.
export const TOURNEY_ADMINS = ['0x2efa87b704d8ec63fdd58d7e568aec24c51bb800'];
export const isTourneyAdmin = (wallet?: string | null): boolean =>
  !!wallet && TOURNEY_ADMINS.includes(wallet.toLowerCase());

export type TourneyStatus = 'scheduled' | 'live' | 'done';

export interface Tournament {
  id: string;
  name: string;
  status: TourneyStatus;
  startsAt: string | null;
  maxPlayers: number;
  prize: string;
  closed: boolean;
  allowlist: string[];
  creator: string;
  createdAt: string;
  chainTid: number | null;   // on-chain WutTournament id (null = off-chain event)
}

export interface TourneyPlayer {
  wallet: string;
  name: string;
  seed: number | null;
}

export interface TourneyMatch {
  id: number;
  round: number;   // 1 = first round
  slot: number;    // 0-based within the round
  p1: string | null;
  p2: string | null;
  winner: string | null;
  liveMatchId: string | null;
}

const rowToTournament = (r: any): Tournament => ({
  id: String(r.id),
  name: String(r.name ?? ''),
  status: (r.status ?? 'scheduled') as TourneyStatus,
  startsAt: r.starts_at ?? null,
  maxPlayers: Number(r.max_players ?? 8),
  prize: String(r.prize ?? ''),
  closed: !!r.closed,
  allowlist: (r.allowlist ?? []) as string[],
  creator: String(r.creator ?? ''),
  createdAt: String(r.created_at ?? ''),
  chainTid: r.chain_tid == null ? null : Number(r.chain_tid),
});

export async function listTournaments(): Promise<Tournament[]> {
  if (!isSupabaseConfigured() || !supabase) return [];
  const { data } = await supabase.from('tournaments').select('*').order('created_at', { ascending: false }).limit(50);
  return (data ?? []).map(rowToTournament);
}

export async function createTournament(t: {
  name: string; startsAt: string | null; maxPlayers: number; prize: string;
  closed: boolean; allowlist: string[]; creator: string;
}): Promise<Tournament | null> {
  const res = await tourneyFn('create', { tournament: t });
  return res?.tournament ? rowToTournament(res.tournament) : null;
}

export async function setTournamentStatus(id: string, status: TourneyStatus): Promise<void> {
  await tourneyFn('set_status', { tid: id, status });
}

/** Record which on-chain WutTournament id backs this event (set right after
 *  the sponsor's escrow tx confirms). The tourney-sign function reads it. */
export async function setChainTid(id: string, chainTid: number): Promise<void> {
  await tourneyFn('set_chain_tid', { tid: id, chainTid });
}

export async function deleteTournament(id: string): Promise<void> {
  await tourneyFn('delete', { tid: id });
}

export async function listPlayers(tid: string): Promise<TourneyPlayer[]> {
  if (!supabase) return [];
  const { data } = await supabase.from('tournament_players').select('*').eq('tournament_id', tid).order('joined_at');
  return (data ?? []).map((r: any) => ({ wallet: String(r.wallet), name: String(r.name ?? ''), seed: r.seed ?? null }));
}

/** Closed events accept wallets OR .shib names on the allowlist. Names are
 *  resolved on-chain at join time so holders can list either form. */
export async function canJoin(t: Tournament, wallet: string, shibName?: string | null): Promise<boolean> {
  if (!t.closed) return true;
  const w = wallet.toLowerCase();
  const n = (shibName ?? '').toLowerCase();
  if (t.allowlist.includes(w)) return true;
  if (n && t.allowlist.includes(n)) return true;
  // allowlist may hold names whose address we haven't compared yet — resolve
  // the few name-shaped entries and check against the joining wallet
  for (const entry of t.allowlist) {
    if (!isShibName(entry)) continue;
    try {
      const addr = await resolveShibName(entry);
      if (addr && addr.toLowerCase() === w) return true;
    } catch { /* keep checking */ }
  }
  return false;
}

// wallet/name are stamped server-side from the session token; the params are
// kept for call-site compatibility but ignored by the server.
export async function joinTournament(tid: string, _wallet: string, _name: string): Promise<boolean> {
  const res = await tourneyFn('join', { tid });
  return !!res?.ok;
}

export async function leaveTournament(tid: string, _wallet: string): Promise<void> {
  await tourneyFn('leave', { tid });
}

export async function listMatches(tid: string): Promise<TourneyMatch[]> {
  if (!supabase) return [];
  const { data } = await supabase.from('tournament_matches').select('*').eq('tournament_id', tid).order('round').order('slot');
  return (data ?? []).map((r: any) => ({
    id: Number(r.id), round: Number(r.round), slot: Number(r.slot),
    p1: r.p1 ?? null, p2: r.p2 ?? null, winner: r.winner ?? null, liveMatchId: r.live_match_id ?? null,
  }));
}

/** Start the event: the server shuffles entrants, builds the bracket, and
 *  auto-advances byes — host-gated, so nobody but the creator can start it. */
export async function startTournament(t: Tournament): Promise<void> {
  await tourneyFn('start', { tid: t.id });
}

/** Record a winner (host-only; the server verifies the winner is in the match
 *  and advances the bracket). */
export async function reportWinner(tid: string, m: TourneyMatch, winner: string): Promise<void> {
  await tourneyFn('report_winner', { tid, matchId: m.id, winner });
}

/** Link the bracket slot to the players' live ranked match (host-only). */
export async function linkLiveMatch(tid: string, m: TourneyMatch): Promise<string | null> {
  const res = await tourneyFn('link', { tid, matchId: m.id });
  return res?.liveMatchId ?? null;
}

/** Pull the linked live match's result onto the bracket (host-only). */
export async function syncLinkedResult(tid: string, m: TourneyMatch): Promise<boolean> {
  const res = await tourneyFn('sync', { tid, matchId: m.id });
  return !!res?.synced;
}

/** Live updates for the whole tab: any change to the three tables → cb. */
export function subscribeTournaments(cb: () => void): () => void {
  if (!isSupabaseConfigured() || !supabase) return () => {};
  const ch = supabase.channel('tourney:all');
  for (const table of ['tournaments', 'tournament_players', 'tournament_matches'])
    ch.on('postgres_changes', { event: '*', schema: 'public', table }, () => cb());
  ch.subscribe();
  return () => { supabase!.removeChannel(ch); };
}
