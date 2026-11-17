class_name Plant
extends RefCounted
## One plant: a tree of wood segments stored as parallel arrays (parents always
## come before their children). Light earned at the leaves pays upkeep first and
## growth second. Every joint is a spring that bends under the weight above it
## and breaks when the load passes what the wood can take.

var id := 0
var world: World
var genome: Genome
var species := -1
var base_x := 0.0
var base_y := 0.0

# --- structure ---
var n := 0
var parent := PackedInt32Array()
var slen := PackedFloat32Array()
var rad := PackedFloat32Array()
var rest := PackedFloat32Array()    # rest angle relative to parent (root: from vertical)
var defl := PackedFloat32Array()    # elastic bend at the joint under this segment
var dvel := PackedFloat32Array()
var ang := PackedFloat32Array()     # absolute angle from vertical, clockwise positive
var ax := PackedFloat32Array()
var ay := PackedFloat32Array()
var bx := PackedFloat32Array()
var by := PackedFloat32Array()
var leaf := PackedFloat32Array()    # leaf width carried at this segment's tip
var lgain := PackedFloat32Array()   # light that leaf earned at the last light pass
var tip := PackedByteArray()        # 1 while this segment is a growing tip
var kids := PackedInt32Array()
var order := PackedInt32Array()
var bias := PackedFloat32Array()    # sideways lean a branch tries to keep
var strain := PackedFloat32Array()  # load / breaking load at each joint
var efx := PackedFloat32Array()     # outside force on each segment (fallen wood, ties, props)
var efy := PackedFloat32Array()
var epx := PackedFloat32Array()
var bfx := PackedFloat32Array()     # this step's force from props, ties and vines (applied at once)
var bfy := PackedFloat32Array()
var btq := PackedFloat32Array()     # its moment about the origin
var epy := PackedFloat32Array()
# solver scratch
var sm := PackedFloat32Array()
var sfx := PackedFloat32Array()
var sfy := PackedFloat32Array()
var st0 := PackedFloat32Array()
var smx := PackedFloat32Array()
var smy := PackedFloat32Array()
var dist := PackedFloat32Array()    # total wood length beyond each segment
var depth := PackedInt32Array()     # nodes between each segment and its farthest tip

# --- life ---
var alive := true
var energy := 0.0
var income := 0.0
var upkeep := 0.0
var root := 0.0
var volume := 0.0
var leaf_total := 0.0
var nutrient := 0.0
var seed_bank := 0.0
var seeds_ripe := 0
var mature := false
var age := 0.0
var dead_for := 0.0
var health := 1.0
var height := 0.0
var max_strain := 0.0
var cause := ""
var falls_survived := 0
var generation := 0
var lid_time := 0.0
var rings := PackedFloat32Array()   # yearly growth record, read off a cut stump
var ring_acc := 0.0
var ring_t := 0.0

# --- derived from the genome ---
var g_reach := 0.0
var fork_p := 0.0
var fork_ang := 0.0
var wood_k := 1.0
var r_tip := 0.7
var leaf_w := 12.0
var leaf_op := 1.0
var leaf_keep := 4
var internode := 18.0
var root_f := 0.1
var seed_mass := 0.5
var seed_cost := 100.0
var mature_vol := 500.0
var eff := 1.0
var upk := 1.0
var vmax := 5.0

# --- bookkeeping ---
var awake := true
var still := 0
var dirty := true
var grow_acc := 0.0
var fork_side := 1.0
var body := RID()
var col_seg := PackedInt32Array()
var col_shapes: Array[RID] = []
var col_x := PackedFloat32Array()   # where each collider was last put
var col_y := PackedFloat32Array()
var col_a := PackedFloat32Array()
var col_l := PackedFloat32Array()
var col_dirty := true
var removed := false
var grips := 0
var anchor_k := 0.35
var fail_at := -1
var fail_acc := 0.0
var fail_uproot := false


func _init(w: World, g: Genome, x: float, reserve: float) -> void:
	world = w
	genome = g
	base_x = x
	base_y = w.soil.ground_y(x)
	_derive()
	fork_side = 1.0 if w.rng.randf() < 0.5 else -1.0
	energy = reserve
	nutrient = reserve * 0.05
	_add_seg(-1, w.rng.randf_range(-0.1, 0.1), 0, 0.0)
	slen[0] = 3.0
	pose()


