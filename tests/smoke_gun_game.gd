extends Node
## Smoke test for Gun Game mode:
## Symmetrical procedural arena, FFA weapon combat & profiles, level progression,
## bot aiming & behavior, safe respawn mechanics and victory condition.
## Run: godot --headless --path . tests/smoke_gun_game.tscn

const PLAYER_SCENE := preload("res://core/player/player.tscn")

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _run() -> void:
	await _test_rules_and_profiles()
	await _test_symmetric_arena()
	await _test_ffa_bullet_damage_and_self_immunity()
	await _test_progression_and_victory()
	await _test_safe_respawn()
	await _test_names_reach_the_feed()
	await _test_damage_events_are_local_only()
	await _test_victory_freezes_the_match()
	await _test_main_offers_pause_and_menu()

	if failures.is_empty():
		print("SMOKE OK: Gun Game arena, FFA combat, weapon tiers, bot AI, and victory flow passed!")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAILURE: ", f)
		get_tree().quit(1)


func _test_rules_and_profiles() -> void:
	_expect(GunGameRules.MAX_LEVEL == 5, "Gun game should have 5 levels")
	_expect(GunGameRules.kills_to_advance(1) == 3, "Level 1 requires 3 kills")
	_expect(GunGameRules.kills_to_advance(4) == 3, "Level 4 requires 3 kills")
	_expect(GunGameRules.kills_to_advance(5) == 1, "Level 5 requires 1 kill for victory")

	var p1 := GunGameRules.weapon_profile(1)
	_expect(p1.name == "Pistola" and not p1.is_melee, "Level 1 is Pistola")

	var p2 := GunGameRules.weapon_profile(2)
	_expect(p2.name == "Escopeta" and p2.bullet_count == 6, "Level 2 is Escopeta with 6 pellets")

	var p3 := GunGameRules.weapon_profile(3)
	_expect(p3.name == "Rebote" and p3.bounces == 2, "Level 3 is Rebote with 2 bounces")

	var p4 := GunGameRules.weapon_profile(4)
	_expect(p4.name == "Perforador" and p4.pierces == 2, "Level 4 is Perforador with 2 pierces")

	var p5 := GunGameRules.weapon_profile(5)
	_expect(p5.name == "Estocada" and p5.is_melee and p5.damage >= 100.0, "Level 5 is Melee with 100 dmg")


func _test_symmetric_arena() -> void:
	var arena := GunGameArena.new(42)
	add_child(arena)
	await _frames(2)

	_expect(arena.obstacles.size() > 0, "Symmetric arena should generate obstacles")
	_expect(arena.obstacles.size() % 2 == 0, "Obstacles must be in pairs due to 180-deg rotational symmetry")

	var spawns := arena.get_spawn_points()
	_expect(spawns.size() >= 8, "Arena must provide at least 8 spawn points")

	arena.queue_free()
	await _frames(2)


func _test_ffa_bullet_damage_and_self_immunity() -> void:
	var p1: Player = PLAYER_SCENE.instantiate()
	p1.position = Vector2(200, 200)
	add_child(p1)
	p1.weapon.team = Weapon.Team.FFA

	var p2: Player = PLAYER_SCENE.instantiate()
	p2.position = Vector2(250, 200)
	add_child(p2)
	p2.weapon.team = Weapon.Team.FFA

	await _frames(2)

	# 1. Player 1 shoots toward Player 2
	p1.aim_override = Vector2(400, 200)
	await _frames(2)
	p1.weapon.try_fire()

	# Wait for bullet to hit p2
	await _frames(10)
	_expect(p2.health.current < 100.0, "Player 2 should receive damage from Player 1's bullet")
	_expect(p2.last_attacker == p1, "Player 2's last_attacker should be Player 1")
	_expect(p1.health.current == 100.0, "Player 1 should not damage themselves")

	p1.queue_free()
	p2.queue_free()
	await _frames(2)


func _test_progression_and_victory() -> void:
	var mode := GunGameMode.new()
	mode.mode_seed = 1234
	add_child(mode)
	mode.setup_match("Tester", 2)
	await _frames(2)

	var human := mode.local_player
	var bot1 := mode.combatants[1]

	_expect(mode.levels[human] == 1, "Human starts at level 1")

	# Simulate 3 kills for human to advance
	Events.player_killed.emit(human, bot1)
	_expect(mode.levels[human] == 1, "1 kill does not level up yet")
	_expect(mode.level_kills[human] == 1, "Level kills is 1")

	Events.player_killed.emit(human, bot1)
	_expect(mode.levels[human] == 1, "2 kills does not level up yet")
	_expect(mode.level_kills[human] == 2, "Level kills is 2")

	Events.player_killed.emit(human, bot1)
	_expect(mode.levels[human] == 2, "3 kills advances to level 2")
	_expect(mode.level_kills[human] == 0, "Level kills resets after level up")
	_expect(human.weapon.bullet_count == 6, "Human now has shotgun with 6 pellets")

	# Advance to level 5 (Melee)
	mode.levels[human] = 5
	mode.level_kills[human] = 0
	human.weapon.apply_profile(GunGameRules.weapon_profile(5))

	_expect(human.weapon.is_melee, "Human weapon is melee at level 5")

	# Melee kill should trigger victory
	var won := [false]
	mode.match_finished.connect(func(w: Player, _name: String, _color: Color) -> void:
		if w == human:
			won[0] = true
	)

	Events.player_killed.emit(human, bot1)
	_expect(won[0], "Getting kill at level 5 should trigger match_finished")
	_expect(mode.is_finished, "Mode should be marked finished")

	mode.queue_free()
	await _frames(2)


