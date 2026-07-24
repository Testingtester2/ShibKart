import { TrackDef } from "../game/track";

/** A map card showing the real track shape (from its waypoints) over the biome gradient. */
export function MapThumb({ track, selected, badge, onClick }: { track: TrackDef; selected?: boolean; badge?: string; onClick?: () => void }) {
  const W = 240, H = 116, pad = 16;
  let minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9;
  for (const [x, y] of track.waypoints) { minx = Math.min(minx, x); maxx = Math.max(maxx, x); miny = Math.min(miny, y); maxy = Math.max(maxy, y); }
  const w = maxx - minx || 1, h = maxy - miny || 1;
  const s = Math.min((W - 2 * pad) / w, (H - 2 * pad) / h);
  const ox = (W - w * s) / 2 - minx * s, oy = (H - h * s) / 2 - miny * s;
  const map = ([x, y]: number[]) => [ox + x * s, oy + y * s];
  const poly = track.waypoints.map(map).map((p) => p.map((n) => n.toFixed(1)).join(",")).join(" ");
  const [sx, sy] = map(track.waypoints[0]);
  const hx = (n: number) => "#" + n.toString(16).padStart(6, "0");
  const grad = `linear-gradient(155deg, ${hx(track.palette.sky)}, ${hx(track.palette.ground)})`;
  return (
    <button className={`mapcard ${selected ? "sel" : ""}`} onClick={onClick} type="button">
      <div className="mapthumb" style={{ background: grad }}>
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
          <polygon points={poly} fill="rgba(20,12,40,0.28)" stroke="rgba(255,255,255,0.9)" strokeWidth="7" strokeLinejoin="round" />
          <polygon points={poly} fill="none" stroke={hx(track.palette.road)} strokeWidth="3" strokeLinejoin="round" />
          <circle cx={sx} cy={sy} r="6" fill="#ffcf3a" stroke="#1a1230" strokeWidth="2" />
        </svg>
        {badge && <span className="mapbadge">{badge}</span>}
      </div>
      <div className="mapcap"><b>{track.name}</b><span>{track.theme} · {track.laps} laps</span></div>
    </button>
  );
}
