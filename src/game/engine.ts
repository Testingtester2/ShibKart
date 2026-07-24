import { TrackDef, centerline, nearest, Vec2 } from "./track";
import { KartInput, KartState, Hazard, Shell, RaceSnapshot, ItemKind, PlayerSlot, NO_INPUT } from "./types";

const MAX = 34, ACCEL = 26, BRAKE = 42, FRICT = 14, TURN = 2.4;
const DRIFT_MULT = 1.7, DRIFT_MIN = 9, D_T1 = 0.7, D_T2 = 1.6, D_T3 = 2.6;
const BOOST_MULT = 1.5, OFFROAD_MAX = 15, OFFROAD_DRAG = 22;

function mulberry32(a: number) {
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

export class RaceEngine {
  cl: Vec2[]; gates: number[]; numGates: number; width: number; laps: number;
  karts: KartState[] = []; hazards: Hazard[] = []; shells: Shell[] = [];
  boxes: { x: number; z: number; cd: number }[] = [];
  started = false; over = false; order: string[] = []; time = 0;
  private rng: () => number; private _id = 1;

  constructor(public track: TrackDef, slots: PlayerSlot[], laps = 3, seed = 1) {
    this.cl = centerline(track);
    this.width = track.width;
    this.laps = laps;
    this.rng = mulberry32(seed);
    this.numGates = Math.min(16, Math.max(8, Math.floor(this.cl.length / 8)));
    const stride = Math.floor(this.cl.length / this.numGates);
    this.gates = Array.from({ length: this.numGates }, (_, i) => (i * stride) % this.cl.length);
    const h0 = Math.atan2(this.cl[1][0] - this.cl[0][0], this.cl[1][1] - this.cl[0][1]);
    const nrm: Vec2 = [Math.cos(h0), -Math.sin(h0)];
    slots.forEach((s, i) => {
      const row = Math.floor(i / 2), col = i % 2 === 0 ? -1 : 1;
      const bx = this.cl[0][0] + nrm[0] * col * (this.width * 0.28) - Math.sin(h0) * row * 4.5;
      const bz = this.cl[0][1] + nrm[1] * col * (this.width * 0.28) - Math.cos(h0) * row * 4.5;
      this.karts.push({
        id: s.id, name: s.name, color: s.color, fur: s.fur, body: s.body, ai: s.ai,
        x: bx, z: bz, heading: h0, speed: 0, lap: 0, cp: 0, cpsPassed: 0, finished: false, place: 0,
        item: "", itemCharges: 0, driftDir: 0, driftCharge: 0, boost: 0, offRoad: false, spin: 0, shield: 0,
      });
    });
    // item boxes: 3 clusters around the loop, offset both sides
    for (let g = 0; g < 3; g++) {
      const idx = Math.floor((this.cl.length * g) / 3);
      const a = this.cl[idx], b = this.cl[(idx + 1) % this.cl.length];
      const dir: Vec2 = [b[0] - a[0], b[1] - a[1]]; const l = Math.hypot(dir[0], dir[1]) || 1;
      const nx = -dir[1] / l, nz = dir[0] / l;
      for (const s of [-1, 0, 1]) this.boxes.push({ x: a[0] + nx * s * 3, z: a[1] + nz * s * 3, cd: 0 });
    }
  }

  start() { this.started = true; }

  step(dt: number, inputs: Record<string, KartInput>) {
    if (!this.started || this.over) return;
    this.time += dt;
    for (const k of this.karts) {
      if (k.spin > 0) { k.spin -= dt; k.speed *= 0.92; k.heading += 9 * dt; this.move(k, dt); continue; }
      const inp = k.finished ? NO_INPUT : k.ai ? this.ai(k) : (inputs[k.id] || NO_INPUT);
      this.drive(k, inp, dt);
      if (inp.useItem && k.item) this.useItem(k);
    }
    this.collisions();
    this.updateHazards(dt);
    this.updateShells(dt);
    this.updateBoxes(dt);
    // finish order
    for (const k of this.karts) if (k.finished && !this.order.includes(k.id)) { k.place = this.order.length + 1; this.order.push(k.id); }
    if (this.karts.every((k) => k.finished)) this.over = true;
  }

  private drive(k: KartState, inp: KartInput, dt: number) {
    const nr = nearest(this.cl, k.x, k.z);
    k.offRoad = nr.d > this.width / 2;
    let top = MAX * (k.boost > 0 ? BOOST_MULT : 1);
    if (k.offRoad) top = Math.min(top, OFFROAD_MAX);
    if (inp.throttle > 0) k.speed = Math.min(top, k.speed + ACCEL * inp.throttle * dt);
    else if (inp.throttle < 0) k.speed = Math.max(-8, k.speed - BRAKE * dt);
    else k.speed = Math.max(0, k.speed - FRICT * dt);
    if (k.offRoad && k.speed > OFFROAD_MAX) k.speed = Math.max(OFFROAD_MAX, k.speed - OFFROAD_DRAG * dt);

    const grip = Math.min(1, Math.abs(k.speed) / 7);
    let turn = inp.steer * TURN * turn_mul(k) * grip;
    if (k.offRoad) turn *= 0.8;
    const drifting = inp.drift && Math.abs(k.speed) > DRIFT_MIN && Math.abs(inp.steer) > 0.1;
    if (drifting) { if (k.driftDir === 0) k.driftDir = Math.sign(inp.steer); turn *= DRIFT_MULT; k.driftCharge += dt; }
    else {
      if (k.driftDir !== 0 && k.driftCharge >= D_T1)
        k.boost = k.driftCharge >= D_T3 ? 2.0 : k.driftCharge >= D_T2 ? 1.4 : 0.9;
      k.driftDir = 0; k.driftCharge = 0;
    }
    k.heading += turn * dt;
    k.boost = Math.max(0, k.boost - dt);
    this.move(k, dt);
  }

  private move(k: KartState, dt: number) {
    k.x += Math.sin(k.heading) * k.speed * dt;
    k.z += Math.cos(k.heading) * k.speed * dt;
    const nr = nearest(this.cl, k.x, k.z);
    const lim = this.width / 2 + 2;
    if (nr.d > lim) {
      const nx = (k.x - nr.x) / (nr.d || 1), nz = (k.z - nr.z) / (nr.d || 1);
      k.x = nr.x + nx * (lim - 0.5); k.z = nr.z + nz * (lim - 0.5); k.speed *= 0.5;
    }
    // progress gates
    if (!k.finished) {
      const g = this.cl[this.gates[k.cp]];
      if (Math.hypot(k.x - g[0], k.z - g[1]) < this.width * 0.9 + 3) {
        k.cp = (k.cp + 1) % this.numGates; k.cpsPassed++;
        if (k.cpsPassed >= this.numGates) { k.cpsPassed = 0; k.lap++; if (k.lap >= this.laps) k.finished = true; }
      }
    }
  }

  private ai(k: KartState): KartInput {
    const n = this.cl.length;
    const g = this.gates[k.cp], ga = this.gates[(k.cp + 1) % this.numGates];
    const tx = this.cl[g][0] * 0.6 + this.cl[ga][0] * 0.4, tz = this.cl[g][1] * 0.6 + this.cl[ga][1] * 0.4;
    const desired = Math.atan2(tx - k.x, tz - k.z);
    let diff = wrap(desired - k.heading);
    const steer = clamp(diff * 2.2, -1, 1);
    // slow for upcoming curve
    const a = this.cl[g], b = this.cl[(g + 8) % n], c = this.cl[(g + 16) % n];
    const v1 = Math.atan2(b[0] - a[0], b[1] - a[1]), v2 = Math.atan2(c[0] - b[0], c[1] - b[1]);
    const up = Math.abs(wrap(v2 - v1));
    let throttle = clamp(1 - up * 0.5, 0.55, 1);
    if (Math.abs(diff) > 1.2) throttle *= 0.7;
    const drift = Math.abs(diff) > 0.65 && k.speed > DRIFT_MIN;
    const useItem = !!k.item && this.rng() < 0.012;
    return { throttle, steer, drift, useItem };
  }

  private collisions() {
    for (let i = 0; i < this.karts.length; i++) for (let j = i + 1; j < this.karts.length; j++) {
      const a = this.karts[i], b = this.karts[j];
      const dx = a.x - b.x, dz = a.z - b.z, d = Math.hypot(dx, dz);
      if (d < 1.8 && d > 0.05) {
        const nx = dx / d, nz = dz / d, ov = 1.8 - d;
        a.x += nx * ov * 0.5; a.z += nz * ov * 0.5; b.x -= nx * ov * 0.5; b.z -= nz * ov * 0.5;
        const agg = a.speed >= b.speed ? a : b, vic = agg === a ? b : a;
        vic.speed *= 0.82; agg.speed *= 0.97;
      }
    }
  }

  private updateBoxes(dt: number) {
    for (const box of this.boxes) {
      if (box.cd > 0) { box.cd -= dt; continue; }
      for (const k of this.karts) if (!k.item && Math.hypot(k.x - box.x, k.z - box.z) < 2.2) { this.rollItem(k); box.cd = 5; break; }
    }
  }

  private rollItem(k: KartState) {
    const pos = this.positions().findIndex((x) => x.id === k.id);
    const frac = pos / Math.max(1, this.karts.length - 1);
    let pool: ItemKind[];
    if (frac < 0.34) pool = ["bone", "banana", "oil", "bone"];
    else if (frac < 0.67) pool = ["bone", "shell", "banana", "shield", "triple_bone"];
    else pool = ["shell", "lightning", "triple_bone", "shield", "ghost"];
    k.item = pool[Math.floor(this.rng() * pool.length)];
    k.itemCharges = k.item === "triple_bone" ? 3 : 1;
  }

  private useItem(k: KartState) {
    const it = k.item;
    const fwd: Vec2 = [Math.sin(k.heading), Math.cos(k.heading)];
    if (it === "banana" || it === "oil") this.hazards.push({ id: this._id++, kind: it, x: k.x - fwd[0] * 3, z: k.z - fwd[1] * 3, life: 20 });
    else if (it === "bone" || it === "triple_bone") this.shells.push({ id: this._id++, x: k.x + fwd[0] * 3, z: k.z + fwd[1] * 3, heading: k.heading, life: 3, owner: k.id });
    else if (it === "shell") { const tgt = this.aheadOf(k); this.shells.push({ id: this._id++, x: k.x + fwd[0] * 3, z: k.z + fwd[1] * 3, heading: k.heading, life: 6, owner: k.id }); void tgt; }
    else if (it === "shield") k.shield = 6;
    else if (it === "ghost") { k.boost = Math.max(k.boost, 1.5); k.shield = 3; }
    else if (it === "lightning") for (const o of this.karts) if (o !== k && this.progress(o) > this.progress(k)) { o.spin = 1.5; o.speed *= 0.4; }
    if (it === "triple_bone" && k.itemCharges > 1) k.itemCharges--; else { k.item = ""; k.itemCharges = 0; }
  }

  private aheadOf(k: KartState): KartState | null {
    const s = this.positions(); const i = s.findIndex((x) => x.id === k.id); return i > 0 ? s[i - 1] : null;
  }

  private updateHazards(dt: number) {
    for (const h of [...this.hazards]) {
      h.life -= dt;
      for (const k of this.karts) if (k.spin <= 0 && Math.hypot(k.x - h.x, k.z - h.z) < 1.6) {
        if (k.shield > 0) k.shield = 0; else { k.spin = 1.2; k.speed *= 0.4; }
        this.hazards = this.hazards.filter((x) => x !== h); break;
      }
      if (h.life <= 0) this.hazards = this.hazards.filter((x) => x !== h);
    }
  }

  private updateShells(dt: number) {
    for (const s of [...this.shells]) {
      s.life -= dt;
      s.x += Math.sin(s.heading) * 26 * dt; s.z += Math.cos(s.heading) * 26 * dt;
      for (const k of this.karts) if (k.id !== s.owner && k.spin <= 0 && Math.hypot(k.x - s.x, k.z - s.z) < 1.7) {
        if (k.shield > 0) k.shield = 0; else { k.spin = 1.2; k.speed *= 0.5; }
        this.shells = this.shells.filter((x) => x !== s); break;
      }
      if (s.life <= 0) this.shells = this.shells.filter((x) => x !== s);
    }
    for (const k of this.karts) if (k.shield > 0) k.shield -= dt;
  }

  progress(k: KartState): number {
    if (k.finished) return 1e12 - k.place;
    const g = this.cl[this.gates[k.cp]];
    return (k.lap * this.numGates + k.cpsPassed) * 1e6 - Math.hypot(k.x - g[0], k.z - g[1]);
  }
  positions(): KartState[] { return [...this.karts].sort((a, b) => this.progress(b) - this.progress(a)); }
  placeOf(id: string): number { return this.positions().findIndex((k) => k.id === id) + 1; }

  snapshot(): RaceSnapshot {
    return { t: this.time, karts: this.karts.map((k) => ({ ...k })), hazards: this.hazards.map((h) => ({ ...h })), shells: this.shells.map((s) => ({ ...s })), started: this.started, over: this.over, order: [...this.order] };
  }
  applySnapshot(s: RaceSnapshot) {
    this.time = s.t; this.started = s.started; this.over = s.over; this.order = [...s.order];
    const byId = new Map(this.karts.map((k) => [k.id, k]));
    for (const ks of s.karts) { const k = byId.get(ks.id); if (k) Object.assign(k, ks); }
    this.hazards = s.hazards.map((h) => ({ ...h })); this.shells = s.shells.map((sh) => ({ ...sh }));
  }
}

const turn_mul = (k: KartState) => (k.body === 1 ? 1.08 : k.body === 2 ? 0.92 : 1.0);
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const wrap = (a: number) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
