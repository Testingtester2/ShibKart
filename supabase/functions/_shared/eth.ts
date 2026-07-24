// Shared crypto for ShibKart edge functions (Deno). Mirrors WutCardBoshi's
// tourney-sign: secp256k1 (noble) with RFC-6979 hmac hookup, keccak, ecrecover.
import * as secp from "npm:@noble/secp256k1@2.1.0";
import { keccak_256 } from "npm:@noble/hashes@1.4.0/sha3";
import { hmac } from "npm:@noble/hashes@1.4.0/hmac";
import { sha256 } from "npm:@noble/hashes@1.4.0/sha256";
secp.etc.hmacSha256Sync = (k: Uint8Array, ...m: Uint8Array[]) => hmac(sha256, k, secp.etc.concatBytes(...m));

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

export const hexToBytes = (h: string) => { h = h.replace(/^0x/, ""); const o = new Uint8Array(h.length / 2); for (let i = 0; i < o.length; i++) o[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16); return o; };
export const bytesToHex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
export const utf8 = (s: string) => new TextEncoder().encode(s);

export function ethHashPersonal(msg: string): Uint8Array {
  const m = utf8(msg);
  return keccak_256(secp.etc.concatBytes(utf8(`\x19Ethereum Signed Message:\n${m.length}`), m));
}
export function ethHash32(inner: Uint8Array): Uint8Array {
  return keccak_256(secp.etc.concatBytes(utf8("\x19Ethereum Signed Message:\n32"), inner));
}
export function addressFromPub(pub: Uint8Array): string {
  const h = keccak_256(pub.slice(1)); // drop 0x04 prefix
  return "0x" + bytesToHex(h.slice(12));
}
/** Recover the signer address from a 65-byte personal_sign signature over `digest`. */
export function recover(digest: Uint8Array, sig65: string): string | null {
  try {
    const s = hexToBytes(sig65); if (s.length !== 65) return null;
    let v = s[64]; if (v >= 27) v -= 27;
    const signature = secp.Signature.fromCompact(s.slice(0, 64)).addRecoveryBit(v);
    const pub = signature.recoverPublicKey(digest).toRawBytes(false);
    return addressFromPub(pub).toLowerCase();
  } catch { return null; }
}
/** Sign a 32-byte digest with the result-signer key -> {v,r,s} for the contract. */
export function signDigest(digest: Uint8Array, keyHex: string): { v: number; r: string; s: string } {
  const sig = secp.sign(digest, hexToBytes(keyHex));
  return { v: sig.recovery + 27, r: "0x" + sig.r.toString(16).padStart(64, "0"), s: "0x" + sig.s.toString(16).padStart(64, "0") };
}
export function signerAddress(keyHex: string): string {
  const pub = secp.getPublicKey(hexToBytes(keyHex), false);
  return addressFromPub(pub).toLowerCase();
}
// minimal ABI encoders
export const u256 = (v: bigint) => { const o = new Uint8Array(32); for (let i = 31; i >= 0; i--) { o[i] = Number(v & 0xffn); v >>= 8n; } return o; };
export const addr32 = (a: string) => u256(BigInt(a.toLowerCase()));
export function abiEncode(parts: Uint8Array[]): Uint8Array { return secp.etc.concatBytes(...parts); }
