// Client auth — proves wallet control so nobody can act/submit as another wallet.
// personal_sign a login message -> `auth` edge fn recovers + verifies -> HMAC session
// token (cached ~6h). Carried on every result/settlement call.
import { supabase } from "./supa";
import { getProvider, walletAddress } from "./wallet";

export async function getSessionToken(interactive = true): Promise<string | null> {
  const wallet = walletAddress();
  if (!wallet || !supabase) return null;
  const key = "shibkart.session." + wallet.toLowerCase();
  try { const c = JSON.parse(localStorage.getItem(key) || "null"); if (c?.token && c.exp > Date.now() + 60000) return c.token; } catch {}
  if (!interactive) return null;
  const p = getProvider(); if (!p) return null;
  const message = `ShibKart login\nwallet: ${wallet}\nts: ${Date.now()}`;
  let signature: string;
  try { signature = (await p.request({ method: "personal_sign", params: [message, wallet] })) as string; } catch { return null; }
  const { data, error } = await supabase.functions.invoke("auth", { body: { wallet, message, signature } });
  if (error || !data?.token) return null;
  try { localStorage.setItem(key, JSON.stringify({ token: data.token, exp: data.exp })); } catch {}
  return data.token as string;
}

/** Submit a finished tournament race's order (wallet addresses) for server-side
 *  validation + recording. Auth-bound; the server rejects spoofed/foreign results. */
export async function reportResult(tournamentId: string, orderAddresses: string[]) {
  const token = await getSessionToken();
  if (!token || !supabase) return null;
  const { data } = await supabase.functions.invoke("race-report", { body: { token, tournamentId, orderAddresses } });
  return data;
}
