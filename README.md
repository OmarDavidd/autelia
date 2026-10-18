# Autelia

2D top-down survival game built in Godot 4 (GDScript) as the experimental environment for a
thesis on dynamic difficulty adjustment with a hybrid model: a small artificial neural network
predicts the player's next-window performance and a PI controller adjusts difficulty.

The name comes from *autotelic experience* (Csikszentmihalyi's flow theory): an activity
enjoyed for its own sake, which happens when challenge matches skill.

- Engine: Godot 4.7, GL Compatibility renderer
- Difficulty conditions: fixed (rule-based and model-based are planned for the thesis)
- Telemetry: CSV, one row per 30 s wave

See [docs/architecture.md](docs/architecture.md) for the module layout and data flow.

## Running

```sh
godot --path .                                            # play
godot --path . -- --seed=2026 --difficulty=0.7 --participant=P01
godot --path . -- --mute                                  # no sound
```

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Mouse + left click | Aim and shoot |
| R | Restart after dying |
| F3 | Researcher panel: difficulty slider, seed, live window stats |
| F12 | Save a screenshot |

Telemetry is written to `user://telemetry/<participant>_<session>.csv`
(Linux: `~/.local/share/godot/app_userdata/Autelia/telemetry/`), one row per wave.

## Tests and captures

```sh
godot --headless --path . tests/smoke_stage1.tscn         # one per stage: 1-5, 7, plus smoke_sound
godot --path . tools/capture/capture.tscn -- etapa7-alta  # thesis screenshots
python3 tools/sfx/generate_sfx.py                         # regenerate assets/audio/*.wav
```