## Everything needed to rebuild this plant later.
func save_state() -> Dictionary:
	return {
		"id": id, "h": genome.h, "hue": genome.hue, "species": species, "x": base_x, "generation": generation,
		"parent": parent, "slen": slen, "rad": rad, "rest": rest, "defl": defl, "leaf": leaf, "tip": tip, "order": order, "bias": bias,
		"alive": alive, "energy": energy, "root": root, "nutrient": nutrient, "seed_bank": seed_bank, "seeds_ripe": seeds_ripe,
		"mature": mature, "age": age, "dead_for": dead_for, "health": health, "falls": falls_survived, "cause": cause,
		"rings": rings, "ring_acc": ring_acc, "ring_t": ring_t,
	}


func load_state(d: Dictionary) -> void:
	id = d.id
	species = d.species
	generation = d.generation
	parent = d.parent
	slen = d.slen
	rad = d.rad
	rest = d.rest
	defl = d.defl
	leaf = d.leaf
	tip = d.tip
	order = d.order
	bias = d.bias
	n = parent.size()
	for arr: Variant in [dvel, ang, ax, ay, bx, by, lgain, kids, strain, efx, efy, epx, epy, bfx, bfy, btq, sm, sfx, sfy, st0, smx, smy, dist, depth]:
		arr.resize(n)
		arr.fill(0)
	for i in n:
		if parent[i] >= 0:
			kids[parent[i]] += 1
	alive = d.alive
	energy = d.energy
	root = d.root
	nutrient = d.nutrient
	seed_bank = d.seed_bank
	seeds_ripe = d.seeds_ripe
	mature = d.mature
	age = d.age
	dead_for = d.dead_for
	health = d.health
	falls_survived = d.falls
	cause = d.cause
	rings = d.rings
	ring_acc = d.ring_acc
	ring_t = d.ring_t
	pose()
	_measure()
	_update_anchor()
	col_dirty = true
	awake = true
	still = 0


func _derive() -> void:
	var h := genome.h
	g_reach = lerpf(0.04, 1.0, h[Genome.REACH])
	fork_p = lerpf(0.02, 0.6, h[Genome.FORK])
	fork_ang = lerpf(0.3, 1.25, h[Genome.FORK])
	wood_k = lerpf(0.55, 1.6, h[Genome.WOOD])
	r_tip = 0.45 + 0.35 * wood_k
	leaf_w = lerpf(10.0, 28.0, h[Genome.LEAF])
	leaf_op = lerpf(0.6, 1.0, h[Genome.LEAF])
	leaf_keep = int(round(lerpf(6.0, 3.0, h[Genome.LEAF])))
	internode = lerpf(13.0, 26.0, h[Genome.LEAF])
	root_f = lerpf(0.05, 0.4, h[Genome.ROOT])
	seed_mass = lerpf(0.12, 1.0, h[Genome.SEED])
	seed_cost = 70.0 + 650.0 * h[Genome.SEED] * h[Genome.SEED]
	mature_vol = lerpf(100.0, 14000.0, pow(h[Genome.PATIENCE], 1.6))
	eff = lerpf(1.0, 0.55, h[Genome.THRIFT])
	upk = lerpf(1.0, 0.3, h[Genome.THRIFT])
	vmax = lerpf(6.5, 3.0, h[Genome.THRIFT])


func _add_seg(par: int, rel: float, ord: int, p_bias: float) -> int:
	parent.append(par)
	slen.append(2.0)
	rad.append(r_tip)
	rest.append(rel)
	defl.append(0.0)
	dvel.append(0.0)
	ang.append(0.0)
	ax.append(base_x)
	ay.append(base_y)
	bx.append(base_x)
	by.append(base_y)
	leaf.append(leaf_w)
	lgain.append(0.0)
	tip.append(1)
	kids.append(0)
	order.append(ord)
	bias.append(p_bias)
	strain.append(0.0)
	efx.append(0.0)
	efy.append(0.0)
	epx.append(0.0)
	epy.append(0.0)
	bfx.append(0.0)
	bfy.append(0.0)
	btq.append(0.0)
	sm.append(0.0)
	sfx.append(0.0)
	sfy.append(0.0)
	st0.append(0.0)
	smx.append(0.0)
	smy.append(0.0)
	dist.append(0.0)
	depth.append(0)
	if par >= 0:
		kids[par] += 1
	n += 1
	col_dirty = true
	return n - 1


