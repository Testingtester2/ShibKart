import { useEffect, useRef, useState } from "react";
import { Identity, fillWithAI } from "../state";
import { TRACKS } from "../game/track";
import { MapThumb } from "./MapThumb";
import { Room, now } from "../net/net";
import { netConfigured } from "../net/supa";
import { PlayerSlot } from "../game/types";
import { RaceParams } from "../App";

export function Lobby({ identity, onBack, onStart }: { identity: Identity; onBack: () => void; onStart: (p: RaceParams) => void }) {
  const [players, setPlayers] = useState<PlayerSlot[]>([identity]);
  const [sel, setSel] = useState(TRACKS[0].id);
  const [votes, setVotes] = useState<Record<string, string>>({});
  const [code, setCode] = useState("");
  const [joinCode, setJoinCode] = useState("");
  const roomRef = useRef<Room | null>(null);

  const wire = (room: Room) => {
    room.on({
      players: setPlayers,
      vote: (id, trackId) => setVotes((v) => ({ ...v, [id]: trackId })),
      start: (m) => onStart({ trackId: m.trackId, seed: m.seed, startEpoch: m.startEpoch, slots: m.slots, room }),
    });
  };

  useEffect(() => {
    const room = Room.make(identity);
    roomRef.current = room; setCode(room.code); wire(room); room.join();
    return () => room.leave();
  }, []);

  const doJoin = async () => {
    if (!joinCode) return;
    roomRef.current?.leave();
    const r = new Room(joinCode.toUpperCase(), identity);
    roomRef.current = r; setCode(r.code); wire(r); await r.join();
  };

  const vote = (id: string) => { setSel(id); roomRef.current?.vote(id); };

  const startRace = () => {
    const room = roomRef.current!;
    const tally: Record<string, number> = {};
    Object.values(votes).forEach((t) => (tally[t] = (tally[t] || 0) + 1));
    const top = Object.entries(tally).sort((a, b) => b[1] - a[1])[0]?.[0] || sel;
    const slots = fillWithAI(room.players(), 8);
    room.startRace(top, Math.floor(Math.random() * 1e9), now() + 3200, slots);
  };

  const host = roomRef.current?.isHost() ?? true;
  const voteCount = (id: string) => Object.values(votes).filter((v) => v === id).length;

  return (
    <div className="screen">
      <button className="back-btn" onClick={onBack}>← Menu</button>
      <h2>PvP Lobby</h2>
      <div className="row">
        <div className="panel-card">
          <div style={{ fontWeight: 800, marginBottom: 8 }}>Room <span style={{ color: "var(--cyan)" }}>{code}</span> {netConfigured() ? "" : "· local"}</div>
          <div className="players">
            {fillWithAI(players, 8).map((p) => (
              <div className="pl" key={p.id}>
                <span className="swatch" style={{ background: `#${p.color.toString(16)}` }} />
                <span style={{ fontWeight: 800 }}>{p.name}</span>
                <span className="tag">{p.ai ? "CPU" : "PLAYER"}</span>
              </div>
            ))}
          </div>
          {netConfigured() && (
            <div className="row" style={{ marginTop: 10 }}>
              <input className="field" placeholder="join code" value={joinCode} onChange={(e) => setJoinCode(e.target.value)} />
              <button className="btn ghost" onClick={doJoin}>Join</button>
            </div>
          )}
        </div>
      </div>

      <h2 style={{ fontSize: 24 }}>Vote a map</h2>
      <div className="mapgrid">
        {TRACKS.map((t) => (
          <MapThumb key={t.id} track={t} selected={sel === t.id} badge={voteCount(t.id) ? `▲ ${voteCount(t.id)}` : undefined} onClick={() => vote(t.id)} />
        ))}
      </div>

      <div className="row" style={{ margin: "16px 0 40px" }}>
        {host ? <button className="btn" onClick={startRace}>Start Race</button>
              : <div className="panel-card">Waiting for host to start…</div>}
      </div>
    </div>
  );
}
