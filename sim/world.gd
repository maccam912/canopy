class_name World
extends Node2D
## The jar: soil, sun, plants, seeds and fallen wood, advanced by step().
## Nothing here draws or reads input, so a whole forest can be grown headless.

signal plant_added(p: Plant)
signal plant_removed(p: Plant)
signal log_added(l: LogBody)
signal log_removed(l: LogBody)
signal happened(kind: String, data: Dictionary)


class SeedBit:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var genome: Genome
	var mass := 0.5
	var reserve := 50.0
	var resting := false
	var t := 0.0
	var delay := 3.0
	var life := 100.0
	var phase := 0.0
	var species := -1
	var generation := 0
	var check := 0.0


## A prop (a stick wedged between the ground and a trunk) or a tie (a string
## between two stems). Both only ever add outside forces to the plants they touch.
class Brace:
	var tie := false
	var a: Plant
	var a_at := Vector2()
	var b: Plant
	var b_at := Vector2()      # tie: point on the second plant; prop: the foot on the ground
	var length := 0.0
	var stiff := 1.0
	var limit := 1.0
	var load := 0.0
	var broken := false
	var grip := false          # made by the plant itself: a thin stem tangled in a stouter one


var rng := RandomNumberGenerator.new()
var braces: Array[Brace] = []
var census_acc := 0.0
var grip_acc := 0.0
var shapes_standing := 0
var tallest_ever := 0.0
var jar_w := 1500.0
var jar_h := 780.0
var lid_y := -780.0
var soil := Soil.new()
var light := LightField.new()
var shapes := Shapes.new()
var plants: Array[Plant] = []
var logs: Array[LogBody] = []
var seeds: Array[SeedBit] = []
var body_plant := {}
var ground_rid := RID()
var occupied := PackedInt32Array()
var seed_cols := PackedInt32Array()

var time := 0.0            # biological seconds: growth, rot, the sun
var clock := 0.0           # mechanical seconds: sway and falls, always real time
var speed := 1.0
var falling := false
var sun_phi := 0.0
var sun_vel := 0.0
var wind := 0.0            # steady wind from the Wind tool
var gust_x := -1e6
var gust_v := 0.0
var gust_power := 0.0
var gust_wait := 4.0
var breeze := 1.0

var next_id := 1
var light_real := 1.0
var light_bio := 1.0
var light_version := 0
var soil_acc := 0.0
var cascade := {}
var cascade_clock := -100.0
var cascade_peak := 0
var purge := false

var count_falls := 0
var count_born := 0
var count_died := 0
var count_rotted := 0
var best_cascade := 0


func setup(p_seed: int, w := 1500.0, h := 780.0, state := {}) -> void:
	rng.seed = p_seed
	jar_w = w
	jar_h = h
	if not state.is_empty():
		jar_w = state.jar_w
		jar_h = state.jar_h
	lid_y = -jar_h
	soil.setup(jar_w, rng)
	occupied.resize(soil.n)
	seed_cols.resize(soil.n)
	if not state.is_empty():
		soil.height = state.soil_height
		soil.rich = state.soil_rich
		soil.wet = state.soil_wet
	_build_ground()
	if not state.is_empty():
		_load(state)
	compute_light()


## The whole jar as plain data, for saving.
func save_state() -> Dictionary:
	var ps := []
	for p in plants:
		if not p.removed:
			ps.append(p.save_state())
	var ss := []
	for s in seeds:
		ss.append({"x": s.x, "y": s.y, "vx": s.vx, "vy": s.vy, "h": s.genome.h, "hue": s.genome.hue, "mass": s.mass, "reserve": s.reserve,
			"resting": s.resting, "t": s.t, "delay": s.delay, "life": s.life, "species": s.species, "generation": s.generation})
	var ls := []
	for l in logs:
		# Fallen wood is saved where it lies, already turned to its resting angle.
		var data := PackedFloat32Array()
		data.resize(l.segs.size())
		var xf := l.global_transform
		for i in l.segs.size() / LogBody.STRIDE:
			var o := i * LogBody.STRIDE
			var a := xf * Vector2(l.segs[o], l.segs[o + 1])
			var b := xf * Vector2(l.segs[o + 2], l.segs[o + 3])
			data[o] = a.x
			data[o + 1] = a.y
			data[o + 2] = b.x
			data[o + 3] = b.y
			data[o + 4] = l.segs[o + 4]
			data[o + 5] = l.segs[o + 5]
		ls.append({"data": data, "x": l.position.x, "y": l.position.y, "h": l.genome.h, "hue": l.genome.hue, "species": l.species,
			"nutrient": l.nutrient, "rot": l.rot, "age": l.age, "seeds": l.seeds, "landed": l.landed, "flung": l.flung})
	var bs := []
	for b in braces:
		if b.grip:
			continue
		bs.append({"tie": b.tie, "a": b.a.id, "a_at": b.a_at, "b": b.b.id if b.tie else -1, "b_at": b.b_at, "length": b.length, "stiff": b.stiff, "limit": b.limit})
	return {
		"version": 1, "jar_w": jar_w, "jar_h": jar_h, "time": time, "clock": clock, "sun_phi": sun_phi, "sun_vel": sun_vel,
		"next_id": next_id, "rng": rng.state, "soil_height": soil.height, "soil_rich": soil.rich, "soil_wet": soil.wet,
		"shapes": shapes.list, "names": shapes.used_names, "plants": ps, "seeds": ss, "logs": ls, "braces": bs,
		"count_falls": count_falls, "count_born": count_born, "count_died": count_died, "count_rotted": count_rotted,
		"best_cascade": best_cascade, "tallest_ever": tallest_ever,
	}


