extends Node
## Global signal bus. Gameplay emits here; telemetry, UI and difficulty listen.
## Gameplay code never references the listeners directly.

signal shot_fired(shooter: Node)
signal enemy_hit(enemy: Node, damage: float)
signal enemy_killed(enemy: Node)
signal player_damaged(amount: float, health_left: float)
signal player_died
signal wave_started(index: int)
signal wave_ended(index: int)
