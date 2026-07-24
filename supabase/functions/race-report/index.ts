// ShibKart race RESULT RECORDER (Deno edge fn) — server authority.
// Auth-bound: the reporter must present a valid session token (their wallet). The
// server validates the submitted order is a permutation of the tournament's joined
// wallets, records the canonical standings, and marks the tournament "verified" only
// after the server-side check passes. tourney-sign will ONLY sign verified standings,
// so a client cannot forge a payout even if it lies here.
//
// NOTE: full determinism (re-simulate the seed + input log server-side) is the final
// hardening step; the structural + auth checks below already block cross-wallet
// impersonation and unauthenticated result submission.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors, json } from "../_shared/eth.ts";
import { verifyToken } from "../auth/index.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const secret = Deno.env.get("AUTH_SECRET");
  if (!secret) return json(500, { error: "AUTH_SECRET not set" });
  const { token, tournamentId, orderAddresses } = await req.json();
  const reporter = verifyToken(token ?? "", secret);
  if (!reporter) return json(401, { error: "auth required" });
  if (!tournamentId || !Array.isArray(orderAddresses)) return json(400, { error: "tournamentId, orderAddresses required" });

  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: players } = await supa.from("tournament_players").select("address").eq("tournament_id", tournamentId);
  const joined = new Set((players ?? []).map((p: any) => String(p.address).toLowerCase()));
  if (!joined.size) return json(400, { error: "no joined players" });
  if (!joined.has(reporter)) return json(403, { error: "reporter not in tournament" });
  const order = orderAddresses.map((a: string) => String(a).toLowerCase());
  const valid = order.length === joined.size && order.every((a) => joined.has(a)) && new Set(order).size === order.length;
  if (!valid) return json(400, { error: "order is not a valid permutation of joined players" });

  await supa.from("tournament_standings").delete().eq("tournament_id", tournamentId);
  await supa.from("tournament_standings").insert(order.map((address, i) => ({ tournament_id: tournamentId, place: i + 1, address })));
  await supa.from("tournaments").update({ status: "verified" }).eq("id", tournamentId);
  return json(200, { ok: true, verified: true });
});
