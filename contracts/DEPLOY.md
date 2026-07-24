# ShibKartTournament — deploy note

`ShibKartTournament.sol` is a racing-tournament escrow: entry-fee pooling + sponsor
seed + **signed podium payouts** (the match server signs final standings; anyone
submits them via `finalize`). It mirrors WutTournament's signer-settlement so you
reuse the same off-chain result-signing infrastructure (`tourney-sign` edge fn).

## Which contract does ShibKart use?
Config flag `VITE_TOURNAMENT_KIND`:
- `wut` (default) — the already-deployed **WutTournament** (winner-takes-all).
- `shibkart` — this new contract (entry fees + podium split). Deploy it, then set:
  ```
  VITE_TOURNAMENT_KIND=shibkart
  VITE_TOURNAMENT_CONTRACT=0x<deployed address>
  VITE_CHAIN_ID=<chain id>
  ```

## Deploy
1. Constructor arg = `resultSigner` = the public address whose key your Supabase
   `tourney-sign` function signs with (same key/pattern WutTournament uses).
2. Compile with solc ^0.8.20 (Remix / Foundry / Hardhat). Example (Foundry):
   ```
   forge create contracts/ShibKartTournament.sol:ShibKartTournament \
     --constructor-args 0xYOUR_SIGNER --rpc-url $RPC --private-key $PK
   ```
3. Put the address in `VITE_TOURNAMENT_CONTRACT`, set `VITE_TOURNAMENT_KIND=shibkart`.

## Signing (server) — `finalize` message
The server signs `keccak256(abi.encode(contract, chainId, id, winners[], amounts[]))`
as an Ethereum Signed Message. `winners`/`amounts` are the podium split derived from
the off-chain per-map points standings. Sum(amounts) must be ≤ pot.

## Fit note
WutTournament fits **winner-takes-all** racing today with zero new deploys. Use
`shibkart` only if you want entry-fee pools and multi-place (podium) payouts.
