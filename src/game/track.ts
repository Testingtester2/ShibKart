export type Vec2 = [number, number];

export interface Palette { sky: number; fog: number; ground: number; road: number; sun: number; }

export interface TrackDef {
  id: string; name: string; theme: string; width: number; laps: number;
  waypoints: Vec2[]; palette: Palette;
}

const PAL: Record<string, Palette> = {
  grass:   { sky: 0x8fd0ff, fog: 0xbfe6ff, ground: 0x54a83f, road: 0x45464f, sun: 0xfff2d8 },
  cherry:  { sky: 0xffd0e6, fog: 0xffe3f1, ground: 0x66b04f, road: 0x4a4a55, sun: 0xfff0f6 },
  city:    { sky: 0x22305a, fog: 0x33406a, ground: 0x2b2f45, road: 0x33343f, sun: 0xbfd0ff },
  desert:  { sky: 0x9ad0ff, fog: 0xf3e6c0, ground: 0xd9b56a, road: 0x8a7a58, sun: 0xfff0d0 },
  moon:    { sky: 0x0a0a1a, fog: 0x14142a, ground: 0x6a6a72, road: 0x2a3a4a, sun: 0xbfe0ff },
  snow:    { sky: 0xbfe0ff, fog: 0xeaf4ff, ground: 0xe8f0f6, road: 0x93a8ba, sun: 0xffffff },
  volcano: { sky: 0x3a1414, fog: 0x5a2418, ground: 0x3a2420, road: 0x2a1c18, sun: 0xffb060 },
  beach:   { sky: 0x2ab0ff, fog: 0xbfeaff, ground: 0xeddba0, road: 0x8a7a5a, sun: 0xfff2d0 },
};

export function radialLoop(rx: number, rz: number, harm: [number, number, number][], steps = 40): Vec2[] {
  const pts: Vec2[] = [];
  for (let i = 0; i < steps; i++) {
    const th = (2 * Math.PI * i) / steps;
    let r = 1;
    for (const [k, a, ph] of harm) r += a * Math.sin(k * th + ph);
    r = Math.max(0.5, r);
    pts.push([Math.cos(th) * rx * r, Math.sin(th) * rz * r]);
  }
  return pts;
}

const T = (id: string, name: string, theme: string, width: number, rx: number, rz: number, harm: [number, number, number][], steps = 40): TrackDef =>
  ({ id, name, theme, width, laps: 3, waypoints: radialLoop(rx, rz, harm, steps), palette: PAL[theme] });

export const TRACKS: TrackDef[] = [
  T("boshi_speedway", "Boshi Speedway", "grass", 12, 62, 36, [], 32),
  T("sakura_sprint", "Sakura Sprint", "cherry", 11, 60, 42, [[2, 0.16, 0.6], [3, 0.1, 0]], 40),
  T("neon_circuit", "Neon Circuit", "city", 10, 56, 46, [[2, 0.22, 1.2], [4, 0.1, 0.4]], 44),
  T("dune_dash", "Dune Dash", "desert", 13, 66, 38, [[1, 0.14, 0.3], [2, 0.12, 2.0]], 36),
  T("lunar_rift", "Lunar Rift", "moon", 11, 58, 48, [[2, 0.2, 0], [3, 0.12, 1.4]], 42),
  T("frostbite_pass", "Frostbite Pass", "snow", 10, 60, 44, [[2, 0.18, 0.9], [4, 0.12, 2.2]], 44),
  T("magma_ring", "Magma Ring", "volcano", 12, 64, 40, [[1, 0.12, 1.1], [3, 0.1, 0.5]], 38),
  T("palm_bay", "Palm Bay", "beach", 12, 64, 42, [[2, 0.16, 2.4], [1, 0.1, 0.2]], 38),
  T("shiba_gardens", "Shiba Gardens", "grass", 11, 60, 46, [[3, 0.16, 0.7], [2, 0.1, 1.8]], 42),
  T("bone_yard", "Bone Yard", "desert", 11, 58, 48, [[2, 0.22, 0.4], [4, 0.12, 1.0]], 44),
  T("moon_market", "Moon Market", "moon", 12, 62, 40, [[2, 0.14, 1.6], [5, 0.08, 0.0]], 40),
  T("cherry_coast", "Cherry Coast", "beach", 12, 66, 44, [[1, 0.16, 0.8], [3, 0.1, 2.1]], 42),
];

export function trackById(id: string): TrackDef {
  return TRACKS.find((t) => t.id === id) || TRACKS[0];
}

/** Catmull-Rom densify. */
export function smooth(p: Vec2[], subdiv = 6): Vec2[] {
  const n = p.length, out: Vec2[] = [];
  const cm = (a: number, b: number, c: number, d: number, t: number) => {
    const t2 = t * t, t3 = t2 * t;
    return 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
  };
  for (let i = 0; i < n; i++) {
    const p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n];
    for (let s = 0; s < subdiv; s++) {
      const t = s / subdiv;
      out.push([cm(p0[0], p1[0], p2[0], p3[0], t), cm(p0[1], p1[1], p2[1], p3[1], t)]);
    }
  }
  return out;
}

const _clCache = new Map<string, Vec2[]>();
export function centerline(t: TrackDef): Vec2[] {
  let c = _clCache.get(t.id);
  if (!c) { c = smooth(t.waypoints, 6); _clCache.set(t.id, c); }
  return c;
}

export function nearest(cl: Vec2[], x: number, z: number) {
  let best = 1e9, bx = x, bz = z, bi = 0;
  for (let i = 0; i < cl.length; i++) {
    const dx = x - cl[i][0], dz = z - cl[i][1], d = dx * dx + dz * dz;
    if (d < best) { best = d; bx = cl[i][0]; bz = cl[i][1]; bi = i; }
  }
  return { d: Math.sqrt(best), x: bx, z: bz, i: bi };
}

/** Local saved tracks (from a future in-app editor) live in localStorage. */
export function savedTracks(): TrackDef[] {
  try {
    const raw = localStorage.getItem("shibkart.tracks");
    return raw ? (JSON.parse(raw) as TrackDef[]) : [];
  } catch { return []; }
}
export function allTracks(): TrackDef[] { return [...TRACKS, ...savedTracks()]; }
