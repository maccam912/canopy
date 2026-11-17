class_name Visitors
extends RefCounted
## Small creatures that move in when the forest offers what they need. Each one
## nudges a loop, and none can be controlled.
##
##   Fireflies  a fresh gap while the sun is low   gather where light reaches the floor
##   Beetles    rotting wood                       speed up rot where they settle
##   Birds      a tall standing crown              carry heavy seeds across the jar
##   Squirrel   plants with plump seeds            buries seeds; some sprout far away
##   Owl        a trunk that has stood a long time leaves just before its tree falls

enum { FIREFLY, BEETLE, BIRD, SQUIRREL, OWL }


class Visitor:
	var kind := 0
	var pos := Vector2()
	var vel := Vector2()
	var goal := Vector2()
	var state := ""            # what it is doing now
	var t := 0.0               # seconds in this state
	var life := 60.0           # biological seconds before it leaves of its own accord
	var plant: Plant           # perch, or the plant it is visiting
	var seg := -1
	var log_body: LogBody
	var along := 0.5           # beetle: place along its log
	var carrying: Genome
	var carry_species := -1
	var source_id := -1        # bird: the plant it is fetching a seed from
	var phase := 0.0
	var face := 1.0
	var hue := 0.15


var world: World
var list: Array[Visitor] = []
var check := 0.0
var light_then := PackedFloat32Array()   # floor light a while ago, to spot fresh gaps
var light_age := 0.0
var counts := [0, 0, 0, 0, 0]


func _init(w: World) -> void:
	world = w


## dt: real seconds (movement stays calm at any speed); bdt: forest seconds.
func step(dt: float, bdt: float) -> void:
	light_age += bdt
	if light_then.size() != world.soil.n or light_age > 45.0:
		light_then = world.soil.light.duplicate()
		light_age = 0.0
	check += bdt
	if check > 2.0:
		check = 0.0
		_arrivals()
	var i := list.size() - 1
	while i >= 0:
		var v := list[i]
		v.t += dt
		v.life -= bdt
		var keep := true
		match v.kind:
			FIREFLY:
				keep = _firefly(v, dt)
			BEETLE:
				keep = _beetle(v, dt)
			BIRD:
				keep = _bird(v, dt)
			SQUIRREL:
				keep = _squirrel(v, dt)
			OWL:
				keep = _owl(v, dt)
		if not keep:
			counts[v.kind] -= 1
			if v.log_body != null and is_instance_valid(v.log_body):
				v.log_body.beetles = maxf(0.0, v.log_body.beetles - 0.6)
			list[i] = list[list.size() - 1]
			list.pop_back()
		i -= 1


func _add(kind: int, at: Vector2) -> Visitor:
	var v := Visitor.new()
	v.kind = kind
	v.pos = at
	v.phase = world.rng.randf() * TAU
	list.append(v)
	counts[kind] += 1
	return v


