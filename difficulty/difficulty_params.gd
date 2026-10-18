class_name DifficultyParams
## Maps one difficulty value d in [0, 1] to the parameters it controls.
## d = 0.5 reproduces the base tuning, and every parameter moves linearly with d,
## so each difficulty value is traceable to concrete numbers.

## Value at d = 0 (x) and at d = 1 (y).
const RANGES := {
	"spawn_interval": Vector2(2.0, 0.8),
	"speed_multiplier": Vector2(0.75, 1.25),
	"fire_rate_multiplier": Vector2(0.6, 1.4),
	"health_multiplier": Vector2(0.8, 1.2),
}


static func values(difficulty: float) -> Dictionary:
	var t := clampf(difficulty, 0.0, 1.0)
	var result := {}
	for key: String in RANGES:
		var range_: Vector2 = RANGES[key]
		result[key] = lerpf(range_.x, range_.y, t)
	return result


static func apply(difficulty: float, spawner: WaveSpawner) -> void:
	var tuned := values(difficulty)
	for key: String in tuned:
		spawner.set(key, tuned[key])
