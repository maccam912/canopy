extends SceneTree
## Exercise the Planting menu against a monoculture in the second home.

const MAIN := preload("res://game/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("TEST FAIL: ", what)


func _run() -> void:
	var game := MAIN.instantiate()
	game.smoke = true  # Skip the player's save when building the test scene.
	root.add_child(game)
	game.smoke = false
	game.homes[0].state = game.world.save_state()
	var jar := var_to_bytes(game.homes[0].state)
	game.homes.append({"kind": "tank", "state": {}})
	game.home = 1
	game._build("tank", {}, 11)
	var tank: World = game.world
	tank.set_physics_process(false)
	var g := Genome.make(World.STARTER_HABITS[1], 0.3)
	var known := tank.shapes.found(g, 8.0, -1, tank.rng)
	for i in 12:
		tank.add_plant(g, 200.0 + i * 125.0, 80.0)
	var original := tank.plants.duplicate()
	var seed := tank.spawn_seed(g, 250.0, -80.0, 0.0, 0.0, null)
	tank.soil.wet[20] = 0.8
	game.unlocked.jar = true
	game.pocket.append([g, 0, 1])
	game.records.falls = 10

	var menu: PopupMenu = game.hud.planting_menu.get_popup()
	menu.id_pressed.emit(0)
	var distinct := tank.plants.size() == original.size() + 6
	for i in range(original.size(), tank.plants.size()):
		for j in i:
			if tank.plants[i].genome.distance(tank.plants[j].genome) < Shapes.RADIUS:
				distinct = false
	check(distinct, "adding varieties introduces six genetically distinct seedlings")
	check(game.world == tank and tank.plants.slice(0, original.size()) == original
		and tank.seeds.has(seed) and is_equal_approx(tank.soil.wet[20], 0.8),
		"adding varieties keeps the plants, seeds, and soil in the existing home")
	tank.max_plants = tank.plants.size()
	check(tank.sow_diverse(6) == 0, "planting respects the population limit")

	var dialog: ConfirmationDialog = game.hud.reset_dialog
	menu.id_pressed.emit(1)
	check(dialog.visible and dialog.title == "Reset the Tank?", "the reset prompt identifies the selected home")
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	await process_frame
	check(game.world == tank and not dialog.visible, "canceling a reset keeps the old forest")
	game._on_event("lid_held", {"plant": original[0]})
	menu.id_pressed.emit(1)
	dialog.get_ok_button().pressed.emit()
	for i in 100:
		await process_frame
	var fresh: World = game.world
	check(fresh != tank and fresh.kind == "tank" and game.home == 1 and fresh.jar_w == 2100.0,
		"confirming a reset rebuilds the current home in the same shelf slot")
	check(fresh.plants.size() == 16 and fresh.time < 2.0 and fresh.seeds.is_empty() and fresh.soil.wet[20] == 0.0,
		"the replacement has a wider planting and starts with fresh soil")

	var saved: Dictionary = bytes_to_var(var_to_bytes(game._save_data()))
	check(saved.home == 1 and var_to_bytes(saved.homes[0].state) == jar,
		"the saved shelf keeps the other home's original state")
	check(saved.homes[1].state.plants.size() == 16 and saved.homes[1].state.shapes[0].name == known.name
		and saved.unlocked.jar and saved.pocket.size() == 1 and saved.records.falls == 10,
		"the save records the replacement and retains discoveries, tools, pocketed seeds and records")
	await create_timer(4.5).timeout
	check(game.homes.size() == 2 and game.world == fresh and not game.moving_home,
		"a pending crack in the old forest cannot move the player out of the reset home")
	print("PLANTING_PASS" if failures == 0 else "PLANTING_FAILED")
	quit(failures)