func _arrivals() -> void:
	var rng := world.rng
	var low_sun := absf(world.sun_phi) > 0.8
	# Fireflies: a column of floor that has just come into the light, while the sun is low.
	if low_sun and counts[FIREFLY] < 28:
		for c in range(2, world.soil.n - 2):
			if world.soil.light[c] > 0.55 and light_then[c] < 0.25 and rng.randf() < 0.08:
				var x := (c + 0.5) * Soil.CW
				var swarm := rng.randi_range(5, 9)
				for k in swarm:
					var v := _add(FIREFLY, Vector2(x + rng.randf_range(-30, 30), world.soil.ground_y(x) - rng.randf_range(10, 70)))
					v.goal = Vector2(x, world.soil.ground_y(x) - 30.0)
					v.life = rng.randf_range(50.0, 90.0)
				world.happened.emit("visitor", {"kind": "fireflies", "x": x, "y": world.soil.ground_y(x)})
				light_then[c] = 1.0
				break
	# Beetles: rotting wood that has lain a while.
	if counts[BEETLE] < 14:
		for l in world.logs:
			if l.landed and l.rot > 0.12 and l.rot < 0.85 and l.beetles < 1.0 and l.volume > 300.0 and rng.randf() < 0.05:
				for k in rng.randi_range(2, 3):
					var v := _add(BEETLE, l.position)
					v.log_body = l
					v.along = rng.randf()
					v.face = 1.0 if rng.randf() < 0.5 else -1.0
					v.life = 1e9
				l.beetles += 1.6
				world.happened.emit("visitor", {"kind": "beetles", "x": l.position.x, "y": l.position.y})
				break
	# Birds: a tall standing crown to sit in.
	if counts[BIRD] < 2 and rng.randf() < 0.12:
		var crown := _tallest(world.jar_h * 0.5)
		if crown != null:
			var v := _add(BIRD, Vector2(-60.0 if rng.randf() < 0.5 else world.jar_w + 60.0, world.lid_y + rng.randf_range(40, 160)))
			v.plant = crown
			v.seg = _top_seg(crown)
			v.state = "arrive"
			v.life = rng.randf_range(80.0, 160.0)
			v.hue = rng.randf_range(0.0, 1.0)
			world.happened.emit("visitor", {"kind": "bird", "x": v.pos.x, "y": v.pos.y})
	# Squirrel: plump seeds on the ground or on a plant.
	if counts[SQUIRREL] < 1 and rng.randf() < 0.08:
		var source: Plant = null
		for p in world.plants:
			if p.alive and not p.removed and p.mature and p.genome.h[Genome.SEED] > 0.62 and p.height > 60.0:
				source = p
				break
		if source != null:
			var left := rng.randf() < 0.5
			var x := -30.0 if left else world.jar_w + 30.0
			var v := _add(SQUIRREL, Vector2(x, world.soil.ground_y(clampf(x, 0.0, world.jar_w))))
			v.plant = source
			v.state = "seek"
			v.life = rng.randf_range(90.0, 150.0)
			v.face = 1.0 if left else -1.0
			world.happened.emit("visitor", {"kind": "squirrel", "x": v.pos.x, "y": v.pos.y})
	# Owl: a trunk that has stood a long time and is still standing.
	if counts[OWL] < 1 and rng.randf() < 0.1:
		var best: Plant = null
		for p in world.plants:
			if p.alive and not p.removed and p.age > 420.0 and p.height > 160.0 and p.max_strain < 0.6:
				if best == null or p.age > best.age:
					best = p
		if best != null:
			var v := _add(OWL, Vector2(-60.0 if best.base_x > world.jar_w * 0.5 else world.jar_w + 60.0, world.lid_y + 60.0))
			v.plant = best
			v.seg = _perch_seg(best)
			v.state = "arrive"
			v.life = 1e9
			world.happened.emit("visitor", {"kind": "owl", "x": v.pos.x, "y": v.pos.y, "plant": best})


func _tallest(min_h: float) -> Plant:
	var best: Plant = null
	for p in world.plants:
		if p.alive and not p.removed and p.height > min_h and p.leaf_total > 0.0:
			if best == null or p.height > best.height:
				best = p
	return best


func _top_seg(p: Plant) -> int:
	var best := 0
	for i in p.n:
		if p.by[i] < p.by[best]:
			best = i
	return best


## A sturdy branch high in the tree.
func _perch_seg(p: Plant) -> int:
	var best := 0
	var best_y := 1e9
	for i in p.n:
		if p.rad[i] >= 2.0 and p.by[i] < best_y:
			best_y = p.by[i]
			best = i
	return best


func _perch(v: Visitor) -> Vector2:
	if v.plant == null or v.plant.removed or v.seg < 0 or v.seg >= v.plant.n:
		return Vector2(INF, INF)
	return Vector2(v.plant.bx[v.seg], v.plant.by[v.seg])


func _fly_to(v: Visitor, goal: Vector2, dt: float, speed: float) -> bool:
	var d := goal - v.pos
	var dist := d.length()
	if dist < 3.0:
		v.pos = goal
		v.vel = Vector2.ZERO
		return true
	var want := d / dist * minf(speed, dist * 3.0)
	v.vel = v.vel.lerp(want, minf(1.0, dt * 4.0))
	v.pos += v.vel * dt
	if absf(v.vel.x) > 5.0:
		v.face = signf(v.vel.x)
	return false