## Forward kinematics only: where every segment sits for its current angles.
func pose() -> void:
	var top := base_y
	for i in n:
		var p := parent[i]
		var jx := base_x
		var jy := base_y
		var pa := 0.0
		if p >= 0:
			jx = bx[p]
			jy = by[p]
			pa = ang[p]
		var a := pa + rest[i] + defl[i]
		ang[i] = a
		ax[i] = jx
		ay[i] = jy
		bx[i] = jx + sin(a) * slen[i]
		by[i] = jy - cos(a) * slen[i]
		if by[i] < top:
			top = by[i]
	height = base_y - top
	dirty = true


# ---------------------------------------------------------------- growth ----

func grow(dt: float) -> void:
	age += dt
	if not alive:
		_decay(dt)
		return
	_measure()
	_update_anchor()
	upkeep = upk * (T.U_WOOD * volume + T.U_LEAF * leaf_total * leaf_op + T.U_ROOT * root)
	var net := income * eff - upkeep
	energy += net * dt
	ring_acc += maxf(net, 0.0) * dt
	ring_t += dt
	if ring_t >= 20.0:
		rings.append(ring_acc / ring_t)
		ring_acc = 0.0
		ring_t = 0.0
	if energy <= 0.0:
		die("starved")
		return
	if not mature and volume >= mature_vol:
		mature = true
		world.on_mature(self)

	var safety := upkeep * 4.0
	var budget := maxf(0.0, energy - safety) * (1.0 - exp(-dt * 0.9))
	if budget <= 0.0:
		_shed(dt)
		return

	# Where the surplus goes: seeds, roots, then wood and tips.
	var b_seed := budget * T.SEED_FRAC if mature else 0.0
	var root_target := root_f * 2.0 * (volume + 40.0)
	var b_root := budget * (root_f if root < root_target else 0.02)
	var b_shoot := budget - b_seed - b_root

	var spread := 14.0 + sqrt(root) * 1.6
	var fert := world.soil.fertility(base_x, spread)

	# Thickening: each segment wants a cross-section that fits the wood beyond it.
	var need_thick := 0.0
	for i in n:
		var tr := wood_k * (0.8 + 0.2 * pow(dist[i], 0.6))
		var r := rad[i]
		if tr > r:
			need_thick += T.C_WOOD * (tr * tr - r * r) * slen[i]
	need_thick = minf(need_thick, (60.0 + volume * 0.25) * dt)
	# Tips: brightly lit tips grow fastest; side branches defer to the leader.
	var need_tip := 0.0
	var full := leaf_w * leaf_op * 0.8
	for i in n:
		if tip[i] == 1:
			var vig := 0.2 + 0.8 * minf(1.0, lgain[i] / full)
			vig *= pow(0.8, order[i])
			sm[i] = vmax * vig * fert * dt          # scratch: length this tip wants
			need_tip += sm[i] * T.C_WOOD * rad[i] * rad[i] + sm[i] / internode * leaf_w * leaf_op * T.C_LEAF
	var need := need_thick + need_tip
	var scale := 1.0
	if need > b_shoot:
		scale = b_shoot / need
	var spent := 0.0
	var gained_vol := 0.0
	if need_thick > 0.0 and scale > 0.0:
		var total_thick := 0.0
		for i in n:
			var tr := wood_k * (0.8 + 0.2 * pow(dist[i], 0.6))
			var r := rad[i]
			if tr > r:
				total_thick += (tr * tr - r * r) * slen[i]
		var f := minf(1.0, need_thick * scale / maxf(total_thick * T.C_WOOD, 0.001))
		for i in n:
			var tr := wood_k * (0.8 + 0.2 * pow(dist[i], 0.6))
			var r := rad[i]
			if tr > r:
				var r2 := r * r + (tr * tr - r * r) * f
				gained_vol += (r2 - r * r) * slen[i]
				var nr := sqrt(r2)
				if nr > world.collider_r and (r <= world.collider_r or nr > r * 1.08):
					col_dirty = true
				rad[i] = nr
		spent += gained_vol * T.C_WOOD
	if need_tip > 0.0 and scale > 0.0:
		var count := n
		for i in count:
			if tip[i] == 1:
				var dl := sm[i] * scale
				slen[i] += dl
				gained_vol += dl * rad[i] * rad[i]
				spent += dl * T.C_WOOD * rad[i] * rad[i] + dl / internode * leaf_w * leaf_op * T.C_LEAF
				if slen[i] >= internode:
					var over := minf(slen[i] - internode, internode * 0.8)
					slen[i] = internode
					var before := n
					_node(i)
					if n > before:
						slen[n - 1] += over
	# Building wood takes richness out of the ground under the roots.
	var got := world.soil.take(base_x, spread, gained_vol)
	nutrient += got
	root += b_root / T.C_ROOT
	energy -= spent + b_root + b_seed
	if mature:
		seed_bank += b_seed
		while seed_bank >= seed_cost and seeds_ripe < 6:
			seed_bank -= seed_cost
			seeds_ripe += 1
			world.on_seeded(self)
		if seeds_ripe > 0 and world.rng.randf() < dt * 0.25 * seeds_ripe:
			_drop_seed()
	_shed(dt)
	if n > T.SEG_CAP - 3:
		_fuse()
	_resprout()
	pose()
	if by_min() <= world.lid_y + 6.0:
		lid_time += dt
		if lid_time > 3.0:
			world.on_lid(self)
	else:
		lid_time = 0.0


