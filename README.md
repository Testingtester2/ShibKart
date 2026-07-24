# ShibKart (web-native)

Browser kart racer for the Shiboshi universe — React + TypeScript + **three.js**
(3D racing) + **Pixi** (FX), **Supabase** realtime PvP, **WalletConnect** login, and
the locked **WutTournament** contract. Same stack as WutCardBoshi so auth / realtime /
tournament are reused, not reinvented.

## Run
```bash
cd ShibKart-web
npm install
npm run dev        # opens http://localhost:5174
```
`npm run build` → production bundle in `dist/` (deploy static to Vercel/Netlify).
`npm run typecheck` → tsc.

## What's in this first drop
- **Polished main menu** (`src/ui/MainMenu.tsx`) — branded wordmark, hero scene,
  parallax, premium buttons w/ hover/press, wallet chip. Renders fully on CSS
  fallbacks; drops in generated art when present.
- **three.js race proof** (`src/game/RaceProof.tsx`) — drivable kart on a real track
  (road ribbon, edge lines, roadside boards, warm lighting, chase cam, drift +
  mini-turbo). Click **Play** to enter it. This is the graphics proof to judge.
- **Boshi driver** via the shared **BoshiCore** three.js compositor
  (`src/boshicore/boshicore.ts`, assets in `public/boshi/`). Falls back to a chibi
  mesh if the rig fails, so the scene always renders.
- **Menu art pipeline** (`tools/gen_menu_assets.py`) — ComfyUI, silhouette-guided,
  auto-places into `public/assets/ui/` (no LoRA).

## Menu / UI art (ComfyUI)
```bash
python tools/gen_menu_assets.py --validate    # offline check (no ComfyUI)
python tools/gen_menu_assets.py               # generate logo, hero_bg, panel, icons
python tools/gen_menu_assets.py --only logo_bone --force
```
Output → `public/assets/ui/` (`logo.png` is the main wordmark). CSS fallbacks show until these exist.

### Logos are optional
`ui/logo.png` is an optional mascot emblem made by the normal edit pipeline (no LoRA). If it's absent the menu shows a crisp CSS text wordmark, so you can skip logo generation entirely.


## Reusing WutCardBoshi (WITHOUT touching it)
WutCardBoshi is treated as **read-only reference**. Its integration files were
**copied** into `src/reference/wutcard/` (supabase client, wallet + WalletConnect,
tournamentChain, pvp realtime client, `WutTournament.abi.json`). Nothing in the
WutCardBoshi folder was modified. These are wired into `src/net/` as we build the
PvP flow (they read the same env vars, so the same login + tournament apply).

## Env (for PvP + wallet, later)
Create `.env`:
```
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_WALLETCONNECT_PROJECT_ID=...
```
Racing works vs AI without these; realtime PvP + wallet need them.

## Layout
```
public/boshi/         BoshiCore rig assets (base.glb, traits, tex, manifest)
public/assets/ui/     generated menu art (optional)
src/ui/               MainMenu + styles
src/game/             three.js race proof, track, boshi driver
src/boshicore/        BoshiCore compositor (copied from the BoshiCore repo)
src/reference/wutcard/ copied WutCardBoshi integration (read-only source)
src/net/              PvP wiring (next)
tools/gen_menu_assets.py  ComfyUI menu art
```
