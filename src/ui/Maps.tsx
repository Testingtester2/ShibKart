import { useState } from "react";
import { TRACKS } from "../game/track";

export function Maps({ onBack, tournament, settings }: { onBack: () => void; tournament?: boolean; settings?: boolean }) {
  const [sel, setSel] = useState(TRACKS[0].id);
  const title = tournament ? "Tournament" : settings ? "Settings" : "Maps";
  return (
    <div className="screen">
      <button className="back-btn" onClick={onBack}>← Menu</button>
      <h2>{title}</h2>
      {tournament && <div className="panel-card">On-chain tournaments run on the locked <b>WutTournament</b> contract. Connect your wallet in the lobby to enter — results report to the contract. (Wiring live in the PvP flow.)</div>}
      {settings && <div className="panel-card">Audio, controls and graphics options land here. Racing uses WASD / arrows + Space to drift.</div>}
      <div className="grid">
        {TRACKS.map((t) => (
          <div key={t.id} className={`tile ${sel === t.id ? "sel" : ""}`} onClick={() => setSel(t.id)}>
            <div className="thumb" style={{ background: `linear-gradient(160deg, #${t.palette.sky.toString(16)}, #${t.palette.ground.toString(16)})` }} />
            <div className="cap">{t.name}<small>{t.theme}</small></div>
          </div>
        ))}
      </div>
    </div>
  );
}
