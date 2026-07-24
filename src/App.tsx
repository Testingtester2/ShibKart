import { useMemo, useState } from "react";
import { MainMenu } from "./ui/MainMenu";
import { Lobby } from "./ui/Lobby";
import { Maps } from "./ui/Maps";
import { Garage } from "./ui/Garage";
import { Tournament } from "./ui/Tournament";
import { Results } from "./ui/Results";
import { RaceView } from "./game/RaceView";
import { loadIdentity } from "./state";
import { PlayerSlot } from "./game/types";
import { Room } from "./net/net";
import "./ui/screens.css";

export type RaceParams = { trackId: string; seed: number; startEpoch: number; slots: PlayerSlot[]; room: Room | null };

export function App() {
  const [screen, setScreen] = useState<string>("menu");
  const identity = useMemo(() => loadIdentity(), []);
  const [race, setRace] = useState<RaceParams | null>(null);
  const [result, setResult] = useState<{ order: string[]; slots: PlayerSlot[] } | null>(null);

  const go = (s: string) => setScreen(s === "play" ? "lobby" : s);

  return (
    <div className="app-root">
      {screen === "menu" && <MainMenu onNav={go} />}
      {screen === "lobby" && (
        <Lobby identity={identity} onBack={() => setScreen("menu")}
          onStart={(p) => { setRace(p); setScreen("race"); }} />
      )}
      {screen === "maps" && <Maps onBack={() => setScreen("menu")} />}
      {screen === "garage" && <Garage identity={identity} onBack={() => setScreen("menu")} />}
      {screen === "tournament" && <Tournament onBack={() => setScreen("menu")} onPlay={() => setScreen("lobby")} />}
      {screen === "settings" && <Maps onBack={() => setScreen("menu")} settings />}
      {screen === "race" && race && (
        <RaceView params={race} selfId={identity.id}
          onFinish={(order) => { setResult({ order, slots: race.slots }); setScreen("results"); }} />
      )}
      {screen === "results" && result && (
        <Results order={result.order} slots={result.slots}
          onLobby={() => setScreen("lobby")} onMenu={() => setScreen("menu")} />
      )}
    </div>
  );
}