func by_min() -> float:
	return base_y - height


## Totals and per-segment reach, tips to root.
func _measure() -> void:
	volume = 0.0
	leaf_total = 0.0
	var i := n - 1
	for j in n:
		dist[j] = 0.0
		depth[j] = 0
	while i >= 0:
		volume += rad[i] * rad[i] * slen[i]
		leaf_total += leaf[i]
		var p := parent[i]
		if p >= 0:
			dist[p] += dist[i] + slen[i]
			if depth[i] + 1 > depth[p]:
				depth[p] = depth[i] + 1
		i -= 1


## A tip has finished its internode: continue it, and maybe fork.
func _node(i: int) -> void:
	if n >= T.SEG_CAP:
		return
	tip[i] = 0
	var rng := world.rng
	var cur := ang[i]
	# New growth leans toward the sun (Reach), toward brighter air, and away from down.
	var want := g_reach * clampf(world.sun_phi, -1.25, 1.25)
	var px := cos(cur) * 22.0
	var py := sin(cur) * 22.0
	var grad := world.light.sample(bx[i] + px, by[i] + py) - world.light.sample(bx[i] - px, by[i] - py)
	want += grad * (0.5 + g_reach)
	var b := bias[i]
	var ord := order[i]
	var forked := false
	if ord < T.MAX_ORDER and n < T.SEG_CAP - 2 and rng.randf() < fork_p * (1.0 if ord == 0 else 0.7):
		forked = true
		fork_side = -fork_side
		var h_fork := genome.h[Genome.FORK]
		if rng.randf() < h_fork * h_fork:
			# An even split: the leader gives way to two equal arms.
			var half := fork_ang * 0.5
			var c1 := _add_seg(i, clampf(wrapf(want + b - cur, -PI, PI) * 0.5, -0.5, 0.5) + half * fork_side + rng.randfn(0.0, 0.05), ord + 1, b * 0.8 + half * 0.8 * fork_side)
			var c2 := _add_seg(i, clampf(wrapf(want + b - cur, -PI, PI) * 0.5, -0.5, 0.5) - half * fork_side + rng.randfn(0.0, 0.05), ord + 1, b * 0.8 - half * 0.8 * fork_side)
			_place(c1)
			_place(c2)
			return
		var s := _add_seg(i, fork_ang * fork_side + rng.randfn(0.0, 0.08), ord + 1, fork_ang * 0.75 * fork_side)
		_place(s)
	var rel := clampf(wrapf(want + b - cur, -PI, PI) * 0.5, -0.5, 0.5) + rng.randfn(0.0, 0.04)
	var c := _add_seg(i, rel, ord, b * (0.85 if not forked else 0.7))
	_place(c)


