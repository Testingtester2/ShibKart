// ShibKart auth — anti-impersonation. Client personal_signs a login message; we
// recover the address, require it == claimed wallet, and issue an HMAC session
// token bound to that address. Every match/result call must carry this token, so
// nobody can act as a wallet they don't control. (Mirrors WutCardBoshi `auth`.)
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { cors, json, ethHashPersonal, recover, utf8, bytesToHex } from "../_shared/eth.ts";
import { hmac } from "npm:@noble/hashes@1.4.0/hmac";
import { sha256 } from "npm:@noble/hashes@1.4.0/sha256";

const TTL = 6 * 60 * 60 * 1000;
const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
function tokenFor(wallet: string, exp: number, secret: string) {
  const payload = `${wallet.toLowerCase()}.${exp}`;
  const mac = bytesToHex(hmac(sha256, utf8(secret), utf8(payload)));
  return b64(utf8(`${payload}.${mac}`));
}
export function verifyToken(token: string, secret: string): string | null {
  try {
    const [wallet, expS, mac] = atob(token).split(".");
    const exp = Number(expS); if (Date.now() > exp) return null;
    const good = bytesToHex(hmac(sha256, utf8(secret), utf8(`${wallet}.${exp}`)));
    return good === mac ? wallet : null;
  } catch { return null; }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const secret = Deno.env.get("AUTH_SECRET");
  if (!secret) return json(500, { error: "AUTH_SECRET not set" });
  const { wallet, message, signature } = await req.json();
  if (!wallet || !message || !signature) return json(400, { error: "wallet, message, signature required" });
  const rec = recover(ethHashPersonal(message), signature);
  if (!rec || rec !== String(wallet).toLowerCase()) return json(401, { error: "signature does not match wallet" });
  const exp = Date.now() + TTL;
  return json(200, { token: tokenFor(wallet, exp, secret), exp, address: rec });
});