func _load(d: Dictionary) -> void:
	time = d.time
	clock = d.clock
	sun_phi = d.sun_phi
	sun_vel = d.sun_vel
	rng.state = d.rng
	shapes.list.assign(d.shapes)
	shapes.used_names = d.names
	count_falls = d.count_falls
	count_born = d.count_born
	count_died = d.count_died
	count_rotted = d.count_rotted
	best_cascade = d.best_cascade
	tallest_ever = d.tallest_ever
	for s in shapes.list:
		s.alive = 0
	var by_id := {}
	for pd: Dictionary in d.plants:
		var p := add_plant(Genome.make(Array(pd.h), pd.hue), pd.x, 0.0)
		if p.species >= 0:
			shapes.list[p.species].total -= 1
			shapes.list[p.species].alive -= 1
		p.load_state(pd)
		if p.alive and p.species >= 0:
			shapes.list[p.species].alive += 1
		by_id[p.id] = p
	count_born = d.count_born
	next_id = d.next_id
	for sd: Dictionary in d.seeds:
		var s := SeedBit.new()
		s.genome = Genome.make(Array(sd.h), sd.hue)
		s.x = sd.x
		s.y = sd.y
		s.vx = sd.vx
		s.vy = sd.vy
		s.mass = sd.mass
		s.reserve = sd.reserve
		s.resting = sd.resting
		s.t = sd.t
		s.delay = sd.delay
		s.life = sd.life
		s.species = sd.species
		s.generation = sd.generation
		s.phase = rng.randf() * TAU
		if s.resting:
			seed_cols[soil.col(s.x)] += 1
		seeds.append(s)
	for ld: Dictionary in d.logs:
		var body := LogBody.new()
		body.genome = Genome.make(Array(ld.h), ld.hue)
		body.species = ld.species
		body.setup(self, ld.data, Vector2(ld.x, ld.y), Vector2.ZERO, 0.0)
		body.nutrient = ld.nutrient
		body.rot = ld.rot
		body.age = ld.age
		body.seeds = ld.seeds
		body.landed = ld.landed
		body.flung = ld.flung
		add_child(body)
		logs.append(body)
		log_added.emit(body)
	for bd: Dictionary in d.braces:
		if not by_id.has(bd.a) or (bd.tie and not by_id.has(bd.b)):
			continue
		var b := Brace.new()
		b.tie = bd.tie
		b.a = by_id[bd.a]
		b.a_at = bd.a_at
		b.b = by_id[bd.b] if bd.tie else null
		b.b_at = bd.b_at
		b.length = bd.length
		b.stiff = bd.stiff
		b.limit = bd.limit
		braces.append(b)


func _build_ground() -> void:
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	ground.physics_material_override = mat
	# One convex slab per soil column keeps contact with long logs stable.
	for i in soil.n:
		var x0 := i * Soil.CW
		var x1 := x0 + Soil.CW
		var cs := CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = PackedVector2Array([Vector2(x0, soil.height[i]), Vector2(x1, soil.height[i + 1]), Vector2(x1, 160.0), Vector2(x0, 160.0)])
		cs.shape = poly
		ground.add_child(cs)
	add_child(ground)
	ground_rid = ground.get_rid()
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	for side in 2:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(80.0, jar_h + 400.0)
		cs.shape = rect
		cs.position = Vector2(-40.0 if side == 0 else jar_w + 40.0, -jar_h * 0.5)
		walls.add_child(cs)
	add_child(walls)


func _physics_process(delta: float) -> void:
	step(delta)


func _exit_tree() -> void:
	braces.clear()
	for l in logs:
		l.release()
	for p in plants:
		p.free_body()


