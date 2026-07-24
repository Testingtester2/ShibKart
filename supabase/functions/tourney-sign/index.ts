// ShibKart tournament RESULT SIGNER (Deno edge fn) — the referee.
// Signs the SERVER-STORED standings (never the caller's claim) with RESULT_SIGNER_KEY,
// producing the v/r/s the contract's finalize()/claimPrize() verifies. No client can
// forge a win or a payout: the signature only covers what the server recorded as the
// verified result, and the contract checks signer == resultSigner.
//
// Secrets: RESULT_SIGNER_KEY (hex, no 0x), TOURNAMENT_CONTRACT (0x…), CHAIN_ID,
//          TOURNAMENT_KIND (wut|shibkart), SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, AUTH_SECRET
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { keccak_256 } from "npm:@noble/hashes@1.4.0/sha3";
import { cors, json, u256, addr32, abiEncode, ethHash32, signDigest } from "../_shared/eth.ts";
import { verifyToken } from "../auth/index.ts";

const boneToWei = (b: number) => BigInt(Math.round(b * 1e6)) * 10n ** 12n;
const SPLIT = [0.5, 0.3, 0.2]; // podium share of pot

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("RESULT_SIGNER_KEY"), contract = Deno.env.get("TOURNAMENT_CONTRACT");
    const chainId = BigInt(Deno.env.get("CHAIN_ID") ?? "109"), kind = Deno.env.get("TOURNAMENT_KIND") ?? "wut";
    const secret = Deno.env.get("AUTH_SECRET");
    if (!key || !contract || !secret) return json(500, { error: "signer not configured" });

    const { tournamentId, token } = await req.json();
    if (!verifyToken(token ?? "", secret)) return json(401, { error: "auth required" });
    if (!tournamentId) return json(400, { error: "tournamentId required" });

    const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: trows } = await supa.from("tournaments").select("chain_tid,pot_bone,status").eq("id", tournamentId).limit(1);
    const t = trows?.[0];
    if (!t || t.chain_tid == null) return json(400, { error: "tournament not mapped on-chain" });
    if (t.status !== "verified") return json(400, { error: "standings not verified yet" });
    const { data: st } = await supa.from("tournament_standings").select("place,address").eq("tournament_id", tournamentId).order("place");
    const podium = (st ?? []).filter((r: any) => /^0x[0-9a-fA-F]{40}$/.test(r.address));
    if (!podium.length) return json(400, { error: "no verified standings" });
    const id = BigInt(t.chain_tid);

    if (kind === "shibkart") {
      const pot = Number(t.pot_bone ?? 0);
      const n = Math.min(3, podium.length);
      const winners = podium.slice(0, n).map((r: any) => r.address as string);
      const amountsBone = winners.map((_, i) => Math.floor(pot * (SPLIT[i] / SPLIT.slice(0, n).reduce((a, b) => a + b, 0)) * 100) / 100);
      // inner = keccak(abi.encode(contract, chainId, id, address[] winners, uint96[] amounts))
      const head = [addr32(contract), u256(chainId), u256(id), u256(160n), u256(BigInt(160 + 32 + winners.length * 32))];
      const wtail = [u256(BigInt(winners.length)), ...winners.map(addr32)];
      const atail = [u256(BigInt(amountsBone.length)), ...amountsBone.map((b) => u256(boneToWei(b)))];
      const inner = keccak_256(abiEncode([...head, ...wtail, ...atail]));
      const sig = signDigest(ethHash32(inner), key);
      return json(200, { winners, amountsBone, ...sig });
    }
    // wut: single winner, keccak(abi.encode(chainId, contract, id, winner))
    const winner = podium[0].address as string;
    const inner = keccak_256(abiEncode([u256(chainId), addr32(contract), u256(id), addr32(winner)]));
    const sig = signDigest(ethHash32(inner), key);
    return json(200, { winner, ...sig });
  } catch (e) { return json(500, { error: String(e) }); }
});
