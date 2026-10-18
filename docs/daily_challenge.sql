-- Daily challenge leaderboard for Autelia (Supabase).
-- Run once in the Supabase SQL editor, after docs/leaderboard.sql.
--
-- Same rules as the Arcade table: anyone may read every score and add new ones, nobody may
-- edit or delete them, and only plausible values are accepted. `day` is the player's local
-- date of the challenge; inserts are only accepted for days within one day of today (UTC),
-- so nobody can post into a past or future challenge.

create table if not exists public.daily_scores (
  id uuid primary key default gen_random_uuid(),
  day date not null,
  name text not null check (char_length(name) between 3 and 16 and name = btrim(name)),
  score integer not null check (score between 1 and 1000000),
  wave integer not null check (wave between 0 and 1000),
  created_at timestamptz not null default now()
);

-- The game asks for one day's best scores, oldest first on ties.
create index if not exists daily_scores_day_top_idx
  on public.daily_scores (day, score desc, created_at asc);

alter table public.daily_scores enable row level security;

-- Clients may only read, and insert these four columns (never id or created_at).
revoke all on public.daily_scores from anon, authenticated;
grant select on public.daily_scores to anon, authenticated;
grant insert (day, name, score, wave) on public.daily_scores to anon, authenticated;

drop policy if exists "Anyone can read daily scores" on public.daily_scores;
create policy "Anyone can read daily scores" on public.daily_scores
  for select to anon, authenticated using (true);

drop policy if exists "Anyone can add a score to a current challenge" on public.daily_scores;
create policy "Anyone can add a score to a current challenge" on public.daily_scores
  for insert to anon, authenticated
  with check (day between (now() at time zone 'utc')::date - 1 and (now() at time zone 'utc')::date + 1);
