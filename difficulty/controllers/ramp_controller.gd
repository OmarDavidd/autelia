class_name RampController
extends DifficultyController
## Arcade: every wave is harder than the last, whatever the player does.
## Starts easy and reaches the maximum at wave 11, then stays there.

const START := 0.3
const STEP := 0.07


func label() -> String:
	return "ramp"


func next_difficulty(_window: Dictionary, current: float) -> float:
	return minf(current + STEP, 1.0)