func step(dt: float) -> void:
	dt = minf(dt, 1.0 / 30.0)
	# A big fall always plays at normal speed.
	var sp := 1.0 if falling else speed
	var bdt := dt * sp
	time += bdt
	clock += dt
	if sun_vel != 0.0:
		sun_phi += sun_vel * bdt
		if absf(sun_phi) > 1.25:
			sun_phi = clampf(sun_phi, -1.25, 1.25)
			sun_vel = -sun_vel
	light_real += dt
	light_bio += bdt
	if light_real >= 0.3 or light_bio >= 1.2:
		compute_light()
	_gusts(dt)
	_grow(dt, bdt)
	_braces(dt)
	_mech(dt)
	grip_acc += dt
	if grip_acc > 0.5:
		grip_acc = 0.0
		_grips()
	census_acc += bdt
	if census_acc > 4.0:
		census_acc = 0.0
		_census()
	var seed_steps := int(ceil(bdt / 0.034))
	for k in seed_steps:
		_seeds(bdt / seed_steps)
	_logs(dt, bdt)
	soil_acc += bdt
	if soil_acc > 1.0:
		soil.step(soil_acc)
		soil_acc = 0.0
	if not cascade.is_empty() and clock - cascade_clock > 6.0:
		happened.emit("cascade_end", {"count": cascade.size()})
		cascade.clear()
	if purge:
		purge = false
		plants = plants.filter(func(p: Plant) -> bool: return not p.removed)


# ------------------------------------------------------------------ light ----

func compute_light() -> void:
	light_real = 0.0
	light_bio = 0.0
	light.begin(sun_phi, jar_w, jar_h)
	for p in plants:
		var op := p.leaf_op
		for i in p.n:
			if p.leaf[i] > 0.0:
				light.deposit(p.bx[i], p.by[i], p.leaf[i], op)
	light.solve()
	for p in plants:
		var op := p.leaf_op
		var total := 0.0
		for i in p.n:
			if p.leaf[i] > 0.0:
				var e := light.income(p.bx[i], p.by[i], p.leaf[i], op)
				p.lgain[i] = e
				total += e
			else:
				p.lgain[i] = 0.0
		p.income = total if p.alive else 0.0
	for c in soil.n:
		var x := (c + 0.5) * Soil.CW
		soil.light[c] = light.sample(x, soil.ground_y(x) - 4.0)
	light_version += 1


# ----------------------------------------------------------------- plants ----

