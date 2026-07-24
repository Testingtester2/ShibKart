import { useState } from "react";
import { Tournaments, tournamentConfigured, KIND } from "../net/tournament";
import { connectWallet, walletAddress, walletConfigured } from "../net/wallet";

export function Tournament({ onBack, onPlay }: { onBack: () => void; onPlay: () => void }) {
  const [addr, setAddr] = useState(walletAddress());
  const [id, setId] = useState("");
  const [status, setStatus] = useState("");
  const [state, setState] = useState<string>("");

  const guard = async (fn: () => Promise<any>, label: string) => {
    try { setStatus(`${label}…`); const r = await fn(); setStatus(`${label} ✓ ${typeof r === "string" ? r.slice(0, 10) : ""}`); }
    catch (e: any) { setStatus(`${label} ✗ ${e?.message || e}`); }
  };

  const connect = async () => { const a = walletConfigured() ? await connectWallet() : "0xDEMO"; setAddr(a); };
  const create = () => guard(async () => { const { id } = await Tournaments.create({ maxPlayers: 8, entryBone: 1, races: 3, prizeBone: 0, closed: false }); setId(String(id)); return "id " + id; }, "Create");
  const join = () => guard(() => Tournaments.join(Number(id), 1), "Join");
  const lock = () => guard(() => Tournaments.lock(Number(id)), "Lock");
  const settle = () => guard(() => Tournaments.settle(Number(id), []), "Settle");
  const read = () => guard(async () => { const t = await Tournaments.read(Number(id)); setState(t ? `pot ${Tournaments.weiToBone(t.potWei)} · players≤${t.maxPlayers} · locked ${t.locked} · settled ${t.settled}` : "not found"); return "read"; }, "Read");

  return (
    <div className="screen">
      <button className="back-btn" onClick={onBack}>← Menu</button>
      <h2>Tournament</h2>
      <div className="panel-card" style={{ maxWidth: 620 }}>
        On-chain racing tournaments on the <b>{KIND === "shibkart" ? "ShibKartTournament" : "WutTournament"}</b> contract
        {KIND === "shibkart" ? " (entry-fee pool + podium payouts)" : " (winner-takes-all, signed result)"}.
        {!tournamentConfigured() && <div style={{ color: "#ffcf7e", marginTop: 6 }}>⚠ Set <code>VITE_TOURNAMENT_CONTRACT</code> (+ <code>VITE_CHAIN_ID</code>, <code>VITE_TOURNAMENT_KIND</code>) to go live. Actions are disabled until then.</div>}
      </div>
      <div className="row">
        <button className="btn" onClick={connect}>{addr ? addr.slice(0, 6) + "…" + addr.slice(-4) : "Connect Wallet"}</button>
      </div>
      <div className="panel-card row" style={{ gap: 8 }}>
        <input className="field" placeholder="tournament id" value={id} onChange={(e) => setId(e.target.value)} />
        <button className="btn" disabled={!tournamentConfigured()} onClick={create}>Create</button>
        <button className="btn ghost" disabled={!tournamentConfigured()} onClick={join}>Join</button>
        <button className="btn ghost" disabled={!tournamentConfigured()} onClick={lock}>Lock</button>
        <button className="btn ghost" disabled={!tournamentConfigured()} onClick={read}>Read</button>
        <button className="btn ghost" disabled={!tournamentConfigured()} onClick={settle}>Settle</button>
      </div>
      {state && <div className="panel-card">{state}</div>}
      {status && <div className="panel-card" style={{ fontFamily: "monospace", fontSize: 13 }}>{status}</div>}
      <div className="row"><button className="btn" onClick={onPlay}>Play a Tournament Race →</button></div>
    </div>
  );
}
