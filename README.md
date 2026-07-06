# ShibKart — Placeholder Site

A "coming soon" landing page for **ShibKart**, the on-chain kart racer on Shibarium.

Styled in the usual Shib house look: dark theme, circular Shiba Inu badge
(logo sourced from CoinGecko), two-tone `Shib`/`Kart` wordmark, SHIB-orange →
red accents, glassy rounded cards, and a live "On Shibarium" status pill.

## Stack

Zero-build static site — a single `index.html` with inline CSS/JS. No
dependencies, no framework.

## Deploy to Vercel

This repo is Vercel-ready out of the box.

**Option A — Dashboard**
1. Import the repo at [vercel.com/new](https://vercel.com/new).
2. Framework preset: **Other**. Leave build command empty; output dir is the repo root.
3. Deploy.

**Option B — CLI**
```bash
npm i -g vercel
vercel        # preview
vercel --prod # production
```

`vercel.json` sets clean URLs and a few sensible security headers.

## Local preview

Just open `index.html` in a browser, or serve it:
```bash
npx serve .
```

## Notes

- The Shiba logo is loaded from CoinGecko's CDN
  (`assets.coingecko.com/coins/images/11939/...`) and used for both the header
  mark and the favicon.
- The "Notify me" form is a front-end placeholder — wire it to a real endpoint
  (Vercel Function, Formspree, etc.) when the game is ready to launch.
