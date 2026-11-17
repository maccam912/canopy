extends SceneTree
## Headless checks of the two rules: light feeds, weight breaks.
##   godot --headless --fixed-fps 60 --script res://tests/sim_test.gd

var world: World
var frames := 0
var stage := 0
var failures := 0
var cut_height := 0.0
var logs_before := 0
var target: Plant


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("TEST FAIL: ", what)


func _light_rules() -> void:
	var l := LightField.new()
	l.begin(0.0, 400.0, 400.0)
	l.deposit(200.0, -300.0, 28.0, 1.0)
	l.deposit(200.0, -100.0, 28.0, 1.0)
	l.deposit(320.0, -100.0, 28.0, 1.0)
	l.solve()
	var top := l.income(200.0, -300.0, 28.0, 1.0)
	var under := l.income(200.0, -100.0, 28.0, 1.0)
	var open := l.income(320.0, -100.0, 28.0, 1.0)
	check(top > 0.0 and absf(top - open) < 0.1 * top, "leaves in open light earn the same")
	check(under < top * 0.8 and under > 0.0, "a shaded leaf earns a trickle, not nothing (%.1f vs %.1f)" % [under, top])
	check(l.sample(200.0, -10.0) < l.sample(60.0, -10.0), "the floor under two leaves is darker than open floor")
	# A low sun throws the shadow sideways.
	l.begin(1.0, 400.0, 400.0)
	l.deposit(200.0, -300.0, 28.0, 1.0)
	l.solve()
	check(l.sample(200.0, -100.0) > 0.95, "with the sun low on the right, straight below a leaf is lit")


func _genome_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var g := Genome.random(rng)
	var c := g.child(rng)
	check(g.distance(c) > 0.0 and g.distance(c) < 0.5, "a seed copies its parent with small nudges")
	var soil := Soil.new()
	soil.setup(500.0, rng)
	var before := soil.rich[10]
	var got := soil.take(105.0, 5.0, 100.0)
	check(got > 0.0 and soil.rich[10] < before, "roots drain the soil they stand in")


func _process(_delta: float) -> bool:
	if world == null:
		_light_rules()
		_genome_rules()
		world = World.new()
		root.add_child(world)
		world.setup(11)
		world.sow_starters()
		world.speed = 8.0
		return false
	frames += 1
	match stage:
		0:
			if world.time >= 150.0:
				var tallest := 0.0
				for p in world.plants:
					if p.alive and p.height > tallest:
						tallest = p.height
						target = p
				check(world.living() >= 8, "the starters are alive after 150 s (%d)" % world.living())
				check(tallest > 120.0, "something has grown tall (%.0f)" % tallest)
				var seen := {}
				for p in world.plants:
					seen[p.species] = true
				check(world.shapes.list.size() >= 3, "at least three shapes have been named (%d)" % world.shapes.list.size())
				var lit := 0.0
				var dark := 1.0
				for v in world.soil.light:
					lit = maxf(lit, v)
					dark = minf(dark, v)
				check(lit > 0.9 and dark < 0.6, "the floor has both open light and shade (%.2f..%.2f)" % [dark, lit])
				# Snip the tallest plant a third of the way up its first segment.
				cut_height = target.height
				logs_before = world.logs.size()
				world.speed = 1.0
				world.snip(target, 0, 0.5)
				stage = 1
				frames = 0
		1:
			if frames == 2:
				check(world.logs.size() == logs_before + 1, "a snip turns the cut part into fallen wood")
				check(target.removed or target.height < cut_height * 0.5, "the snipped plant is shorter")
			if frames >= 420:
				var l := world.logs[world.logs.size() - 1] if not world.logs.is_empty() else null
				check(l != null and l.landed, "the cut wood reached the ground")
				# Weight breaks: lean hard on the stoutest plant until something gives.
				target = null
				for p in world.plants:
					if p.alive and (target == null or p.rad[0] > target.rad[0]):
						target = p
				stage = 2
				frames = 0
		2:
			if not target.removed and target.n > 1:
				var top := target.n - 1
				target.push(top, target.bx[top], target.by[top], 4.0e6 * target.rad[0], 0.0)
			if target.removed or target.falls_survived > 0:
				check(true, "an overloaded trunk snaps or uproots")
				stage = 3
				frames = 0
			elif frames > 600:
				check(false, "an overloaded trunk snaps or uproots")
				stage = 3
		3:
			if frames >= 120:
				var bad := false
				for r in world.soil.rich:
					if is_nan(r) or r < 0.0:
						bad = true
				for p in world.plants:
					for i in p.n:
						if is_nan(p.bx[i]) or is_nan(p.defl[i]):
							bad = true
				check(not bad, "no NaNs or negative soil after a fall")
				print("SIM_PASS" if failures == 0 else "SIM_FAILED %d" % failures)
				return true
	return false