func _place(i: int) -> void:
	var p := parent[i]
	ang[i] = ang[p] + rest[i]
	ax[i] = bx[p]
	ay[i] = by[p]
	bx[i] = ax[i] + sin(ang[i]) * slen[i]
	by[i] = ay[i] - cos(ang[i]) * slen[i]


## Old wood drops its leaves, and so do leaves that sit in deep shade.
func _shed(dt: float) -> void:
	var rng := world.rng
	var floor_gain := U_break()
	for i in n:
		if leaf[i] <= 0.0:
			continue
		var drop := false
		if depth[i] > leaf_keep:
			drop = rng.randf() < dt * 0.5
		elif lgain[i] < floor_gain and tip[i] == 0:
			drop = rng.randf() < dt * 0.12
		elif lgain[i] < floor_gain * 0.5 and tip[i] == 1 and n > 3:
			# A tip in the dark gives up; the branch stops there.
			if rng.randf() < dt * 0.05:
				drop = true
				tip[i] = 0
		if drop:
			world.soil.add(bx[i], bx[i], leaf[i] * leaf_op * T.LEAF_N * 0.5)
			world.on_leaf_drop(self, i)
			leaf[i] = 0.0
			dirty = true


## Light a leaf must earn to pay for itself.
func U_break() -> float:
	return leaf_w * leaf_op * T.U_LEAF * upk / eff


## A living plant with no growing tip wakes a bud at its highest point.
func _resprout() -> void:
	for i in n:
		if tip[i] == 1:
			return
	if energy < upkeep * 6.0 + 20.0:
		return
	var best := -1
	var best_y := 1e9
	for i in n:
		if kids[i] == 0 and by[i] < best_y:
			best_y = by[i]
			best = i
	if best < 0 or n >= T.SEG_CAP:
		return
	var c := _add_seg(best, clampf(-ang[best] * 0.6, -0.7, 0.7) + world.rng.randfn(0.0, 0.2), order[best], 0.0)
	_place(c)
	energy -= 10.0


## Old straight runs of bare wood fuse into one stiff piece, freeing segments.
func _fuse() -> void:
	var merged := 0
	var j := n - 1
	while j >= 1 and merged < 4:
		var i := parent[j]
		if i >= 0 and kids[i] == 1 and tip[j] == 0 and leaf[i] <= 0.0 and leaf[j] <= 0.0 and absf(rest[j]) < 0.22 and slen[i] + slen[j] <= 110.0:
			var li := slen[i]
			var lj := slen[j]
			var total := li + lj
			var bend := rest[j] + defl[j]
			rest[i] += bend * lj / total
			var vol := rad[i] * rad[i] * li + rad[j] * rad[j] * lj
			slen[i] = total
			rad[i] = sqrt(vol / total)
			for c in range(j + 1, n):
				if parent[c] == j:
					parent[c] = i
					rest[c] += bend * li / total
			kids[i] = kids[j]
			var keep := PackedByteArray()
			keep.resize(n)
			keep.fill(1)
			keep[j] = 0
			_compact(keep)
			merged += 1
		j -= 1
	if merged > 0:
		col_dirty = true


