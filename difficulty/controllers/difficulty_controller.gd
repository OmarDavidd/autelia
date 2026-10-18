class_name DifficultyController
extends RefCounted
## Decides the difficulty of the next window from the stats of the window that just closed.
## Experimental conditions (fixed, rules, model-based) are subclasses with the same interface.


## Short name written to the telemetry `condition` column.
func label() -> String:
	return "base"


func next_difficulty(_window: Dictionary, current: float) -> float:
	return current
