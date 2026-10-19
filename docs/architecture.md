# Autelia architecture

A 2D top-down wave survival game. Besides being playable, it is built as a controlled
environment: runs are reproducible from a seed, difficulty is a single value, and gameplay is
measured per wave.

## Event flow

```
core/ and modes/ ──emit──▶ Events (autoload) ──▶ HUD · Sfx · Telemetry · Difficulty
```

Gameplay code announces what happens (`shot_fired`, `enemy_hit`, `enemy_killed`,
`player_damaged`, `player_died`, `wave_started`, `wave_ended`). Everything else listens and
never changes gameplay in return.

## Folders

| Folder | Owns | Must not know about |
|---|---|---|
| `autoload/` | `Events` signal bus, `DebugTools` (F12 screenshots) | anything else |
| `core/` | player and its input sources (`LocalInput`, `ScriptedInput`, `BotInput`), enemies, combat (weapon, bullet, health), arena, palette and drawing helpers | difficulty, telemetry |
| `modes/` | game rules. `survival/` runs timed waves and owns the run's seeded RNG; `arcade/` keeps the score; `GameSession` holds the mode and name chosen in the menu | how difficulty is chosen |
| `difficulty/` | `DifficultyParams` (d → parameters), `DifficultyDirector`, controllers | gameplay nodes |
| `telemetry/` | `TelemetryRecorder`: one CSV row per wave | gameplay logic |
| `online/` | `Leaderboard`: global Arcade scores on Supabase (REST) | gameplay logic |
| `ui/` | main and pause menus, HUD, touch controls, rotate hint, researcher panel (F3), shared UI style | |
| `audio/` | `Sfx`: plays sounds on events | |
| `tools/` | scripted captures, sound synthesis, test sandbox | |
| `tests/` | smoke tests, run as scenes | |

Dependency rule: `core/` and `modes/` never import `difficulty/`, `telemetry/`, `ui/` or
`audio/`. New game modes can reuse the core without carrying any measurement code.

`main.gd` is the composition root. When the main menu closes it applies the chosen mode:
Experiment leaves the run as is; Arcade and the daily challenge swap in `RampController`, add a `ScoreKeeper`,
shows the score on the HUD and submits it to the `Leaderboard` when the player dies. On
touchscreens it also adds `TouchControls`, which feed the same input actions as the keyboard
and aim through `Player.aim_override`, so the core never knows which device is playing.
The daily challenge also reseeds the run from the day (`GameSession.daily_seed`) and points
the `Leaderboard` at that day's table.

## Players and co-op

A player never reads devices: it asks its `PlayerInput` where to move, where to aim and
whether to shoot. This machine's player uses `LocalInput` (keyboard, mouse, touch sticks);
teammates use `ScriptedInput` (tests, and network messages later) or `BotInput`.

`SurvivalMode.players` holds up to eight players, each in its own color. Enemies chase the
nearest living player and spawn away from every living player. When a player falls,
`Events.player_down` fires; it revives with half health when the next wave starts.
`Events.player_died` keeps its meaning of "the run is over": it fires only when nobody is
left standing, so single-player code and tests are unchanged.

The Cooperativo mode (`modes/coop/`) starts from a `CoopRoom` (invite code and roster, up to
eight). `CoopRules` sizes the arena (`Arena.resize`) and the enemy crowd (`WaveSpawner.crowd`)
by the number of players. A `FollowCamera` keeps this machine's player centered within the
arena, and `TeammateMarkers` point to teammates off screen.

Rooms live on the game server (`server/room_server.gd`, headless entry `server/server.tscn`):
plain WebSocket with one JSON object per message, so one process serves many rooms. It
creates codes, lets players join at any time (also mid-run), hands the host role on and
closes empty rooms; host-only messages (`add_bot`, `start`) from others are ignored. It is
internet-facing behind the tunnel, so it checks every message (type, name, code, size) and
caps peers and rooms. `RoomClient` (`online/`) is this machine's link, kept under the tree
root so it outlives the menu; every room the server sends goes through `CoopRoom.from_dict`.
Without a server, Crear opens a local `CoopRoom` where only bots can join.

## Difficulty

One value `d` in [0, 1] maps linearly to spawn interval, enemy speed, shooter fire rate and
enemy health (`DifficultyParams`); `d = 0.5` is the base tuning. The `DifficultyDirector`
applies it to the spawner, which scales enemies as they spawn, so a change never alters
enemies already on screen.

After each wave the director asks its controller for the next value through
`next_difficulty(window, current)`. `FixedController` (the Experiment mode, the control
condition) never changes it; `RampController` (Arcade) starts at 0.3 and adds 0.07 per wave
up to 1. Other strategies plug in with the same interface.

## Telemetry

Each wave is one measurement window. `TelemetryRecorder` counts the player's shots and hits,
damage dealt and taken, kills, deaths and active time, and appends a row when the wave ends or
the player dies. Columns are listed in `TelemetryRecorder.COLUMNS` and in the README.
Files go to `user://telemetry/` and are never committed.

## Reproducibility

All gameplay randomness goes through the run's seeded `RandomNumberGenerator`. Spawn
positions always use exactly two draws, so the sequence does not depend on where the player
moves. Presentation code (sound pitch variation) uses its own RNG. Timers run on physics time,
not wall-clock time.

## Art and sound

Everything is drawn in code (`Sketch` helpers, `Palette`) and every sound is synthesized by
`tools/sfx/generate_sfx.py`, so there are no third-party assets apart from the Fredoka font
(SIL OFL).