func _firefly(v: Visitor, dt: float) -> bool:
	var drift := Vector2(sin(world.clock * 0.9 + v.phase) * 22.0, cos(world.clock * 0.7 + v.phase * 1.3) * 14.0)
	v.vel = v.vel.lerp((v.goal - v.pos) * 0.4 + drift, minf(1.0, dt * 1.5))
	v.pos += v.vel * dt
	var leaving := v.life <= 0.0 or absf(world.sun_phi) < 0.6
	if leaving:
		v.goal.y -= dt * 30.0
		v.t = minf(v.t, 0.0) - dt
	return not (leaving and v.t < -3.0)


func _beetle(v: Visitor, dt: float) -> bool:
	var l := v.log_body
	if l == null or not is_instance_valid(l) or l.rot >= 0.97:
		return false
	# Crawl back and forth along the top of the log.
	v.along += v.face * dt * 0.05 * (0.6 + 0.4 * sin(world.clock * 1.7 + v.phase))
	if v.along < 0.05 or v.along > 0.95:
		v.face = -v.face
		v.along = clampf(v.along, 0.05, 0.95)
	var count := l.segs.size() / LogBody.STRIDE
	var o := clampi(int(v.along * count), 0, count - 1) * LogBody.STRIDE
	var f := fposmod(v.along * count, 1.0)
	var xf := l.global_transform
	var a := xf * Vector2(l.segs[o], l.segs[o + 1])
	var b := xf * Vector2(l.segs[o + 2], l.segs[o + 3])
	var on := a.lerp(b, f)
	var normal := (b - a).orthogonal().normalized()
	if normal.y > 0.0:
		normal = -normal
	v.pos = on + normal * (l.segs[o + 4] * (1.0 - l.rot * 0.45) + 1.5)
	v.goal = b - a
	return true


func _bird(v: Visitor, dt: float) -> bool:
	var rng := world.rng
	match v.state:
		"arrive", "return":
			var perch := _perch(v)
			if perch.x == INF or not v.plant.alive:
				v.state = "leave"
			elif _fly_to(v, perch + Vector2(0, -6), dt, 170.0):
				v.state = "sit"
				v.t = 0.0
		"sit":
			var perch := _perch(v)
			if perch.x == INF or not v.plant.alive or v.plant.max_strain > 0.9:
				v.state = "leave"
				world.happened.emit("bird_startled", {"x": v.pos.x, "y": v.pos.y})
			else:
				v.pos = perch + Vector2(0, -6)
				if v.life <= 0.0:
					v.state = "leave"
				elif v.t > 8.0 and rng.randf() < dt * 0.15:
					# Go looking for a plump seed somewhere in the jar.
					var picks: Array[Plant] = []
					for p in world.plants:
						if p.alive and not p.removed and p.seeds_ripe > 0 and p.genome.h[Genome.SEED] > 0.45:
							picks.append(p)
					if not picks.is_empty():
						var src: Plant = picks[rng.randi() % picks.size()]
						v.state = "fetch"
						v.carrying = null
						var top := _top_seg(src)
						v.goal = Vector2(src.bx[top], src.by[top])
						v.source_id = src.id
		"fetch":
			if _fly_to(v, v.goal, dt, 190.0):
				var src: Plant = null
				for p in world.plants:
					if p.id == v.source_id:
						src = p
						break
				if src != null and not src.removed and src.seeds_ripe > 0:
					src.seeds_ripe -= 1
					v.carrying = src.genome.child(rng)
					v.carry_species = src.species
					# Drop it far across the jar.
					var far := world.jar_w - v.pos.x + rng.randf_range(-200, 200)
					v.goal = Vector2(clampf(far, 40.0, world.jar_w - 40.0), world.lid_y + rng.randf_range(120, 260))
					v.state = "carry"
				else:
					v.state = "return"
		"carry":
			if _fly_to(v, v.goal, dt, 170.0):
				var s := world.spawn_seed(v.carrying, v.pos.x, v.pos.y + 4.0, v.vel.x * 0.2, 10.0, null)
				if s != null:
					s.species = v.carry_species
				world.happened.emit("bird_drop", {"x": v.pos.x, "y": v.pos.y})
				v.carrying = null
				v.state = "return"
		"leave":
			var out := Vector2(-80.0 if v.pos.x < world.jar_w * 0.5 else world.jar_w + 80.0, world.lid_y + 60.0)
			if _fly_to(v, out, dt, 210.0):
				return false
	return true


