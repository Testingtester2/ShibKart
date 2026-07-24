// ShibKart tournament client — drives the REAL on-chain contract.
// Two backends, chosen by VITE_TOURNAMENT_KIND:
//   "wut"      -> existing locked WutTournament (winner-takes-all, signed claimPrize)
//   "shibkart" -> new ShibKartTournament.sol (entry-fee pool + signed podium payouts)
// Same wallet + Supabase env as WutCardBoshi. Off-chain race standings are signed by
// the match server (Supabase edge fn `tourney-sign`) and submitted on-chain.
//
// ======================= CONFIG — maz, confirm/fill =======================
//   VITE_TOURNAMENT_CONTRACT = 0x...   (the deployed contract address)
//   VITE_CHAIN_ID            = <chain id of the deployment>
//   VITE_TOURNAMENT_KIND     = wut | shibkart   (default wut = existing contract)
// ==========================================================================
import { selector, keccakHex, wUint, wAddr, wBytes32, wAddrArray, wUintArray, send, call, waitReceipt, boneToWei, weiToBone } from "./chain";
import { getSessionToken } from "./auth";

export const TOURNAMENT_CONTRACT = ((import.meta as any).env?.VITE_TOURNAMENT_CONTRACT as string) ?? "";
export const KIND = (((import.meta as any).env?.VITE_TOURNAMENT_KIND as string) ?? "wut") as "wut" | "shibkart";
export const tournamentConfigured = () => !!TOURNAMENT_CONTRACT;

const S = {
  join: selector("join(uint256)"),
  lock: selector("lock(uint256)"),
  createWut: selector("createTournament(uint16,bool)"),
  claimWut: selector("claimPrize(uint256,address,uint8,bytes32,bytes32)"),
  tourWut: selector("tournaments(uint256)"),
  createSK: selector("createTournament(uint16,uint96,uint8,bool)"),
  finalizeSK: selector("finalize(uint256,address[],uint96[],uint8,bytes32,bytes32)"),
  tourSK: selector("tournaments(uint256)"),
};
const T_WUT = keccakHex("TournamentCreated(uint256,address,uint96,uint16,bool)");
const T_SK = keccakHex("RaceTournamentCreated(uint256,address,uint96,uint96,uint16,uint8,bool)");

export interface OnChainTournament { sponsor: string; potWei: bigint; maxPlayers: number; entryWei: bigint; locked: boolean; settled: boolean; }

async function createdId(tx: string, topic: string): Promise<number> {
  const rc = await waitReceipt(tx); if (!rc) throw new Error("tx not confirmed");
  if (rc.status && rc.status !== "0x1") throw new Error("tx reverted");
  const log = rc.logs?.find((l) => l.topics?.[0]?.toLowerCase() === topic);
  return log ? Number(BigInt(log.topics[1])) : -1;
}

export const Tournaments = {
  kind: KIND,
  configured: tournamentConfigured,

  async create(o: { maxPlayers: number; entryBone?: number; races?: number; prizeBone?: number; closed?: boolean }) {
    if (!TOURNAMENT_CONTRACT) throw new Error("Set VITE_TOURNAMENT_CONTRACT");
    if (KIND === "shibkart") {
      const data = S.createSK + wUint(o.maxPlayers) + wUint(boneToWei(o.entryBone ?? 0)) + wUint(o.races ?? 3) + wUint(o.closed ? 1 : 0);
      return { tx: "", id: await createdId(await send(TOURNAMENT_CONTRACT, data, boneToWei(o.prizeBone ?? 0)), T_SK) };
    }
    const data = S.createWut + wUint(o.maxPlayers) + wUint(o.closed ? 1 : 0);
    return { tx: "", id: await createdId(await send(TOURNAMENT_CONTRACT, data, boneToWei(o.prizeBone ?? 0)), T_WUT) };
  },

  async join(id: number, entryBone = 0) {
    return send(TOURNAMENT_CONTRACT, S.join + wUint(id), KIND === "shibkart" ? boneToWei(entryBone) : 0n);
  },
  async lock(id: number) { return send(TOURNAMENT_CONTRACT, S.lock + wUint(id)); },

  async read(id: number): Promise<OnChainTournament | null> {
    const sel = KIND === "shibkart" ? S.tourSK : S.tourWut;
    const out = await call(TOURNAMENT_CONTRACT, sel + wUint(id)); if (!out || out === "0x") return null;
    const h = out.replace(/^0x/, ""), w = (i: number) => h.slice(i * 64, i * 64 + 64);
    if (KIND === "shibkart") return { sponsor: "0x" + w(0).slice(24), potWei: BigInt("0x" + w(1)), maxPlayers: Number(BigInt("0x" + w(2))), entryWei: BigInt("0x" + w(3)), locked: BigInt("0x" + w(6)) === 1n, settled: BigInt("0x" + w(7)) === 1n };
    return { sponsor: "0x" + w(0).slice(24), potWei: BigInt("0x" + w(1)), maxPlayers: Number(BigInt("0x" + w(2))), entryWei: 0n, locked: BigInt("0x" + w(4)) === 1n, settled: BigInt("0x" + w(5)) === 1n };
  },

  /** Submit the finished tournament's result on-chain (server-signed). */
  async settle(id: number, order: string[]) {
    if (KIND === "shibkart") {
      const sig = await fetchStandingsSignature(id, order);
      if (!sig) throw new Error("no server signature (needs VITE_SUPABASE_* + tourney-sign edge fn)");
      const amounts = sig.amountsBone.map(boneToWei);
      const winTail = wAddrArray(sig.winners), winOff = 6 * 32, amtOff = winOff + winTail.length / 2;
      const data = S.finalizeSK + wUint(id) + wUint(winOff) + wUint(amtOff) + wUint(sig.v) + wBytes32(sig.r) + wBytes32(sig.s) + winTail + wUintArray(amounts);
      return send(TOURNAMENT_CONTRACT, data);
    }
    const sig = await fetchWinnerSignature(id);
    if (!sig) throw new Error("no server signature");
    return send(TOURNAMENT_CONTRACT, S.claimWut + wUint(id) + wAddr(sig.winner) + wUint(sig.v) + wBytes32(sig.r) + wBytes32(sig.s));
  },
  weiToBone,
};

async function post(path: string, body: any) {
  const url = (import.meta as any).env?.VITE_SUPABASE_URL, key = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  try { const r = await fetch(`${url}/functions/v1/${path}`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}`, apikey: key }, body: JSON.stringify(body) }); return r.ok ? await r.json() : null; } catch { return null; }
}
export async function fetchWinnerSignature(id: number) { const token = await getSessionToken(); const j = await post("tourney-sign", { tournamentId: String(id), token }); return j && j.winner ? { winner: String(j.winner), v: Number(j.v), r: String(j.r), s: String(j.s) } : null; }
export async function fetchStandingsSignature(id: number, order: string[]) { const token = await getSessionToken(); const j = await post("tourney-sign", { tournamentId: String(id), order, token }); return j && j.winners ? { winners: j.winners as string[], amountsBone: j.amountsBone as number[], v: Number(j.v), r: String(j.r), s: String(j.s) } : null; }