func add_plant(g: Genome, x: float, reserve: float, species := -1, generation := 0) -> Plant:
	var p := Plant.new(self, g, x, reserve)
	p.id = next_id
	next_id += 1
	p.species = shapes.classify(g, species) if not shapes.list.is_empty() else -1
	p.generation = generation
	p.body = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(p.body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_space(p.body, get_world_2d().space)
	PhysicsServer2D.body_set_collision_layer(p.body, 2)
	PhysicsServer2D.body_set_collision_mask(p.body, 0)
	body_plant[p.body] = p
	p.grow_acc = rng.randf() * 0.3
	plants.append(p)
	occupied[soil.col(x)] += 1
	if p.species >= 0:
		shapes.list[p.species].alive += 1
		shapes.list[p.species].total += 1
	count_born += 1
	plant_added.emit(p)
	return p


func remove_plant(p: Plant) -> void:
	if p.removed:
		return
	p.removed = true
	purge = true
	if p.alive and p.species >= 0:
		shapes.list[p.species].alive -= 1
	p.alive = false
	body_plant.erase(p.body)
	p.free_body()
	occupied[soil.col(p.base_x)] -= 1
	plant_removed.emit(p)


func _grow(dt: float, bdt: float) -> void:
	var interval := maxf(0.3, 0.12 * (bdt / dt))
	for p in plants:
		p.grow_acc += bdt
		if p.grow_acc >= interval and not p.removed:
			var step_dt := p.grow_acc
			p.grow_acc = 0.0
			p.grow(step_dt)
			if not p.removed and not p.awake:
				p.awake = true
				p.still = 22


func _mech(dt: float) -> void:
	var count := plants.size()
	for idx in count:
		var p := plants[idx]
		if p.removed or not p.awake:
			continue
		var failed := p.mech(dt, wind_at(p.base_x))
		p.sync_body()
		if failed >= 0:
			break_plant(p, failed, p.fail_uproot)


func wind_at(x: float) -> float:
	var d := (x - gust_x) / 140.0
	return wind + gust_power * exp(-d * d)


func _gusts(dt: float) -> void:
	if gust_power != 0.0:
		gust_x += gust_v * dt
		if gust_x < -300.0 or gust_x > jar_w + 300.0:
			gust_power = 0.0
			gust_wait = rng.randf_range(5.0, 14.0)
		else:
			for p in plants:
				if not p.awake and absf(p.base_x - gust_x) < 220.0:
					p.awake = true
					p.still = 0
	else:
		gust_wait -= dt
		if gust_wait <= 0.0:
			var right := rng.randf() < 0.5
			gust_x = -250.0 if right else jar_w + 250.0
			gust_v = (1.0 if right else -1.0) * rng.randf_range(260.0, 420.0)
			gust_power = (1.0 if right else -1.0) * rng.randf_range(10.0, 30.0) * breeze
	if wind != 0.0:
		for p in plants:
			if not p.awake:
				p.awake = true
				p.still = 0


## A joint gave way. Everything beyond it becomes fallen wood.
## cut: for a snip, how far along segment i the cut lands (0..1); else -1.
func break_plant(p: Plant, i: int, uproot: bool, cut := -1.0, kick := 0.0) -> LogBody:
	if p.removed or i >= p.n:
		return null
	var whole := i == 0 and cut < 0.08
	var idxs := p.subtree(i)
	var data := PackedFloat32Array()
	data.resize(idxs.size() * LogBody.STRIDE)
	var m := 0.0
	var cx := 0.0
	var cy := 0.0
	var vol := 0.0
	var leaves := 0.0
	var o := 0
	for j in idxs:
		var x0 := p.ax[j]
		var y0 := p.ay[j]
		if j == i and cut > 0.0:
			x0 = lerpf(p.ax[j], p.bx[j], cut)
			y0 = lerpf(p.ay[j], p.by[j], cut)
		var r := p.rad[j]
		var l := Vector2(x0, y0).distance_to(Vector2(p.bx[j], p.by[j]))
		var lw := p.leaf[j] * p.leaf_op
		data[o] = x0
		data[o + 1] = y0
		data[o + 2] = p.bx[j]
		data[o + 3] = p.by[j]
		data[o + 4] = r
		data[o + 5] = lw
		o += LogBody.STRIDE
		var mw := T.RHO * r * r * l
		m += mw + T.LEAF_M * lw
		cx += (x0 + p.bx[j]) * 0.5 * mw + p.bx[j] * T.LEAF_M * lw
		cy += (y0 + p.by[j]) * 0.5 * mw + p.by[j] * T.LEAF_M * lw
		vol += r * r * l
		leaves += lw
	var com := Vector2(cx / m, cy / m)
	var joint_at := Vector2(data[0], data[1])
	# The piece keeps the swing it had when it let go.
	var spin := 0.0
	var k := i
	while k >= 0:
		spin += p.dvel[k]
		k = p.parent[k]
	var arm := com - Vector2(p.base_x, p.base_y)
	var vel := Vector2(-arm.y, arm.x) * spin
	var share := clampf(vol / maxf(p.volume, 1.0), 0.0, 1.0)
	var part_nutrient := p.nutrient * share
	p.nutrient -= part_nutrient
	var ripe := p.seeds_ripe + int(p.seed_bank / p.seed_cost) + (1 if p.mature else 0)
	var carried := ripe if whole else int(round(ripe * share))
	var was_alive := p.alive
	var height := p.height
	var info := {"wood": p.genome.h[Genome.WOOD], "reach": p.genome.h[Genome.REACH], "r": p.rad[i], "seg": i, "segs": p.n, "lean": p.ang[i], "health": p.health, "plant": p.id, "x": joint_at.x, "y": joint_at.y, "volume": vol, "uproot": uproot, "snip": cut >= 0.0, "whole": whole, "height": height, "alive": was_alive, "species": p.species}

	var body: LogBody = null
	if vol < T.LITTER_VOL:
		# Too small to be an object: it crumbles straight into litter.
		soil.add(com.x - 10.0, com.x + 10.0, part_nutrient + leaves * T.LEAF_N)
		happened.emit("litter", {"x": com.x, "y": com.y, "hue": p.genome.hue, "leaves": leaves})
	else:
		body = LogBody.new()
		body.genome = p.genome
		body.species = p.species
		body.nutrient = part_nutrient + leaves * T.LEAF_N
		body.seeds = carried
		if cut >= 0.0:
			# A cut stem tips the way it was pushed, or the way it already leans.
			var lean := signf(com.x - joint_at.x) if absf(com.x - joint_at.x) > 2.0 else (1.0 if rng.randf() < 0.5 else -1.0)
			spin += (kick if kick != 0.0 else lean) * 0.4
			var arm2 := com - joint_at
			vel = Vector2(-arm2.y, arm2.x) * spin
		body.setup(self, data, com, vel, spin)
		add_child(body)
		logs.append(body)
		if not whole and p.body.is_valid():
			# The break holds for a moment like a hinge, so the top swings down in an arc.
			body.hinge(p, joint_at)
		log_added.emit(body)

	if whole:
		soil.add(p.base_x - 12.0, p.base_x + 12.0, p.nutrient)
		p.nutrient = 0.0
		if was_alive:
			p.die("uprooted" if uproot else "snapped")
		remove_plant(p)
	else:
		p.seeds_ripe = maxi(0, p.seeds_ripe - carried)
		if cut > 0.0:
			# Keep the stub of the cut segment.
			var kids := PackedInt32Array()
			for j in range(i + 1, p.n):
				if p.parent[j] == i:
					kids.append(j)
			p.slen[i] *= cut
			p.leaf[i] = 0.0
			p.tip[i] = 0
			for c in range(kids.size() - 1, -1, -1):
				p.remove_subtree(kids[c])
			p.pose()
			p.awake = true
			p.still = 0
		else:
			p.remove_subtree(i)
		p.col_dirty = true
		if was_alive:
			p.falls_survived += 1
	if vol >= T.FALL_VOL:
		count_falls += 1
		if clock - cascade_clock > 6.0:
			cascade.clear()
		cascade[p.id] = true
		cascade_clock = clock
		best_cascade = maxi(best_cascade, cascade.size())
		info["count"] = cascade.size()
		happened.emit("fall", info)
	else:
		happened.emit("break", info)
	return body


## A stem cut by the player. Returns the fallen piece, if any.
func snip(p: Plant, i: int, t: float, kick := 0.0) -> LogBody:
	if p.removed or i >= p.n:
		return null
	return break_plant(p, i, false, clampf(t, 0.0, 0.95), kick)


## A small dead plant falls apart where it stands.
func crumble(p: Plant) -> void:
	soil.add(p.base_x - 10.0, p.base_x + 10.0, p.nutrient + p.leaf_total * p.leaf_op * T.LEAF_N)
	happened.emit("litter", {"x": p.base_x, "y": p.base_y - p.height * 0.5, "hue": p.genome.hue, "leaves": p.leaf_total})
	remove_plant(p)


# ----------------------------------------------------------------- braces ----

## Nearest point on a plant to a world position: [segment, point, distance].
func nearest_on(p: Plant, at: Vector2) -> Array:
	var best := -1
	var best_d := 1e9
	var best_pt := at
	for i in p.n:
		var a := Vector2(p.ax[i], p.ay[i])
		var b := Vector2(p.bx[i], p.by[i])
		var pt := Geometry2D.get_closest_point_to_segment(at, a, b)
		var d := pt.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
			best_pt = pt
	return [best, best_pt, sqrt(best_d)]


## The plant stem nearest a point, within reach: [plant, segment, point] or [].
func pick_stem(at: Vector2, reach: float, min_r := 0.0) -> Array:
	var found := []
	var best := reach
	for p in plants:
		if p.removed or absf(p.base_x - at.x) > p.height + reach + 40.0:
			continue
		var hit := nearest_on(p, at)
		if hit[0] >= 0 and hit[2] < best and p.rad[hit[0]] >= min_r:
			best = hit[2]
			found = [p, hit[0], hit[1]]
	return found


## Wedge a stick under a trunk at this point. The foot goes on the side it leans to.
func add_prop(p: Plant, at: Vector2) -> Brace:
	var b := Brace.new()
	b.a = p
	b.a_at = at
	var up := soil.ground_y(at.x) - at.y
	var lean := signf(at.x - p.base_x)
	if lean == 0.0:
		lean = signf(p.ang[0]) if p.ang[0] != 0.0 else 1.0
	var fx := clampf(at.x + lean * maxf(up * 0.45, 14.0), 4.0, jar_w - 4.0)
	b.b_at = Vector2(fx, soil.ground_y(fx))
	b.length = at.distance_to(b.b_at)
	var weight := maxf(p.volume, 200.0) * T.RHO * T.GRAV
	b.stiff = weight / 4.0
	b.limit = weight * 2.5
	braces.append(b)
	happened.emit("prop", {"x": at.x, "y": at.y})
	return b


## Run a string between two stems. It only pulls, and only when stretched.
func add_tie(p: Plant, at: Vector2, q: Plant, to: Vector2) -> Brace:
	var b := Brace.new()
	b.tie = true
	b.a = p
	b.a_at = at
	b.b = q
	b.b_at = to
	b.length = at.distance_to(to) * 1.03
	var weight := maxf(minf(p.volume, q.volume), 200.0) * T.RHO * T.GRAV
	b.stiff = weight / 5.0
	b.limit = weight * 2.0
	braces.append(b)
	happened.emit("tie", {"x": at.x, "y": at.y})
	return b


## Vines come free from the physics: a thin stem that touches a much stouter
## trunk tangles with it and hangs its weight there.
func _grips() -> void:
	var total := 0
	for p in plants:
		p.grips = 0
	for b in braces:
		if b.grip:
			total += 1
			b.a.grips += 1
	if total >= 70:
		return
	var cell := 48.0
	var grid := {}
	for p in plants:
		if p.removed:
			continue
		for i in p.n:
			if p.rad[i] >= 2.4:
				var key := Vector2i(int(floor((p.ax[i] + p.bx[i]) * 0.5 / cell)), int(floor((p.ay[i] + p.by[i]) * 0.5 / cell)))
				if not grid.has(key):
					grid[key] = []
				grid[key].append([p, i])
	if grid.is_empty():
		return
	for p in plants:
		if p.removed or not p.alive or p.grips >= 4 or p.n < 4:
			continue
		for i in p.n:
			if p.kids[i] != 0 or p.rad[i] > 1.8:
				continue
			var at := Vector2(p.bx[i], p.by[i])
			if at.y > p.base_y - 45.0:
				continue
			var home := Vector2i(int(floor(at.x / cell)), int(floor(at.y / cell)))
			var done := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var found: Variant = grid.get(home + Vector2i(ox, oy))
					if found == null or done:
						continue
					for entry: Array in found:
						var q: Plant = entry[0]
						var j: int = entry[1]
						if q == p or q.removed or j >= q.n or q.rad[j] < p.rad[i] * 2.0:
							continue
						var pt := Geometry2D.get_closest_point_to_segment(at, Vector2(q.ax[j], q.ay[j]), Vector2(q.bx[j], q.by[j]))
						if at.distance_to(pt) > q.rad[j] + 6.0:
							continue
						var near := false
						for b in braces:
							if b.grip and b.a == p and b.a_at.distance_to(at) < 45.0:
								near = true
								break
						if near:
							continue
						var g := Brace.new()
						g.tie = true
						g.grip = true
						g.a = p
						g.a_at = at
						g.b = q
						g.b_at = pt
						g.length = at.distance_to(pt) + 2.0
						var weight := maxf(p.volume, 80.0) * T.RHO * T.GRAV
						g.stiff = weight / 4.0
						g.limit = weight * 5.0
						braces.append(g)
						p.grips += 1
						done = true
						happened.emit("grip", {"plant": p, "host": q, "x": pt.x, "y": pt.y})
						break
			if p.grips >= 4:
				break


func _braces(_dt: float) -> void:
	var i := braces.size() - 1
	while i >= 0:
		var b := braces[i]
		var gone := b.a.removed or (b.tie and b.b.removed)
		if not gone:
			var ha := nearest_on(b.a, b.a_at)
			if ha[0] < 0 or ha[2] > 40.0:
				gone = true
			else:
				b.a_at = ha[1]
				var other := b.b_at
				var hb := []
				if b.tie:
					hb = nearest_on(b.b, b.b_at)
					if hb[0] < 0 or hb[2] > 40.0:
						gone = true
					else:
						b.b_at = hb[1]
						other = hb[1]
				if not gone:
					var d: Vector2 = b.a_at - other
					var l := d.length()
					var stretch := (l - b.length) if b.tie else (b.length - l)
					if stretch > 0.0 and l > 0.5:
						var f := b.stiff * stretch
						b.load = f / b.limit
						if f > b.limit:
							gone = true
						else:
							# A tie pulls the two points together; a prop pushes the trunk off its foot.
							var dir := d / l * (-1.0 if b.tie else 1.0)
							b.a.push(ha[0], b.a_at.x, b.a_at.y, dir.x * f, dir.y * f)
							if b.tie:
								b.b.push(hb[0], b.b_at.x, b.b_at.y, -dir.x * f, -dir.y * f)
					else:
						b.load = 0.0
		if gone:
			b.broken = true
			braces.remove_at(i)
			happened.emit("brace_broke", {"x": b.a_at.x, "y": b.a_at.y, "tie": b.tie, "grip": b.grip, "x2": b.b_at.x, "y2": b.b_at.y})
		i -= 1


## Every few seconds: which shapes are standing, and who is the tallest of each.
func _census() -> void:
	var best := {}
	for s in shapes.list:
		s.standing = 0
	for p in plants:
		if not p.alive or p.removed or p.species < 0:
			continue
		var s: Dictionary = shapes.list[p.species]
		if p.mature:
			s.standing += 1
		if p.height > tallest_ever:
			tallest_ever = p.height
		if p.height > s.tallest * 1.02 and p.mature:
			if not best.has(p.species) or p.height > best[p.species].height:
				best[p.species] = p
	shapes_standing = 0
	for s in shapes.list:
		if s.standing > 0:
			shapes_standing += 1
	for id: int in best:
		var p: Plant = best[id]
		shapes.list[id].tallest = p.height
		shapes.list[id].portrait = portrait(p)
	happened.emit("census", {})


## A plant's outline, relative to its base: what the field guide draws.
func portrait(p: Plant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(p.n * 6)
	for i in p.n:
		var o := i * 6
		out[o] = p.ax[i] - p.base_x
		out[o + 1] = p.ay[i] - p.base_y
		out[o + 2] = p.bx[i] - p.base_x
		out[o + 3] = p.by[i] - p.base_y
		out[o + 4] = p.rad[i]
		out[o + 5] = p.leaf[i]
	return out


# ------------------------------------------------------------------ seeds ----

func spawn_seed(g: Genome, x: float, y: float, vx: float, vy: float, from: Plant) -> SeedBit:
	if seeds.size() >= T.MAX_SEEDS:
		return null
	var s := SeedBit.new()
	s.genome = g
	s.x = clampf(x, 6.0, jar_w - 6.0)
	s.y = y
	s.vx = vx
	s.vy = vy
	var hs := g.h[Genome.SEED]
	s.mass = lerpf(0.12, 1.0, hs)
	s.reserve = (70.0 + 650.0 * hs * hs) * 0.7
	s.delay = rng.randf_range(1.5, 7.0)
	s.life = 50.0 + 220.0 * s.mass
	s.phase = rng.randf() * TAU
	if from != null:
		s.species = from.species
		s.generation = from.generation + 1
	seeds.append(s)
	return s


func _seeds(bdt: float) -> void:
	var dt := bdt
	var i := seeds.size() - 1
	while i >= 0:
		var s := seeds[i]
		var dead := false
		if not s.resting:
			# Light seeds drift on the air; heavy ones drop.
			var vt := 20.0 + 170.0 * s.mass * s.mass
			s.vy += T.GRAV * (1.0 - s.vy / vt) * dt
			var drift := wind_at(s.x) * 2.2 + sin(time * 2.3 + s.phase) * 26.0 * (1.0 - s.mass)
			s.vx += (drift * (1.0 - s.mass * 0.8) - s.vx) * minf(1.0, dt * (0.6 + 2.5 * (1.0 - s.mass)))
			s.x += s.vx * dt
			s.y += s.vy * dt
			if s.x < 5.0 or s.x > jar_w - 5.0:
				s.x = clampf(s.x, 5.0, jar_w - 5.0)
				s.vx = -s.vx * 0.3
			var gy := soil.ground_y(s.x)
			if s.y >= gy:
				s.y = gy
				var c := soil.col(s.x)
				if seed_cols[c] >= 3:
					dead = true
				else:
					s.resting = true
					seed_cols[c] += 1
		else:
			s.t += bdt
			s.check += bdt
			if s.t > s.life:
				dead = true
				seed_cols[soil.col(s.x)] -= 1
			elif s.t > s.delay and s.check > 1.0:
				s.check = 0.0
				var c := soil.col(s.x)
				var need := lerpf(0.3, 0.05, s.genome.h[Genome.THRIFT])
				if occupied[c] == 0 and plants.size() < T.MAX_PLANTS and soil.light[c] >= need:
					add_plant(s.genome, s.x, s.reserve, s.species, s.generation)
					seed_cols[c] -= 1
					happened.emit("sprout", {"x": s.x, "y": s.y})
					dead = true
		if dead:
			seeds[i] = seeds[seeds.size() - 1]
			seeds.pop_back()
		i -= 1


## Take a resting or flying seed out of the world (the seed jar).
func take_seed(s: SeedBit) -> void:
	var at := seeds.find(s)
	if at < 0:
		return
	if s.resting:
		seed_cols[soil.col(s.x)] -= 1
	seeds.remove_at(at)


# ------------------------------------------------------------ fallen wood ----

func _logs(dt: float, bdt: float) -> void:
	var any := false
	var crowded := logs.size() > T.MAX_LOGS
	var i := logs.size() - 1
	while i >= 0:
		var l := logs[i]
		l.tick(dt)
		if l.big and l.moving():
			any = true
		var rate := bdt / l.rot_time * (1.0 + l.beetles) * (5.0 if crowded and i < logs.size() - T.MAX_LOGS else 1.0)
		if not l.landed and l.age < 20.0:
			rate = 0.0
		l.rot += rate
		if rate > 0.0:
			var give := minf(l.nutrient, l.nutrient * rate / maxf(1.0 - l.rot + rate, 0.01))
			var sp := l.span()
			soil.add(sp.x, sp.y, give)
			l.nutrient -= give
		if l.rot >= 1.0 or l.position.y > 300.0:
			var sp := l.span()
			soil.add(sp.x, sp.y, l.nutrient)
			l.release()
			logs.remove_at(i)
			log_removed.emit(l)
			count_rotted += 1
			happened.emit("rotted", {"x": l.position.x, "y": l.position.y, "volume": l.volume})
			l.queue_free()
		i -= 1
	falling = any


func on_log_landed(l: LogBody, pos: Vector2, hit_speed: float) -> void:
	happened.emit("impact", {"x": pos.x, "y": pos.y, "speed": hit_speed, "length": l.length, "volume": l.volume, "hue": l.genome.hue if l.genome != null else 0.3})
	if l.seeds > 0 and not l.flung and l.genome != null:
		l.flung = true
		# Seeds are flung from the crown: a taller, faster fall throws them farther.
		var dir := signf(l.linear_velocity.x)
		if dir == 0.0:
			dir = 1.0 if rng.randf() < 0.5 else -1.0
		var xf := l.global_transform
		var count := l.segs.size() / LogBody.STRIDE
		for k in l.seeds:
			var o := (rng.randi() % count) * LogBody.STRIDE
			var at := xf * Vector2(l.segs[o + 2], l.segs[o + 3])
			var s := spawn_seed(l.genome.child(rng), at.x, minf(at.y, soil.ground_y(at.x) - 3.0), dir * hit_speed * rng.randf_range(0.3, 1.5), -hit_speed * rng.randf_range(0.2, 0.8) - 20.0, null)
			if s != null:
				s.species = l.species
		l.seeds = 0
		happened.emit("flung", {"x": pos.x, "y": pos.y})


# ----------------------------------------------------------------- events ----

func on_mature(p: Plant) -> void:
	var near := shapes.nearest(p.genome)
	var previous := p.species
	if near[0] >= 0 and near[1] < Shapes.RADIUS:
		p.species = near[0]
	else:
		var s := shapes.found(p.genome, time, previous, rng, p.grips >= 2)
		s.portrait = portrait(p)
		s.leaf = p.genome.h[Genome.LEAF]
		p.species = s.id
		happened.emit("new_shape", {"shape": s, "plant": p})
	if p.species != previous:
		if previous >= 0:
			shapes.list[previous].alive -= 1
		shapes.list[p.species].alive += 1
		shapes.list[p.species].total += 1
		p.dirty = true
	var s := shapes.list[p.species]
	if p.height > s.tallest:
		s.tallest = p.height


func on_seeded(p: Plant) -> void:
	happened.emit("seeded", {"plant": p})


func on_death(p: Plant) -> void:
	count_died += 1
	if p.species >= 0:
		shapes.list[p.species].alive -= 1
	happened.emit("death", {"plant": p, "cause": p.cause})


func on_leaf_drop(p: Plant, i: int) -> void:
	happened.emit("leaf", {"x": p.bx[i], "y": p.by[i], "hue": p.genome.hue, "dead": not p.alive})


func on_lid(p: Plant) -> void:
	happened.emit("lid", {"plant": p})


## Scatter a first handful of very different seeds.
func sow_starters() -> void:
	var kinds := [
		[0.10, 0.05, 0.25, 0.40, 0.30, 0.30, 0.60, 0.20],   # pole
		[0.20, 0.90, 0.70, 0.90, 0.50, 0.60, 0.70, 0.30],   # umbrella
		[0.30, 0.50, 0.60, 0.70, 0.50, 0.70, 0.40, 0.95],   # lurker
		[0.40, 0.40, 0.20, 0.30, 0.10, 0.05, 0.02, 0.10],   # weed
		[0.95, 0.30, 0.20, 0.50, 0.40, 0.30, 0.40, 0.20],   # chaser
		[0.10, 0.50, 0.95, 0.60, 0.95, 0.80, 0.80, 0.40],   # anchor
		[0.50, 0.20, 0.05, 0.80, 0.05, 0.10, 0.30, 0.10],   # toppler
		[0.30, 0.80, 0.40, 0.10, 0.40, 0.20, 0.50, 0.40],   # feather
	]
	var order := range(kinds.size())
	var slots := kinds.size() + 3
	var hue0 := rng.randf()
	for k in slots:
		var g: Genome
		if k < kinds.size():
			g = Genome.make(kinds[order[k]], fposmod(hue0 + k * 0.618, 1.0))
			g = g.child(rng, 0.03)
		else:
			g = Genome.random(rng)
		var x := jar_w * (0.06 + 0.88 * fposmod(k * 0.618 + 0.3, 1.0))
		add_plant(g, x, 60.0 + 200.0 * g.h[Genome.SEED])


func living() -> int:
	var c := 0
	for p in plants:
		if p.alive and not p.removed:
			c += 1
	return c
