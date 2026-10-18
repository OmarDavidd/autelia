class_name CoopRules
extends RefCounted
## How a co-op run scales with its players: a bigger arena so everyone has room, and a
## bigger crowd of enemies so the challenge keeps up.

const BASE_ARENA := Vector2(1280, 720)
## Each extra player adds this fraction of the base arena per side.
const ARENA_GROWTH := 0.35
## Each extra player adds this fraction of the base spawn rate and enemy cap.
const CROWD_GROWTH := 0.6


static func arena_size(players: int) -> Vector2:
	return (BASE_ARENA * (1.0 + ARENA_GROWTH * maxi(players - 1, 0))).round()


static func crowd(players: int) -> float:
	return 1.0 + CROWD_GROWTH * maxi(players - 1, 0)