## Drop every segment whose keep flag is 0 and renumber the rest.
func _compact(keep: PackedByteArray) -> void:
	var remap := PackedInt32Array()
	remap.resize(n)
	var m := 0
	for i in n:
		if keep[i] == 1:
			remap[i] = m
			if m != i:
				parent[m] = parent[i]
				slen[m] = slen[i]
				rad[m] = rad[i]
				rest[m] = rest[i]
				defl[m] = defl[i]
				dvel[m] = dvel[i]
				ang[m] = ang[i]
				ax[m] = ax[i]
				ay[m] = ay[i]
				bx[m] = bx[i]
				by[m] = by[i]
				leaf[m] = leaf[i]
				lgain[m] = lgain[i]
				tip[m] = tip[i]
				order[m] = order[i]
				bias[m] = bias[i]
				strain[m] = strain[i]
				efx[m] = efx[i]
				efy[m] = efy[i]
				epx[m] = epx[i]
				epy[m] = epy[i]
				bfx[m] = bfx[i]
				bfy[m] = bfy[i]
				btq[m] = btq[i]
			m += 1
		else:
			remap[i] = -1
	n = m
	for arr: Variant in [parent, slen, rad, rest, defl, dvel, ang, ax, ay, bx, by, leaf, lgain, tip, kids, order, bias, strain, efx, efy, epx, epy, bfx, bfy, btq, sm, sfx, sfy, st0, smx, smy, dist, depth]:
		arr.resize(n)
	for i in n:
		kids[i] = 0
	for i in n:
		var p := parent[i]
		if p >= 0:
			parent[i] = remap[p]
			kids[parent[i]] += 1
	col_dirty = true
	dirty = true


## Indices of segment i and everything that grows from it.
func subtree(i: int) -> PackedInt32Array:
	var mark := PackedByteArray()
	mark.resize(n)
	mark.fill(0)
	mark[i] = 1
	var out := PackedInt32Array([i])
	for j in range(i + 1, n):
		if mark[parent[j]] == 1:
			mark[j] = 1
			out.append(j)
	return out


## Remove segment i and everything beyond it (the world has already made a log of it).
func remove_subtree(i: int) -> void:
	var keep := PackedByteArray()
	keep.resize(n)
	keep.fill(1)
	keep[i] = 0
	for j in range(i + 1, n):
		if keep[parent[j]] == 0:
			keep[j] = 0
	_compact(keep)
	_measure()
	pose()
	awake = true
	still = 0


func _drop_seed() -> void:
	var picks: Array[int] = []
	for i in n:
		if leaf[i] > 0.0:
			picks.append(i)
	var i := n - 1
	if not picks.is_empty():
		i = picks[world.rng.randi() % picks.size()]
	seeds_ripe -= 1
	world.spawn_seed(genome.child(world.rng), bx[i], by[i], world.rng.randf_range(-12.0, 12.0), world.rng.randf_range(-10.0, 5.0), self)


func die(why: String) -> void:
	if not alive:
		return
	alive = false
	cause = why
	for i in n:
		tip[i] = 0
	dirty = true
	world.on_death(self)


## A dead plant stands as a snag: leaves fall, the wood weakens, and it comes down.
func _decay(dt: float) -> void:
	dead_for += dt
	_measure()
	_update_anchor()
	var rng := world.rng
	for i in n:
		if leaf[i] > 0.0 and rng.randf() < dt * 0.2:
			world.soil.add(bx[i], bx[i], leaf[i] * leaf_op * T.LEAF_N)
			world.on_leaf_drop(self, i)
			leaf[i] = 0.0
			dirty = true
	var stand := 30.0 + sqrt(volume) * 0.6
	health = maxf(0.04, 1.0 - dead_for / stand)
	if volume < 150.0 and dead_for > 4.0:
		world.crumble(self)
	elif dead_for > stand * 1.15:
		world.break_plant(self, 0, false)
	else:
		awake = true


# ------------------------------------------------------------- mechanics ----