func _squirrel(v: Visitor, dt: float) -> bool:
	var rng := world.rng
	var gy := world.soil.ground_y(clampf(v.pos.x, 0.0, world.jar_w))
	match v.state:
		"seek":
			# Find a plump seed lying on the ground, or wait under a plump-seeded plant.
			var best: World.SeedBit = null
			var best_d := 1e9
			for s in world.seeds:
				if s.resting and s.mass > 0.55:
					var d := absf(s.x - v.pos.x)
					if d < best_d:
						best_d = d
						best = s
			if best != null:
				v.goal = Vector2(best.x, best.y)
				v.state = "fetch"
			elif v.life <= 0.0:
				v.state = "leave"
			elif v.plant != null and not v.plant.removed:
				v.goal = Vector2(v.plant.base_x + 20.0 * v.face, 0.0)
				_run(v, v.goal.x, dt)
		"fetch":
			if _run(v, v.goal.x, dt):
				var got: World.SeedBit = null
				for s in world.seeds:
					if s.resting and absf(s.x - v.pos.x) < 8.0 and s.mass > 0.55:
						got = s
						break
				if got != null:
					v.carrying = got.genome
					v.carry_species = got.species
					world.take_seed(got)
					v.goal = Vector2(rng.randf_range(40.0, world.jar_w - 40.0), 0.0)
					v.state = "bury"
				else:
					v.state = "seek"
		"bury":
			if _run(v, v.goal.x, dt):
				v.state = "dig"
				v.t = 0.0
		"dig":
			if v.t > 1.4:
				# Most buried seeds are forgotten and sprout later; some are eaten.
				if rng.randf() < 0.7:
					var s := world.spawn_seed(v.carrying, v.pos.x, gy - 1.0, 0.0, 0.0, null)
					if s != null:
						s.species = v.carry_species
						s.delay = rng.randf_range(20.0, 60.0)
						s.life = maxf(s.life, 400.0)
				world.happened.emit("buried", {"x": v.pos.x, "y": gy})
				v.carrying = null
				v.state = "seek" if v.life > 0.0 else "leave"
		"leave":
			var out := -40.0 if v.pos.x < world.jar_w * 0.5 else world.jar_w + 40.0
			if _run(v, out, dt):
				return false
	v.pos.y = world.soil.ground_y(clampf(v.pos.x, 0.0, world.jar_w)) - 1.0
	return true


## Scamper along the ground in little bursts.
func _run(v: Visitor, x: float, dt: float) -> bool:
	var d := x - v.pos.x
	if absf(d) < 4.0:
		v.vel = Vector2.ZERO
		return true
	v.face = signf(d)
	var burst := 0.35 + 0.65 * maxf(0.0, sin(world.clock * 7.0 + v.phase))
	v.vel.x = v.face * 150.0 * burst
	v.pos.x += clampf(v.vel.x * dt, -absf(d), absf(d))
	return false


func _owl(v: Visitor, dt: float) -> bool:
	match v.state:
		"arrive":
			var perch := _perch(v)
			if perch.x == INF or not v.plant.alive:
				v.state = "leave"
			elif _fly_to(v, perch + Vector2(0, -10), dt, 120.0):
				v.state = "sit"
				v.t = 0.0
		"sit":
			var p := v.plant
			var perch := _perch(v)
			# The owl knows: it goes before its tree comes down.
			if perch.x == INF or not p.alive or p.max_strain > 0.72 or p.fail_acc > 0.0 or p.health < 0.7:
				v.state = "leave"
				world.happened.emit("owl_left", {"x": v.pos.x, "y": v.pos.y, "plant": p})
			else:
				v.pos = perch + Vector2(0, -10)
		"leave":
			var out := Vector2(-80.0 if v.pos.x < world.jar_w * 0.5 else world.jar_w + 80.0, world.lid_y + 40.0)
			if _fly_to(v, out, dt, 150.0):
				return false
	return true
