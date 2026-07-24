import { useEffect, useState } from "react";
import { connectWallet, walletConfigured } from "../net/wallet";
import "./menu.css";

type Props = { onNav: (id: string) => void };

const sfx = (name: string) => {
  // sound hooks — wired to real audio later; no-op safe now
  try { (window as any).__shibSfx?.(name); } catch {}
};

/** <img> that quietly disappears if the art isn't generated yet (CSS fallback shows). */
function Art({ src, className }: { src: string; className?: string }) {
  const [ok, setOk] = useState(true);
  if (!ok) return null;
  return <img className={className} src={src} alt="" onError={() => setOk(false)} draggable={false} />;
}

const MENU = [
  { id: "play", label: "Play", sub: "PvP Race", icon: "🏁", primary: true },
  { id: "maps", label: "Maps", sub: "17 tracks", icon: "🗺️" },
  { id: "garage", label: "Garage", sub: "Kart + Boshi", icon: "🛞" },
  { id: "tournament", label: "Tournament", sub: "On-chain", icon: "🏆" },
  { id: "settings", label: "Settings", sub: "", icon: "⚙️" },
];

export function MainMenu({ onNav }: Props) {
  const [wallet, setWallet] = useState<string | null>(null);
  const [toast, setToast] = useState<string>("");

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(""), 1800);
    return () => clearTimeout(t);
  }, [toast]);

  const pick = (id: string) => { sfx("click"); onNav(id); };

  const connect = async () => {
    sfx("click");
    if (!walletConfigured()) { setWallet("0xSHIB…B0shi (demo)"); return; }
    const a = await connectWallet();
    if (a) setWallet(a.slice(0, 6) + "…" + a.slice(-4));
  };

  return (
    <div className="menu">
      {/* layered hero background (image if present, gradient + parallax otherwise) */}
      <div className="hero-sky" />
      <Art className="hero-art" src="/assets/ui/hero_bg.png" />
      <div className="hero-glow" />
      <div className="hero-track" />
      <div className="parallax">
        <span className="p-kart k1">🏎️</span>
        <span className="p-kart k2">🛞</span>
        <span className="p-boshi b1">🐕</span>
        <span className="p-star s1" />
        <span className="p-star s2" />
        <span className="p-star s3" />
      </div>

      {/* top bar: wallet / login state */}
      <div className="topbar">
        <div className="brand-mini">SHIBKART</div>
        <button className={`wallet ${wallet ? "on" : ""}`} onClick={connect} onMouseEnter={() => sfx("hover")}>
          <span className="dot" />
          {wallet ? wallet : "Connect Wallet"}
        </button>
      </div>

      {/* wordmark */}
      <div className="wordmark">
        <div className="logo-wrap">
          <Art className="logo-img" src="/assets/ui/logo.png" />
          <h1 className="logo-text">
            SHIB<span>KART</span>
          </h1>
        </div>
        <div className="tagline">Chibi Shibas. Real karts. On-chain glory.</div>
      </div>

      {/* menu buttons */}
      <nav className="menu-cards">
        {MENU.map((m, i) => (
          <button
            key={m.id}
            className={`card ${m.primary ? "primary" : ""}`}
            style={{ animationDelay: `${0.06 * i + 0.15}s` }}
            onClick={() => pick(m.id)}
            onMouseEnter={() => sfx("hover")}
          >
            <span className="card-icon">{m.icon}</span>
            <span className="card-text">
              <span className="card-label">{m.label}</span>
              {m.sub && <span className="card-sub">{m.sub}</span>}
            </span>
            <span className="card-glow" />
          </button>
        ))}
      </nav>

      <div className="footer">v0.1 · web-native · three.js proof</div>
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}
