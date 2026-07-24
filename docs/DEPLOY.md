# ShibKart-web — deploy to GitHub + Vercel

The live site (shibkart.vercel.app) + repo (Testingtester2/ShibKart) currently hold
the **old Godot** build. This is the new **web (Vite)** app — it builds to `dist/`.

## What's different from the Godot deploy
- Godot: static `index.html` at repo root, no build step.
- This: a **Vite app** — Vercel must run `npm run build` and serve `dist/`.
  `vercel.json` here sets framework=vite / build / output for you.

## Recommended: separate repo or branch (keep Godot history intact)
```
cd C:\AIVIDS\ShibKart-web
git init
git add -A
git commit -m "ShibKart web-native (React + three.js PvP)"
git branch -M web
git remote add origin https://github.com/Testingtester2/ShibKart.git
git push -u origin web
```
Then in Vercel: New Project → import the repo → **Root Directory = (repo root of the
`web` branch)**, Framework **Vite**, Build `npm run build`, Output `dist` → Deploy.
Point the `shibkart.vercel.app` domain at this project (or use a new domain and swap
later).

## Or: make this the main site
Push to `main` of a fresh repo (e.g. `Testingtester2/ShibKart-web`) and create a new
Vercel project from it; move the domain over when you're happy.

## Env (Vercel → Settings → Environment Variables) for PvP + wallet + tournament
```
VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
VITE_WALLETCONNECT_PROJECT_ID, VITE_CHAIN_ID
VITE_TOURNAMENT_CONTRACT, VITE_TOURNAMENT_KIND
```
The game runs vs-AI without any of these; realtime PvP + on-chain need them.

## Asset size
`public/boshi/base.glb` (~3.8 MB) + 14 kart/prop `.glb` (~2 MB each) + textures ≈ 35 MB
of static files — fine for Vercel's CDN.

## Edge functions (server authority)
Deploy separately to Supabase (not Vercel):
`supabase functions deploy auth race-report tourney-sign` and apply `supabase/schema.sql`.
