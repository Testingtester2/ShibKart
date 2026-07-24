# ShibKart — go-live setup (own Supabase + own contract)

Separate from WutCardBoshi. Do these once; the game already runs vs-AI without them.

## 0. Signer keypair (the referee)
```
node tools/gen-signer.mjs
```
Prints a **private key** (→ Supabase secret) and its **address** (→ contract constructor).

## 1. New Supabase project (ShibKart's own)
1. supabase.com → New Project → grab **Project URL**, **anon key**, **project ref**.
2. From `ShibKart-web`:
   ```
   supabase link --project-ref <ref>
   # apply schema (SQL editor, paste supabase/schema.sql)  OR:  supabase db push
   supabase functions deploy auth
   supabase functions deploy race-report
   supabase functions deploy tourney-sign
   ```
3. Edge Function **secrets** (Dashboard → Edge Functions → Secrets):
   ```
   AUTH_SECRET         = <random long string>
   RESULT_SIGNER_KEY   = <private key from step 0, no 0x>
   TOURNAMENT_CONTRACT = <ShibKartTournament address from step 2b>
   CHAIN_ID            = <your chain, e.g. 109>
   TOURNAMENT_KIND     = shibkart
   ```
   Realtime (broadcast/presence) is on by default — the PvP lobby needs no tables.

## 2. Deploy the new contract
`contracts/ShibKartTournament.sol` — constructor arg = the **resultSigner ADDRESS** from step 0.
```
forge create contracts/ShibKartTournament.sol:ShibKartTournament \
  --constructor-args 0xYOUR_SIGNER_ADDRESS --rpc-url $RPC --private-key $DEPLOYER_PK
```
(or Remix). Note the deployed **address** → put it in the Supabase secret above and Vercel below.

## 3. Vercel env vars (Production) → then Redeploy
```
VITE_SUPABASE_URL             = <new shibkart supabase url>
VITE_SUPABASE_ANON_KEY        = <new shibkart anon key>
VITE_WALLETCONNECT_PROJECT_ID = <WalletConnect Cloud id — reuse WutCardBoshi's is fine>
VITE_CHAIN_ID                 = <your chain>
VITE_TOURNAMENT_CONTRACT      = <ShibKartTournament address>
VITE_TOURNAMENT_KIND          = shibkart
```

## What lights up
- Supabase URL + anon key → **realtime PvP lobby** (rooms, map vote, snapshots).
- WalletConnect id → **wallet login** button becomes real.
- Contract vars + deployed functions → **tournaments**: create/join (entry fee) → race →
  server signs verified podium standings → on-chain payout.
Each is independent — add what you want live.
