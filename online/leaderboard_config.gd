class_name LeaderboardConfig
extends RefCounted
## Supabase project behind the global Arcade leaderboard (see docs/leaderboard.sql).
## The publishable (anon) key is public by design: Row Level Security only lets it read
## scores and insert new ones. Never put the secret (service_role) key here.
## Empty values keep the game offline: runs work and the table shows an error.

const URL := ""
const KEY := ""