## One step of the bend-and-break solver. Returns the joint that failed, or -1.
func mech(dt: float, wind: float) -> int:
	var soil := world.soil
	var g := T.GRAV
	for j in n:
		sm[j] = 0.0
		sfx[j] = 0.0
		sfy[j] = 0.0
		st0[j] = 0.0
		smx[j] = 0.0
		smy[j] = 0.0
	# Pass 1, tips to root: total force and torque carried by each joint.
	var i := n - 1
	while i >= 0:
		var r := rad[i]
		var mw := T.RHO * r * r * slen[i]
		var ml := T.LEAF_M * leaf[i] * leaf_op
		var cx := (ax[i] + bx[i]) * 0.5
		var cy := (ay[i] + by[i]) * 0.5
		var wfx := wind * (leaf[i] * leaf_op * 3.0 + r * slen[i] * 0.15)
		var fx := efx[i] + bfx[i] + wfx
		var fy := efy[i] + bfy[i] + (mw + ml) * g
		var t0 := cx * mw * g + bx[i] * ml * g + (epx[i] * efy[i] - epy[i] * efx[i]) + btq[i] - by[i] * wfx
		efx[i] *= 1.0 - T.PUSH_GAIN
		efy[i] *= 1.0 - T.PUSH_GAIN
		bfx[i] = 0.0
		bfy[i] = 0.0
		btq[i] = 0.0
		sm[i] += mw + ml
		smx[i] += cx * mw + bx[i] * ml
		smy[i] += cy * mw + by[i] * ml
		sfx[i] += fx
		sfy[i] += fy
		st0[i] += t0
		# A branch lying on the soil is held up by it.
		var gy := soil.ground_y(bx[i])
		if by[i] > gy:
			var lift := minf((by[i] - gy) * T.GROUND_K, 1.4) * sfy[i]
			if lift > 0.0:
				sfy[i] -= lift
				st0[i] -= bx[i] * lift
		var p := parent[i]
		if p >= 0:
			sm[p] += sm[i]
			smx[p] += smx[i]
			smy[p] += smy[i]
			sfx[p] += sfx[i]
			sfy[p] += sfy[i]
			st0[p] += st0[i]
		i -= 1
	# Pass 2, root to tips: bend each joint toward where its load puts it.
	var worst := -1
	var worst_s := 1.0
	var moving := 0.0
	var uprooting := false
	var top := base_y
	var strength := T.SIGMA * health
	max_strain = 0.0
	for k in n:
		var p := parent[k]
		var jx := base_x
		var jy := base_y
		var pa := 0.0
		if p >= 0:
			jx = bx[p]
			jy = by[p]
			pa = ang[p]
		var tau := st0[k] - (jx * sfy[k] - jy * sfx[k])
		var r := rad[k]
		var r3 := r * r * r
		var stiff := T.E * r3 * r / maxf(slen[k], 8.0)
		var dx := smx[k] / sm[k] - jx
		var dy := smy[k] / sm[k] - jy
		var inertia := sm[k] * (dx * dx + dy * dy) * 1.3 + 1.0
		var wn := clampf(sqrt(stiff / inertia), 1.2, 13.0)
		var target := clampf(tau / stiff, -1.35, 1.35)
		var d := defl[k]
		var v := dvel[k]
		v += (wn * wn * (target - d) - 2.0 * T.ZETA * wn * v) * dt
		d += v * dt
		var s := absf(tau) / (strength * r3)
		strain[k] = s
		if s > max_strain:
			max_strain = s
		if s > worst_s:
			worst_s = s
			worst = k
		if s > 0.4:
			# Strained wood slowly takes a set: this is how trunks come to lean.
			var c := d * minf(1.0, T.CREEP * (s - 0.4) * dt)
			rest[k] += c
			d -= c
		if k == 0 and s > anchor_k:
			# The root plate is lifting: the whole plant tilts before it lets go.
			uprooting = true
			var over := minf(s / anchor_k - 1.0, 2.0)
			rest[0] += signf(tau) * (0.12 + 0.5 * over) * dt
			if s / anchor_k > worst_s:
				worst_s = s / anchor_k
				worst = 0
		defl[k] = d
		dvel[k] = v
		var mv := absf(v) + absf(target - d) * 0.5
		if mv > moving:
			moving = mv
		var a := pa + rest[k] + d
		ang[k] = a
		ax[k] = jx
		ay[k] = jy
		bx[k] = jx + sin(a) * slen[k]
		by[k] = jy - cos(a) * slen[k]
		if by[k] < top:
			top = by[k]
	height = base_y - top
	# An overloaded joint yields for a moment before it breaks, so a brief
	# knock is survivable and a real overload creaks first.
	fail_uproot = false
	if worst >= 0:
		if worst != fail_at:
			fail_at = worst
			fail_acc = 0.0
		fail_acc += minf(worst_s - 1.0, 4.0) * dt
		still = 0
		if fail_acc < T.YIELD_TIME:
			worst = -1
		else:
			fail_uproot = worst == 0 and uprooting and anchor_k < 1.0
			fail_at = -1
			fail_acc = 0.0
	elif fail_acc > 0.0:
		fail_acc = maxf(0.0, fail_acc - dt * 0.5)
	if moving < 0.004:
		still += 1
		if still > 24:
			awake = false
			for k in n:
				dvel[k] = 0.0
	else:
		still = 0
		dirty = true
	return worst


