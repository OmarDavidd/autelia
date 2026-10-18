# Autelia

2D top-down survival game built in Godot 4 (GDScript) as the experimental environment for a
thesis on dynamic difficulty adjustment with a hybrid model: a small artificial neural network
predicts the player's next-window performance and a PI controller adjusts difficulty.

The name comes from *autotelic experience* (Csikszentmihalyi's flow theory): an activity
enjoyed for its own sake, which happens when challenge matches skill.

- Engine: Godot 4.7, GL Compatibility renderer
- Conditions: fixed, rules, ANN–PI
- Telemetry: CSV per 20–30 s window

See [docs/architecture.md](docs/architecture.md) for the module layout and data flow.
