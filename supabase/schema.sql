-- ShibKart PvP / tournament tables (server-authoritative results).
-- Enable Realtime on the tables you subscribe to. Writes happen via edge functions
-- using the SERVICE ROLE key; lock down anon writes with RLS.

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  chain_tid   bigint,                      -- on-chain tournament id (set when created on-chain)
  sponsor     text,
  pot_bone    numeric default 0,
  status      text default 'open',         -- open | locked | verified | settled
  created_at  timestamptz default now()
);
create table if not exists public.tournament_players (
  tournament_id uuid references public.tournaments(id) on delete cascade,
  address       text not null,             -- authenticated wallet
  joined_at     timestamptz default now(),
  primary key (tournament_id, address)
);
create table if not exists public.tournament_standings (
  tournament_id uuid references public.tournaments(id) on delete cascade,
  place         int not null,
  address       text not null,
  primary key (tournament_id, place)
);

alter table public.tournaments          enable row level security;
alter table public.tournament_players   enable row level security;
alter table public.tournament_standings enable row level security;
-- read-only to anon; all writes go through edge functions (service role bypasses RLS)
create policy "read tournaments"  on public.tournaments          for select using (true);
create policy "read players"      on public.tournament_players   for select using (true);
create policy "read standings"    on public.tournament_standings for select using (true);
