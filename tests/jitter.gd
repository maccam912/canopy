extends SceneTree
## Measure high-frequency shaking in a grown forest, with parts of the coupling switched off.
##   godot --headless --fixed-fps 60 --script res://tests/jitter.gd -- <seed> <grow_minutes> <mode>
## mode: all | nogrips | nologs | nogusts | none

var world: World
var frames := 0
var phase := 0
var grow_frames := 0
var prev := {}
var prev2 := {}
var jit := {}
var samples := 0
var living_falls := 0
var mode := "all"
var trace_plant: Plant
var ljit := {}
var lsamp := {}
var prev_r := {}
var prev2_r := {}


func _process(_d: float) -> bool:
	if world == null:
		var args := OS.get_cmdline_user_args()
		var sd := int(args[0]) if args.size() > 0 else 5
		var minutes := float(args[1]) if args.size() > 1 else 10.0
		mode = args[2] if args.size() > 2 else "all"
		world = World.new()
		root.add_child(world)
		world.setup(sd)
		world.sow_starters()
		world.speed = 8.0
		grow_frames = int(minutes * 60.0 * 60.0 / 8.0)
		world.happened.connect(func(k: String, d: Dictionary) -> void:
			if phase == 1 and k == "fall" and d.alive and not d.snip:
				living_falls += 1)
		return false
	frames += 1
	if phase == 0 and frames >= grow_frames:
		phase = 1
		frames = 0
		world.speed = 1.0
		world.debug_no_grips = mode in ["nogrips", "none"]
		world.debug_no_log_push = mode in ["nologs", "none"]
		world.debug_no_gusts = mode in ["nogusts", "none"]
		world.debug_no_grow = true
		if world.debug_no_gusts:
			world.gust_power = 0.0
		if world.debug_no_grips:
			world.braces = world.braces.filter(func(b: World.Brace) -> bool: return not b.grip)
	if phase == 2:
		var p := trace_plant
		if p.removed:
			return true
		var line := "%3d " % frames
		for j in [0, p.n / 4, p.n / 2, 3 * p.n / 4, p.n - 1]:
			line += "| j%-2d d%+.4f v%+.3f s%.2f " % [j, p.defl[j], p.dvel[j], p.strain[j]]
		line += "| tip %.2f,%.2f awake %s" % [p.bx[p.n - 1], p.by[p.n - 1], p.awake]
		print(line)
		return frames >= 90
	if phase == 1 and frames > 60:
		# Second difference of every segment tip: zero for steady sway, large for shaking.
		samples += 1
		for p in world.plants:
			if p.removed or not p.alive:
				continue
			var key := p
			var tipy := p.n - 1
			var now := Vector2(p.bx[tipy], p.by[tipy])
			if prev.has(key) and prev2.has(key):
				var acc: Vector2 = now - 2.0 * prev[key] + prev2[key]
				jit[key] = jit.get(key, 0.0) + acc.length()
			prev2[key] = prev.get(key, now)
			prev[key] = now
		for l in world.logs:
			var now2 := l.position
			if prev.has(l) and prev2.has(l):
				var acc2: Vector2 = now2 - 2.0 * prev[l] + prev2[l]
				if l.age > 8.0:
					lsamp[l] = lsamp.get(l, 0) + 1
					ljit[l] = ljit.get(l, 0.0) + acc2.length() + absf(l.rotation - 2.0 * prev_r[l] + prev2_r[l]) * l.length * 0.5
				else:
					pass
			prev2[l] = prev.get(l, now2)
			prev[l] = now2
			prev2_r[l] = prev_r.get(l, l.rotation)
			prev_r[l] = l.rotation
	if phase == 1 and frames >= 60 + 2400:
		var vals := []
		var gripped := 0
		var touched := 0
		for p: Plant in jit:
			if p.removed:
				continue
			vals.append([jit[p] / samples * 60.0, p])
		vals.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var total := 0.0
		for v: Array in vals:
			total += v[0]
		var braced := {}
		for b in world.braces:
			braced[b.a] = "grip" if b.grip else "brace"
			if b.tie:
				braced[b.b] = "host"
		var lv := []
		for l: Variant in ljit.keys():
			if is_instance_valid(l):
				lv.append(ljit[l] / maxf(lsamp.get(l, 1), 1) * 60.0)
		lv.sort()
		lv.reverse()
		var detail := []
		for l: Variant in ljit.keys():
			if is_instance_valid(l):
				detail.append([ljit[l] / maxf(lsamp.get(l, 1), 1) * 60.0, l])
		detail.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for k in mini(6, detail.size()):
			var lb: LogBody = detail[k][1]
			var thick := 0.0
			for i in lb.segs.size() / LogBody.STRIDE:
				thick = maxf(thick, lb.segs[i * LogBody.STRIDE + 4])
			print("    log %7.1f  len %4.0f mass %7.0f r %.1f shapes %d  touching %.2f sleeping %s hinged %s  age %.0f  y %.0f  contacts %d" % [detail[k][0], lb.length, lb.mass, thick, lb.get_child_count() - 1, lb.touching, lb.sleeping, lb.joint.is_valid(), lb.age, lb.position.y, lb.get_contact_count()])
		print("   logs %d  jitter (top 5): %s" % [lv.size(), str(lv.slice(0, 5)).replace(", ", " ").left(90)])
		print("mode %-8s plants %3d  mean jitter %7.2f  worst %7.2f  living falls in 20s: %d  grips %d" % [mode, vals.size(), total / maxf(vals.size(), 1), vals[0][0] if vals.size() > 0 else 0.0, living_falls, world.braces.size()])
		if vals.size() > 0 and OS.get_cmdline_user_args().has("trace"):
			trace_plant = vals[0][1]
			phase = 2
			frames = 0
			return false
		for k in mini(6, vals.size()):
			var p: Plant = vals[k][1]
			print("    %7.2f  h %4.0f n %2d r0 %.1f strain %.2f  %s" % [vals[k][0], p.height, p.n, p.rad[0], p.max_strain, braced.get(p, "")])
		return true
	return false
