-- Global Arcade leaderboard for Autelia (Supabase).
-- Run once in the Supabase SQL editor.
--
-- The game talks to Supabase with the publishable (anon) key, which is public by design.
-- What protects the table is this file: anyone may read every score and add new ones,
-- nobody may edit or delete them, and only plausible values are accepted.
-- Remove a cheated score by hand from the Supabase dashboard (Table Editor).

create table if not exists public.scores (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 16 and name = btrim(name)),
  score integer not null check (score between 1 and 1000000),
  wave integer not null check (wave between 0 and 1000),
  created_at timestamptz not null default now()
);

-- The game asks for the top 10 by score, oldest first on ties.
create index if not exists scores_top_idx on public.scores (score desc, created_at asc);

alter table public.scores enable row level security;

-- Clients may only read, and insert these three columns (never id or created_at).
revoke all on public.scores from anon, authenticated;
grant select on public.scores to anon, authenticated;
grant insert (name, score, wave) on public.scores to anon, authenticated;

drop policy if exists "Anyone can read scores" on public.scores;
create policy "Anyone can read scores" on public.scores
  for select to anon, authenticated using (true);

drop policy if exists "Anyone can add a score" on public.scores;
create policy "Anyone can add a score" on public.scores
  for insert to anon, authenticated with check (true);
