extends SceneTree
## Grow a forest unattended and print what happened. Usage:
##   godot --headless --fixed-fps 60 --script res://tests/soak.gd -- <minutes> <speed> <seed> [swing]

var world: World
var frames := 0
var limit := 0
var next_report := 60.0
var t0 := 0
var cascades := []


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var minutes := float(args[0]) if args.size() > 0 else 10.0
	var speed := float(args[1]) if args.size() > 1 else 8.0
	var sd := int(args[2]) if args.size() > 2 else 1
	world = World.new()
	root.add_child(world)
	world.setup(sd)
	world.sow_starters()
	world.speed = speed
	if args.size() > 3 and args[3] == "swing":
		world.sun_vel = 0.02
	elif args.size() > 3:
		world.sun_phi = float(args[3])
	world.happened.connect(_on_event)
	limit = int(minutes * 60.0 * 60.0 / speed)
	t0 = Time.get_ticks_msec()


func _on_event(kind: String, data: Dictionary) -> void:
	if kind == "new_shape":
		print("  [%5.0fs] new shape: %s  %s" % [world.time, data.shape.name, _fmt(data.shape.h)])
	elif kind == "cascade_end" and data.count >= 2:
		cascades.append(data.count)
	elif kind == "lid":
		print("  [%5.0fs] touched the lid" % world.time)


func _fmt(h: PackedFloat32Array) -> String:
	var s := ""
	for v in h:
		s += "%.1f " % v
	return s


func _process(_delta: float) -> bool:
	if world == null:
		_start()
	frames += 1
	if world.time >= next_report:
		next_report += 60.0
		var alive := 0
		var tall := 0.0
		var mean := 0.0
		var segs := 0
		var awake := 0
		var kinds := {}
		var strain := 0.0
		for p in world.plants:
			segs += p.n
			if p.awake:
				awake += 1
			if p.alive:
				alive += 1
				mean += p.height
				tall = maxf(tall, p.height)
				strain = maxf(strain, p.max_strain)
				if p.height > 40.0:
					kinds[p.species] = kinds.get(p.species, 0) + 1
		var rest := 0
		var dark := 0
		var taken := 0
		for sd in world.seeds:
			if sd.resting:
				rest += 1
				var c := world.soil.col(sd.x)
				if world.occupied[c] > 0:
					taken += 1
				elif world.soil.light[c] < lerpf(0.3, 0.05, sd.genome.h[Genome.THRIFT]):
					dark += 1
		print("     seeds resting %d  blocked-by-plant %d  too-dark %d" % [rest, taken, dark])
		var rich := 0.0
		for r in world.soil.rich:
			rich += r
		print("[%5.0fs] alive %3d/%3d  tall %4.0f mean %4.0f  segs %4d awake %3d  logs %2d seeds %3d  falls %3d best %2d  shapes %d (%d standing)  rich %.2f  strain %.2f  %.1fms/f" % [
			world.time, alive, world.plants.size(), tall, mean / maxf(alive, 1), segs, awake, world.logs.size(), world.seeds.size(),
			world.count_falls, world.best_cascade, world.shapes.list.size(), kinds.size(), rich / world.soil.n / T.RICH0, strain,
			float(Time.get_ticks_msec() - t0) / frames])
	if frames >= limit:
		print("cascades: ", cascades)
		for s in world.shapes.list:
			print("  %-18s alive %3d total %4d tallest %4.0f  %s" % [s.name, s.alive, s.total, s.tallest, _fmt(s.h)])
		print("SOAK_DONE born %d died %d rotted %d falls %d" % [world.count_born, world.count_died, world.count_rotted, world.count_falls])
		return true
	return false
