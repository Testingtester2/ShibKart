import { PlayerSlot } from "../game/types";
export function Results({ order, slots, onLobby, onMenu }: { order: string[]; slots: PlayerSlot[]; onLobby: () => void; onMenu: () => void }) {
  const byId = new Map(slots.map((s) => [s.id, s]));
  const medals = ["🥇", "🥈", "🥉"];
  return (
    <div className="screen">
      <h2>Results</h2>
      <div className="panel-card players" style={{ minWidth: 360 }}>
        {order.map((id, i) => {
          const s = byId.get(id);
          return (
            <div className="pl" key={id}>
              <span style={{ width: 28, fontWeight: 900 }}>{medals[i] || i + 1}</span>
              <span className="swatch" style={{ background: `#${(s?.color ?? 0xffffff).toString(16)}` }} />
              <span style={{ fontWeight: 800 }}>{s?.name ?? id}</span>
              {s && !s.ai && <span className="tag">YOU/PLAYER</span>}
            </div>
          );
        })}
      </div>
      <div className="row">
        <button className="btn" onClick={onLobby}>Back to Lobby</button>
        <button className="btn ghost" onClick={onMenu}>Main Menu</button>
      </div>
    </div>
  );
}
