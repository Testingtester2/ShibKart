import { PlayerSlot } from "./game/types";

export const FURS = ["orange", "brown", "black"];
export const BODY_NAMES = ["Standard", "Sport", "Heavy"];
export const KART_COLORS = [0xe8503a, 0x3aa0e8, 0x39c56a, 0xffcf3a, 0xa05ad6, 0x33d6c0, 0xff7fb0, 0xf28c28];
const NAMES = ["Shiboshi", "Doge", "Kabosu", "Ryu", "Momo", "Yuki", "Taro", "Hana"];

export interface Identity extends PlayerSlot {}

const KEY = "shibkart.identity";
export function loadIdentity(): Identity {
  try { const r = localStorage.getItem(KEY); if (r) return JSON.parse(r); } catch {}
  const id = "you-" + Math.random().toString(36).slice(2, 8);
  const idn: Identity = { id, name: NAMES[Math.floor(Math.random() * NAMES.length)], fur: "orange", body: 0, color: KART_COLORS[0], ai: false, ready: false };
  saveIdentity(idn); return idn;
}
export function saveIdentity(i: Identity) { try { localStorage.setItem(KEY, JSON.stringify(i)); } catch {} }

/** Fill a lobby up to `n` with AI opponents. */
export function fillWithAI(players: PlayerSlot[], n = 8): PlayerSlot[] {
  const out = [...players];
  let i = 0;
  while (out.length < n) {
    out.push({ id: "ai-" + i, name: "CPU " + NAMES[i % NAMES.length], fur: FURS[i % 3], body: i % 3, color: KART_COLORS[(players.length + i) % KART_COLORS.length], ai: true, ready: true });
    i++;
  }
  return out;
}
