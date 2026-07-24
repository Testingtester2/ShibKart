import { useState } from "react";
import { TRACKS } from "../game/track";
import { MapThumb } from "./MapThumb";

export function Maps({ onBack, tournament, settings }: { onBack: () => void; tournament?: boolean; settings?: boolean }) {
  const [sel, setSel] = useState(TRACKS[0].id);
  const title = tournament ? "Tournament" : settings ? "Settings" : "Maps";
  return (
    <div className="screen">
      <button className="back-btn" onClick={onBack}>← Menu</button>
      <h2>{title}</h2>
      {tournament && <div className="panel-card" style={{ maxWidth: 620 }}>On-chain tournaments run on the locked contract. Connect your wallet, enter, and the podium is paid from the pot. (Wiring lives in the PvP flow.)</div>}
      {settings && <div className="panel-card" style={{ maxWidth: 620 }}>Racing: WASD / arrows to drive, Space to drift, E for items. Audio + graphics options land here.</div>}
      {!tournament && !settings && <div style={{ opacity: 0.85, fontWeight: 700, marginBottom: 4 }}>{TRACKS.length} circuits — every biome, every layout</div>}
      <div className="mapgrid">
        {TRACKS.map((t) => <MapThumb key={t.id} track={t} selected={sel === t.id} onClick={() => setSel(t.id)} />)}
      </div>
    </div>
  );
}
