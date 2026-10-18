extends Node
## Global signal bus. Gameplay emits here; telemetry, UI and difficulty listen.
## Gameplay code never references the listeners directly.

signal shot_fired(shooter: Node)
signal enemy_hit(enemy: Node, damage: float)
signal enemy_killed(enemy: Node)
signal player_damaged(amount: float, health_left: float)
## The whole team is down: the run is over. With one player, that player died.
signal player_died
## One player fell (co-op: the others may still be standing).
signal player_down(player: Node)
signal player_revived(player: Node)
signal wave_started(index: int)
signal wave_ended(index: int)