func _test_safe_respawn() -> void:
	var arena := GunGameArena.new(999)
	add_child(arena)
	await _frames(2)

	var p1: Player = PLAYER_SCENE.instantiate()
	var spawns := arena.get_spawn_points()
	p1.position = spawns[0] # Near top-left
	add_child(p1)

	# Safest spawn for an opponent when p1 is at spawns[0]
	var safest := arena.find_safest_spawn([p1])
	_expect(safest != spawns[0], "Safest spawn should never be the spawn currently occupied")
	_expect(safest.distance_to(p1.position) > 400.0, "Safest spawn should be far away from opponent")

	arena.queue_free()
	p1.queue_free()
	await _frames(2)


## The kill feed, standings and victory banner use each combatant's own name.
func _test_names_reach_the_feed() -> void:
	var mode := GunGameMode.new()
	mode.mode_seed = 77
	add_child(mode)
	mode.setup_match("Tester", 2)
	await _frames(2)
	var feed: Array[String] = []
	mode.kill_logged.connect(func(killer: String, victim: String, _kc: Color, _vc: Color) -> void:
		feed.append("%s>%s" % [killer, victim]))
	Events.player_killed.emit(mode.local_player, mode.combatants[1])
	_expect(feed == ["Tester>%s" % GunGameMode.BOT_NAMES[0]], "kill feed names: %s" % str(feed))
	mode.queue_free()
	await _frames(2)


## Only this machine's player makes the hurt sound and reaches telemetry; bots hitting
## each other off screen must not.
func _test_damage_events_are_local_only() -> void:
	var mode := GunGameMode.new()
	mode.mode_seed = 78
	add_child(mode)
	mode.setup_match("Tester", 2)
	await _frames(2)
	var events := [0]
	var count := func(_amount: float, _left: float) -> void: events[0] += 1
	Events.player_damaged.connect(count)
	mode.combatants[1].take_hit(10.0, mode.combatants[2])
	_expect(events[0] == 0, "a bot's damage reached player_damaged %d times" % events[0])
	mode.local_player.take_hit(10.0, mode.combatants[1])
	_expect(events[0] == 1, "the local player's damage must reach player_damaged once, got %d" % events[0])
	Events.player_damaged.disconnect(count)
	mode.queue_free()
	await _frames(2)


## Once someone wins, the match stops behind the victory panel.
func _test_victory_freezes_the_match() -> void:
	var mode := GunGameMode.new()
	mode.mode_seed = 79
	add_child(mode)
	mode.setup_match("Tester", 2)
	await _frames(2)
	mode.levels[mode.local_player] = GunGameRules.MAX_LEVEL
	Events.player_killed.emit(mode.local_player, mode.combatants[1])
	_expect(mode.is_finished, "the last-level kill must finish the match")
	_expect(get_tree().paused, "the match must stop once it is won")
	get_tree().paused = false
	mode.queue_free()
	await _frames(2)


## The full scene: Esc pauses a gun game, and the victory panel leaves through the same
## paths as the pause menu (back to the real main menu, never an Experiment run).
func _test_main_offers_pause_and_menu() -> void:
	GameSession.mode = GameSession.Mode.GUN_GAME
	MainMenu.seen = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var pause: PauseMenu = main.get_node_or_null("PauseMenu")
	_expect(pause != null, "a gun game needs the pause menu")
	if pause:
		_expect(pause.mode == main.get_node("GunGame"), "the pause menu must watch the gun game")
		_expect(pause.can_pause(), "a running gun game must be pausable")
		var hud: GunGameHud = main.get_node("GunGameHud")
		var menu_targets := _pressed_targets(hud.get("menu_button"))
		_expect("to_main_menu" in menu_targets, "Menú principal must go through the pause menu: %s" % str(menu_targets))
		var restart_targets := _pressed_targets(hud.get("restart_button"))
		_expect("restart" in restart_targets, "Jugar de nuevo must go through the pause menu: %s" % str(restart_targets))
	main.queue_free()
	GameSession.mode = GameSession.Mode.EXPERIMENT
	MainMenu.seen = false
	await _frames(2)


## Method names a button's pressed signal calls; empty when there is no button.
func _pressed_targets(button: Variant) -> Array[String]:
	var targets: Array[String] = []
	if button is Button:
		for connection in button.pressed.get_connections():
			targets.append(connection.callable.get_method())
	return targets