## How much of the base wood's breaking load the roots can hold. Below 1 the
## plant uproots before its trunk snaps; wet ground grips less.
func anchor_ratio() -> float:
	return anchor_k


func _update_anchor() -> void:
	var grip := 1.0 - 0.65 * world.soil.wetness(base_x)
	anchor_k = (0.35 + 3.0 * root / (volume + 40.0)) * grip


## The segment with a collider nearest a point.
func seg_near(at: Vector2) -> int:
	var best := 0
	var best_d := 1e18
	for i in col_seg:
		if i >= n:
			continue
		var pt := Geometry2D.get_closest_point_to_segment(at, Vector2(ax[i], ay[i]), Vector2(bx[i], by[i]))
		var d := pt.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


func push(i: int, px: float, py: float, fx: float, fy: float) -> void:
	if i >= n:
		return
	# Outside forces are smoothed over about a fifth of a second, so a log
	# resting on a stem settles instead of feeding back into a buzz.
	efx[i] += fx * T.PUSH_GAIN
	efy[i] += fy * T.PUSH_GAIN
	epx[i] = px
	epy[i] = py
	awake = true
	still = 0


## A force from a prop, tie or vine: springs must act at once, because a
## delayed spring pumps energy into a sway instead of taking it out.
func brace(i: int, px: float, py: float, fx: float, fy: float) -> void:
	if i >= n:
		return
	bfx[i] += fx
	bfy[i] += fy
	btq[i] += px * fy - py * fx
	awake = true
	still = 0


# ------------------------------------------------------------- colliders ----

## Move the stem colliders to match the plant. Plants only ever collide with
## fallen wood, and moving a collider is not free, so this happens only while
## moving wood is near, and only for segments that have moved enough to matter.
func sync_body() -> void:
	if not body.is_valid():
		return
	if not world.wood_near(base_x, height + 40.0):
		return
	if col_dirty:
		_rebuild_body()
		return
	for c in col_seg.size():
		var i := col_seg[c]
		if i >= n:
			col_dirty = true
			return
		var cx := (ax[i] + bx[i]) * 0.5
		var cy := (ay[i] + by[i]) * 0.5
		var l := slen[i]
		if absf(l - col_l[c]) > col_l[c] * 0.15 + 1.0:
			col_dirty = true
		var moved := absf(cx - col_x[c]) + absf(cy - col_y[c]) + absf(wrapf(ang[i] - col_a[c], -PI, PI)) * l * 0.5
		if moved > 0.35:
			col_x[c] = cx
			col_y[c] = cy
			col_a[c] = ang[i]
			PhysicsServer2D.body_set_shape_transform(body, c, Transform2D(ang[i], Vector2(cx, cy)))


func _rebuild_body() -> void:
	col_dirty = false
	PhysicsServer2D.body_clear_shapes(body)
	for s in col_shapes:
		PhysicsServer2D.free_rid(s)
	col_shapes.clear()
	col_seg.clear()
	col_x.clear()
	col_y.clear()
	col_a.clear()
	col_l.clear()
	for i in n:
		if rad[i] >= world.collider_r and slen[i] > 4.0:
			var shape := PhysicsServer2D.rectangle_shape_create()
			PhysicsServer2D.shape_set_data(shape, Vector2(rad[i], slen[i] * 0.5))
			var cx := (ax[i] + bx[i]) * 0.5
			var cy := (ay[i] + by[i]) * 0.5
			PhysicsServer2D.body_add_shape(body, shape, Transform2D(ang[i], Vector2(cx, cy)))
			col_shapes.append(shape)
			col_seg.append(i)
			col_x.append(cx)
			col_y.append(cy)
			col_a.append(ang[i])
			col_l.append(slen[i])


func free_body() -> void:
	if body.is_valid():
		PhysicsServer2D.free_rid(body)
		body = RID()
	for s in col_shapes:
		PhysicsServer2D.free_rid(s)
	col_shapes.clear()
	col_seg.clear()
