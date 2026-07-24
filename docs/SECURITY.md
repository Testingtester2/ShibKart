# ShibKart security — server authority (mirrors WutCardBoshi)

Nothing that touches **results, standings, or payouts** is trusted from the client.
The client host may run the live sim for responsiveness, but the authoritative,
signable result is produced and signed **server-side**.

## 1. Anti-impersonation auth (nonce challenge → wallet signs → server verifies)
- Client: `src/net/auth.ts` `getSessionToken()` builds a login message, asks the
  wallet to `personal_sign` it, and POSTs `{wallet, message, signature}` to the
  **`auth`** edge function.
- Server (`supabase/functions/auth`): recovers the address from the signature
  (`ecrecover` over the EIP-191 personal-sign digest) and requires it to equal the
  claimed wallet. On success it returns an **HMAC session token** bound to that
  address (`AUTH_SECRET`, ~6h). Cached in localStorage.
- Every result/settlement call carries this token, so a player **cannot act, join,
  or submit results as a wallet they don't control** — the exact WutCardBoshi fix.

## 2. Server-recorded results (`race-report`)
- After a tournament race, the order (as **wallet addresses**) is POSTed with the
  session token to **`race-report`**.
- Server (`supabase/functions/race-report`): verifies the token → reporter address,
  requires the reporter is a **joined** player, and validates the order is a true
  permutation of the tournament's joined wallets. It writes
  `tournament_standings` and flips the tournament to `status='verified'`.
- **Only `verified` standings can ever be signed for payout.**
- Hardening still to add: full deterministic **re-simulation** of `seed + input log`
  server-side (the engine is deterministic) to reject impossible race states
  outright. The auth binding + permutation check already block impersonation and
  unauthenticated/foreign submissions; re-sim closes self-collusion on the exact
  finishing order.

## 3. Signed payouts (`tourney-sign`) — the referee
- Server (`supabase/functions/tourney-sign`): auth-gated. Reads the **server-stored
  verified standings** (never the caller's claim), computes the podium split of the
  pot, and signs with **`RESULT_SIGNER_KEY`** (secp256k1, RFC-6979):
  - `shibkart` kind → `keccak256(abi.encode(contract, chainId, id, address[] winners, uint96[] amounts))`
    → `finalize(...)`.
  - `wut` kind → `keccak256(abi.encode(chainId, contract, id, winner))` → `claimPrize(...)`.
- The contract verifies `ecrecover(...) == resultSigner`, so **no client can forge a
  win or payout** — only the server's signature over verified standings pays out.

## What maz must set up
**Supabase → Edge Functions → Secrets:**
```
AUTH_SECRET                 = <random long string>              # session-token HMAC
RESULT_SIGNER_KEY           = <hex private key, no 0x>          # the resultSigner
TOURNAMENT_CONTRACT         = 0x<deployed tournament address>
CHAIN_ID                    = <chain id, e.g. 109 Shibarium>
TOURNAMENT_KIND             = wut | shibkart
SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY                          # auto-available
```
- The **address** of `RESULT_SIGNER_KEY` must be the contract's `resultSigner`
  (constructor arg for `ShibKartTournament`, or the existing WutTournament's signer).
- Apply `supabase/schema.sql` (tables + RLS). Writes go through the service role in
  the edge functions; anon is read-only.

**Deploy:**
```
supabase functions deploy auth
supabase functions deploy race-report
supabase functions deploy tourney-sign
```

## Trust boundary summary
| Concern | Who is authoritative |
|---|---|
| Live race motion (feel) | client host (cosmetic; re-checked before it counts) |
| Identity / who you are | **server** (signed-message session token) |
| Final standings | **server** (`race-report`, verified) |
| Payout signature | **server** (`tourney-sign`, `RESULT_SIGNER_KEY`) |
| On-chain payout | **contract** (verifies signer == resultSigner) |
