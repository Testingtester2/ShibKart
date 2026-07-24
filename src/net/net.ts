import { supabase, netConfigured } from "./supa";
import { PlayerSlot, RaceSnapshot, KartInput } from "../game/types";

export type NetMsg =
  | { k: "vote"; id: string; trackId: string }
  | { k: "start"; trackId: string; seed: number; startEpoch: number; slots: PlayerSlot[] }
  | { k: "snap"; s: RaceSnapshot }
  | { k: "input"; id: string; cmd: KartInput }
  | { k: "results"; order: string[] };

type Handlers = {
  players?: (p: PlayerSlot[]) => void;
  vote?: (id: string, trackId: string) => void;
  start?: (m: Extract<NetMsg, { k: "start" }>) => void;
  snap?: (s: RaceSnapshot) => void;
  input?: (id: string, cmd: KartInput) => void;
  results?: (order: string[]) => void;
};

const rid = () => Math.random().toString(36).slice(2, 8);

/** A room over Supabase Realtime (presence + broadcast). Local when unconfigured. */
export class Room {
  code: string; selfId: string; self: PlayerSlot;
  private ch: any = null;
  private h: Handlers = {};
  private roster = new Map<string, PlayerSlot>();

  constructor(code: string, self: PlayerSlot) {
    this.code = code; this.self = self; this.selfId = self.id;
    this.roster.set(self.id, self);
  }

  static make(self: PlayerSlot) { return new Room(rid().toUpperCase(), self); }

  on(h: Handlers) { this.h = { ...this.h, ...h }; return this; }

  async join() {
    if (!netConfigured() || !supabase) { this.emitPlayers(); return; }
    this.ch = supabase.channel(`room:${this.code}`, {
      config: { presence: { key: this.selfId }, broadcast: { self: false } },
    });
    this.ch.on("presence", { event: "sync" }, () => {
      const st = this.ch.presenceState();
      this.roster.clear();
      for (const key of Object.keys(st)) {
        const meta = st[key][0];
        if (meta?.slot) this.roster.set(key, meta.slot);
      }
      this.roster.set(this.selfId, this.self);
      this.emitPlayers();
    });
    this.ch.on("broadcast", { event: "msg" }, ({ payload }: any) => this.handle(payload as NetMsg));
    await this.ch.subscribe(async (status: string) => {
      if (status === "SUBSCRIBED") await this.ch.track({ slot: this.self });
    });
  }

  private handle(m: NetMsg) {
    if (m.k === "vote") this.h.vote?.(m.id, m.trackId);
    else if (m.k === "start") this.h.start?.(m);
    else if (m.k === "snap") this.h.snap?.(m.s);
    else if (m.k === "input") this.h.input?.(m.id, m.cmd);
    else if (m.k === "results") this.h.results?.(m.order);
  }

  private send(m: NetMsg) { this.ch?.send({ type: "broadcast", event: "msg", payload: m }); }
  private emitPlayers() { this.h.players?.([...this.roster.values()]); }

  players(): PlayerSlot[] { return [...this.roster.values()]; }
  /** Host = lowest id present. Everyone agrees deterministically. */
  isHost(): boolean {
    const ids = [...this.roster.keys()].sort();
    return ids.length === 0 || ids[0] === this.selfId;
  }

  async setSelf(patch: Partial<PlayerSlot>) {
    this.self = { ...this.self, ...patch };
    this.roster.set(this.selfId, this.self);
    if (this.ch) await this.ch.track({ slot: this.self });
    this.emitPlayers();
  }
  vote(trackId: string) { this.send({ k: "vote", id: this.selfId, trackId }); this.h.vote?.(this.selfId, trackId); }
  startRace(trackId: string, seed: number, startEpoch: number, slots: PlayerSlot[]) {
    const m: NetMsg = { k: "start", trackId, seed, startEpoch, slots };
    this.send(m); this.h.start?.(m);
  }
  sendSnap(s: RaceSnapshot) { this.send({ k: "snap", s }); }
  sendInput(cmd: KartInput) { this.send({ k: "input", id: this.selfId, cmd }); }
  sendResults(order: string[]) { this.send({ k: "results", order }); }

  leave() { if (this.ch) supabase?.removeChannel(this.ch); this.ch = null; }
}

/** Serverless clock: use Supabase time if available, else local. */
export function now() { return Date.now(); }
