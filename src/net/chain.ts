// Minimal EVM call helpers over the connected wallet provider (no ethers/viem).
// Selectors are derived with keccak (same as WutCardBoshi's hardcoded ones).
import { keccak_256 } from "@noble/hashes/sha3";
import { getProvider } from "./wallet";

export const CHAIN_ID = Number((import.meta as any).env?.VITE_CHAIN_ID ?? 1);

const toHex = (b: Uint8Array) => Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
export function selector(sig: string): string { return "0x" + toHex(keccak_256(new TextEncoder().encode(sig)).slice(0, 4)); }
export function keccakHex(s: string): string { return "0x" + toHex(keccak_256(new TextEncoder().encode(s))); }

export const wUint = (v: bigint | number): string => { let n = BigInt(v); if (n < 0n) n = (1n << 256n) + n; return n.toString(16).padStart(64, "0"); };
export const wAddr = (a: string): string => a.toLowerCase().replace(/^0x/, "").padStart(64, "0");
export const wBytes32 = (h: string): string => h.toLowerCase().replace(/^0x/, "").padStart(64, "0");
/** ABI-encode a dynamic address[] as (offset already placed by caller) len + items. */
export const wAddrArray = (arr: string[]): string => wUint(arr.length) + arr.map(wAddr).join("");
export const wUintArray = (arr: (bigint | number)[]): string => wUint(arr.length) + arr.map(wUint).join("");

function provider() { const p = getProvider(); if (!p) throw new Error("Connect your wallet first."); return p; }
async function from(): Promise<string> { const a = (await provider().request({ method: "eth_accounts" })) as string[]; if (!a?.[0]) throw new Error("No wallet account."); return a[0]; }

export async function send(to: string, data: string, valueWei = 0n): Promise<string> {
  return (await provider().request({ method: "eth_sendTransaction", params: [{ from: await from(), to, data, value: "0x" + valueWei.toString(16) }] })) as string;
}
export async function call(to: string, data: string): Promise<string> {
  return (await provider().request({ method: "eth_call", params: [{ to, data }, "latest"] })) as string;
}
export interface Receipt { status?: string; logs?: { topics: string[]; data: string }[] }
export async function waitReceipt(txHash: string, timeoutMs = 90000): Promise<Receipt | null> {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const r = (await provider().request({ method: "eth_getTransactionReceipt", params: [txHash] })) as Receipt | null;
    if (r) return r; await new Promise((res) => setTimeout(res, 3000));
  }
  return null;
}
export const boneToWei = (bone: number): bigint => BigInt(Math.round(bone * 1e6)) * 10n ** 12n;
export const weiToBone = (wei: bigint): number => Number(wei / 10n ** 12n) / 1e6;
