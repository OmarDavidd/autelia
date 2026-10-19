class_name GunGameRules
extends RefCounted
## Weapon levels and rules for the Gun Game mode.
## Players advance every 2 kills, ending with a melee ink thrust for the win.

const MAX_LEVEL := 5
const KILLS_PER_LEVEL := 3
const FINAL_KILLS_TO_WIN := 1
const COMBATANT_MAX_HEALTH := 50.0

const PROFILES: Dictionary = {
	1: {
		"name": "Pistola",
		"fire_rate": 6.0,
		"bullet_speed": 950.0,
		"damage": 15.0,
		"bullet_count": 1,
		"spread_degrees": 0.0,
		"bounces": 0,
		"pierces": 0,
		"bullet_radius": 5.0,
		"bullet_lifetime": 1.4,
		"is_melee": false,
		"recoil": 0.0,
		"lunge": 0.0,
		"sound_pitch": 1.05,
	},
	2: {
		"name": "Escopeta",
		"fire_rate": 1.6,
		"bullet_speed": 820.0,
		"damage": 11.0,
		"bullet_count": 6,
		"spread_degrees": 30.0,
		"bounces": 0,
		"pierces": 0,
		"bullet_radius": 4.5,
		"bullet_lifetime": 0.45,
		"is_melee": false,
		"recoil": 190.0,
		"lunge": 0.0,
		"sound_pitch": 0.70,
	},
	3: {
		"name": "Rebote",
		"fire_rate": 4.5,
		"bullet_speed": 900.0,
		"damage": 18.0,
		"bullet_count": 1,
		"spread_degrees": 0.0,
		"bounces": 2,
		"pierces": 0,
		"bullet_radius": 6.5,
		"bullet_lifetime": 1.6,
		"is_melee": false,
		"recoil": 0.0,
		"lunge": 0.0,
		"sound_pitch": 1.35,
	},
	4: {
		"name": "Perforador",
		"fire_rate": 1.0,
		"bullet_speed": 1250.0,
		"damage": 42.0,
		"bullet_count": 1,
		"spread_degrees": 0.0,
		"bounces": 0,
		"pierces": 2,
		"bullet_radius": 10.0,
		"bullet_lifetime": 1.4,
		"is_melee": false,
		"recoil": 260.0,
		"lunge": 0.0,
		"sound_pitch": 0.55,
	},
	5: {
		"name": "Estocada",
		"fire_rate": 1.5,
		"bullet_speed": 650.0,
		"damage": 100.0,
		"bullet_count": 1,
		"spread_degrees": 0.0,
		"bounces": 0,
		"pierces": 0,
		"bullet_radius": 36.0,
		"bullet_lifetime": 0.14,
		"is_melee": true,
		"recoil": 0.0,
		"lunge": 420.0,
		"sound_pitch": 1.45,
	},
}


static func kills_to_advance(level: int) -> int:
	if level >= MAX_LEVEL:
		return FINAL_KILLS_TO_WIN
	return KILLS_PER_LEVEL


static func weapon_profile(level: int) -> Dictionary:
	return PROFILES.get(clampi(level, 1, MAX_LEVEL), PROFILES[1])


static func weapon_name(level: int) -> String:
	return str(weapon_profile(level).get("name", "Arma"))
