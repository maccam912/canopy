extends SceneTree
## Exercise the transition from overlapping growth to solid fallen wood in Rapier.

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("TEST FAIL: ", what)


func _initialize() -> void:
	call_deferred("_run")


func _trunk(world: World, x: float) -> Plant:
	var p := world.add_plant(Genome.random(world.rng), x, 0.0)
	p.slen[0] = 200.0
	p.rad[0] = 16.0
	p.rest[0] = 0.0
	p.pose()
	p._measure()
	p.awake = false
	return p


func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.setup(1)
	world.debug_no_grow = true
	world.debug_no_gusts = true
	world.debug_no_grips = true

	var cut := _trunk(world, 500.0)
	var neighbor := _trunk(world, 510.0)
	var log := world.snip(cut, 0, 0.0, -0.001)
	for i in 5:
		await physics_frame
	check(log.overlapping_wood.has(neighbor.body),
		"a cut starts with a collision exception for the trunk it already intersects")
	check(absf(log.position.x - 500.0) < 1.0 and is_zero_approx(neighbor.efx[0]),
		"the pre-existing overlap shoves neither the log nor its neighbor")

	log.position = Vector2(440.0, -130.0)
	log.rotation = 0.0
	log.linear_velocity = Vector2.ZERO
	log.angular_velocity = 0.0
	for i in 3:
		await physics_frame
	check(not log.overlapping_wood.has(neighbor.body),
		"the collision exception clears once the log is out of the trunk")
	log.linear_velocity = Vector2(220.0, 0.0)
	for i in 35:
		await physics_frame
		if absf(neighbor.efx[0]) > 100.0:
			break
	check(neighbor.efx[0] > 100.0, "a fresh hit pushes the trunk in the direction the log was traveling")

	# Saved jars can contain intersecting logs, and restore them on the same tick.
	var state := world.save_state()
	var saved_log: Dictionary = state.logs[0]
	state.logs.append(saved_log.duplicate(true))
	world.queue_free()
	await process_frame
	world = World.new()
	root.add_child(world)
	world.setup(1, 1500.0, 540.0, state)
	for i in 4:
		await physics_frame
	var a := world.logs[0]
	var b := world.logs[1]
	var suppressed := a.get_collision_exceptions().has(b) or b.get_collision_exceptions().has(a)
	check(suppressed and a.position.distance_to(b.position) < 1.0,
		"two intersecting logs loaded together wait for clearance")
	print("WOOD_CONTACTS_PASS" if failures == 0 else "WOOD_CONTACTS_FAILED")
	quit(failures)
