class_name Fx
extends Node2D
## Seeds, drifting leaves, dust, and the pulses of glow that run down a stem
## while a plant is earning.

class Bit:
	var pos := Vector2()
	var vel := Vector2()
	var life := 1.0
	var span := 1.0
	var size := 4.0
	var col := Color.WHITE
	var kind := 0      # 0 leaf, 1 dust, 2 spark
	var rot := 0.0
	var spin := 0.0

var world: World
var bits: Array[Bit] = []
var glow_node: Node2D
var leaf_tex: Texture2D
var trail := PackedVector2Array()
var trail_life := 0.0
var preview := PackedVector2Array()
var ring_at := Vector2()
var ring_data := PackedFloat32Array()
var ring_life := 0.0
var ring_size := 20.0


func setup(w: World) -> void:
	world = w
	leaf_tex = Art.leaf()
	glow_node = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_node.material = mat
	glow_node.draw.connect(_draw_glow)
	add_child(glow_node)
	world.happened.connect(_on_event)


func _on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"leaf":
			if bits.size() < 400:
				_leaf(Vector2(d.x, d.y), d.hue, d.dead)
		"litter":
			for k in mini(8, 2 + int(d.leaves / 12.0)):
				_leaf(Vector2(d.x, d.y) + Vector2(randf_range(-10, 10), randf_range(-14, 6)), d.hue, true)
		"impact":
			var power := clampf(d.speed / 160.0, 0.3, 2.5)
			for k in int(6 + 10 * power):
				var b := Bit.new()
				b.kind = 1
				b.pos = Vector2(d.x + randf_range(-d.length * 0.2, d.length * 0.2), d.y - 2.0)
				b.vel = Vector2(randf_range(-50, 50), randf_range(-70, -15)) * power
				b.span = randf_range(0.7, 1.8)
				b.life = b.span
				b.size = randf_range(4, 10) * power
				b.col = Color(0.62, 0.55, 0.44, 0.2)
				bits.append(b)
			for k in int(4 + 6 * power):
				_leaf(Vector2(d.x + randf_range(-d.length * 0.3, d.length * 0.3), d.y - randf_range(4, 30)), d.hue, false, Vector2(randf_range(-80, 80), randf_range(-140, -30)) * power)
		"fall", "break":
			var chips := 5 if kind == "fall" else 2
			for k in chips:
				var b := Bit.new()
				b.kind = 2
				b.pos = Vector2(d.x, d.y)
				b.vel = Vector2(randf_range(-70, 70), randf_range(-90, -10))
				b.span = randf_range(0.4, 0.9)
				b.life = b.span
				b.size = randf_range(1.5, 3.0)
				b.col = Color(1.0, 0.88, 0.62, 0.9)
				bits.append(b)
		"sprout":
			var b := Bit.new()
			b.kind = 2
			b.pos = Vector2(d.x, d.y - 2.0)
			b.vel = Vector2(0, -14)
			b.span = 0.7
			b.life = 0.7
			b.size = 2.2
			b.col = Color(0.8, 1.0, 0.6, 0.8)
			bits.append(b)
		"rotted":
			for k in 5:
				var b := Bit.new()
				b.kind = 1
				b.pos = Vector2(d.x + randf_range(-20, 20), d.y)
				b.vel = Vector2(randf_range(-12, 12), randf_range(-22, -6))
				b.span = randf_range(1.0, 2.0)
				b.life = b.span
				b.size = randf_range(5, 10)
				b.col = Color(0.3, 0.26, 0.2, 0.3)
				bits.append(b)


func _leaf(at: Vector2, hue: float, dead: bool, vel := Vector2.ZERO) -> void:
	var b := Bit.new()
	b.kind = 0
	b.pos = at
	b.vel = vel + Vector2(randf_range(-10, 10), randf_range(0, 12))
	b.span = randf_range(3.0, 6.0)
	b.life = b.span
	b.size = randf_range(8, 15)
	b.col = Color(0.55, 0.4, 0.2) if dead else Color.from_hsv(hue, 0.5, 0.7)
	b.rot = randf() * TAU
	b.spin = randf_range(-3, 3)
	bits.append(b)


func sparkle(at: Vector2, hue: float) -> void:
	for k in 7:
		var b := Bit.new()
		b.kind = 2
		b.pos = at
		b.vel = Vector2.from_angle(randf() * TAU) * randf_range(20, 70)
		b.span = randf_range(0.4, 0.8)
		b.life = b.span
		b.size = randf_range(1.2, 2.4)
		b.col = Color.from_hsv(hue, 0.3, 1.0, 0.9)
		bits.append(b)


func rain(at: Vector2) -> void:
	for k in 2:
		var b := Bit.new()
		b.kind = 3
		b.pos = at + Vector2(randf_range(-38, 38), randf_range(-20, 10))
		b.vel = Vector2(world.wind_at(at.x) * 0.5, randf_range(420, 560))
		b.span = 2.0
		b.life = 2.0
		b.size = randf_range(7, 13)
		b.col = Color(0.7, 0.86, 1.0, 0.55)
		bits.append(b)


## A cut stump shows the plant's life in its rings: wide for bright years, narrow for shaded ones.
func show_rings(at: Vector2, rings: PackedFloat32Array, radius: float) -> void:
	ring_at = at + Vector2(0, -46)
	ring_data = rings.slice(maxi(0, rings.size() - 14))
	ring_life = 5.0
	ring_size = clampf(radius * 3.2, 22.0, 46.0)


func swipe(from: Vector2, to: Vector2) -> void:
	if trail.is_empty():
		trail.append(from)
	trail.append(to)
	if trail.size() > 24:
		trail = trail.slice(trail.size() - 24)
	trail_life = 0.25


func _process(delta: float) -> void:
	var soil := world.soil
	var i := bits.size() - 1
	while i >= 0:
		var b := bits[i]
		b.life -= delta
		if b.life <= 0.0:
			bits[i] = bits[bits.size() - 1]
			bits.pop_back()
		else:
			if b.kind == 0:
				b.vel.y += (38.0 - b.vel.y) * minf(1.0, delta * 2.0)
				b.vel.x += (sin(b.life * 3.0 + b.rot) * 30.0 + world.wind_at(b.pos.x) * 2.0 - b.vel.x) * minf(1.0, delta * 2.0)
				b.rot += b.spin * delta
				var gy := soil.ground_y(clampf(b.pos.x, 0.0, world.jar_w))
				if b.pos.y >= gy - 1.0:
					b.vel = Vector2.ZERO
					b.spin = 0.0
					b.pos.y = gy - 1.0
					b.life = minf(b.life, 1.5)
			elif b.kind == 1:
				b.vel *= 1.0 - minf(1.0, delta * 2.2)
				b.size += delta * 9.0
			elif b.kind == 3:
				if b.pos.y >= soil.ground_y(clampf(b.pos.x, 0.0, world.jar_w)):
					b.life = 0.0
			else:
				b.vel.y += 240.0 * delta
			b.pos += b.vel * delta
		i -= 1
	if ring_life > 0.0:
		ring_life -= delta
	if trail_life > 0.0:
		trail_life -= delta
		if trail_life <= 0.0:
			trail.clear()
	queue_redraw()
	glow_node.queue_redraw()


func _draw() -> void:
	# Seeds: a dot, with a tuft on the ones light enough to drift.
	for s in world.seeds:
		var c := Color.from_hsv(s.genome.hue, 0.35, 0.92 if not s.resting else 0.6)
		var r := 1.3 + 2.2 * s.mass
		if s.resting:
			draw_circle(Vector2(s.x, s.y - r * 0.4), r * 0.8, c)
		else:
			draw_circle(Vector2(s.x, s.y), r, c)
			if s.mass < 0.5:
				var t := Color(1, 1, 1, 0.5)
				draw_line(Vector2(s.x, s.y), Vector2(s.x - 4, s.y - 6), t, 1.0)
				draw_line(Vector2(s.x, s.y), Vector2(s.x + 4, s.y - 6), t, 1.0)
				draw_line(Vector2(s.x, s.y), Vector2(s.x, s.y - 7), t, 1.0)
	for b in bits:
		var a := clampf(b.life / b.span * 2.0, 0.0, 1.0)
		var c := b.col
		c.a *= a
		if b.kind == 0:
			draw_set_transform(b.pos, b.rot, Vector2(1.0, cos(b.life * 4.0 + b.rot) * 0.7 + 0.3))
			draw_texture_rect(leaf_tex, Rect2(-b.size * 0.5, -b.size * 0.24, b.size, b.size * 0.48), false, c)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif b.kind == 3:
			draw_line(b.pos, b.pos - b.vel.normalized() * b.size, c, 1.3)
		else:
			draw_circle(b.pos, b.size, c)
	# Props and ties.
	for br in world.braces:
		var strain := clampf(br.load, 0.0, 1.0)
		if br.grip:
			# A tendril: a small curl where the vine holds its host.
			draw_arc(br.b_at, 3.0, 0.0, TAU * 0.8, 10, Color.from_hsv(br.a.genome.hue, 0.5, 0.75, 0.9), 1.2)
			draw_line(br.a_at, br.b_at, Color.from_hsv(br.a.genome.hue, 0.45, 0.6, 0.7), 1.0)
		elif br.tie:
			var mid := (br.a_at + br.b_at) * 0.5
			var slack := maxf(0.0, br.length - br.a_at.distance_to(br.b_at))
			mid.y += slack * 1.5 + 2.0
			var line := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				line.append(br.a_at.lerp(mid, t).lerp(mid.lerp(br.b_at, t), t))
			draw_polyline(line, Color(0.92, 0.86, 0.7, 0.85).lerp(Color(1.0, 0.4, 0.3), strain), 1.4)
			draw_circle(br.a_at, 2.2, Color(0.92, 0.86, 0.7))
			draw_circle(br.b_at, 2.2, Color(0.92, 0.86, 0.7))
		else:
			draw_line(br.b_at, br.a_at, Color(0.62, 0.47, 0.3).lerp(Color(1.0, 0.75, 0.5), strain), 4.0)
			draw_circle(br.b_at, 3.0, Color(0.5, 0.38, 0.25))
	if ring_life > 0.0 and ring_data.size() > 0:
		var a := clampf(ring_life, 0.0, 1.0)
		var total := 0.0
		var peak := 0.001
		for v in ring_data:
			peak = maxf(peak, v)
		for v in ring_data:
			total += 0.35 + 0.65 * v / peak
		draw_circle(ring_at, ring_size + 3.0, Color(0.25, 0.18, 0.12, a))
		draw_circle(ring_at, ring_size, Color(0.87, 0.74, 0.52, a))
		var r := 0.0
		for v in ring_data:
			r += (0.35 + 0.65 * v / peak) / total * ring_size
			draw_arc(ring_at, r, 0.0, TAU, 40, Color(0.45, 0.3, 0.18, a * 0.85), 1.0, true)
		draw_circle(ring_at, 1.5, Color(0.35, 0.22, 0.14, a))
	if preview.size() == 2:
		draw_line(preview[0], preview[1], Color(1, 1, 1, 0.5), 1.4)
	if trail.size() >= 2:
		draw_polyline(trail, Color(1, 1, 1, clampf(trail_life * 4.0, 0.0, 0.8)), 2.0)


func _draw_glow() -> void:
	# Pulses of glow run from lit leaves down to the roots of plants in surplus.
	var g := Art.glow()
	var now := world.clock
	for p in world.plants:
		if not p.alive or p.removed or p.n < 2:
			continue
		var net := p.income * p.eff - p.upkeep
		if net <= 0.5:
			continue
		var pulses := clampi(1 + int(net / 30.0), 1, 3)
		for k in pulses:
			var phase := now * 0.45 + p.id * 0.37 + k * 0.41
			var cycle := int(floor(phase))
			var f := phase - cycle
			# Pick a leaf for this cycle, then walk the pulse down toward the root.
			var pick := (p.id * 7919 + cycle * 104729 + k * 31) % p.n
			var seg := -1
			for j in p.n:
				var c := (pick + j) % p.n
				if p.leaf[c] > 0.0 and p.lgain[c] > 0.0:
					seg = c
					break
			if seg < 0:
				continue
			var total := 0.0
			var c2 := seg
			while c2 >= 0:
				total += p.slen[c2]
				c2 = p.parent[c2]
			var want := f * total
			c2 = seg
			while c2 >= 0 and want > p.slen[c2]:
				want -= p.slen[c2]
				c2 = p.parent[c2]
			if c2 < 0:
				continue
			var t := want / maxf(p.slen[c2], 0.01)
			var at := Vector2(lerpf(p.bx[c2], p.ax[c2], t), lerpf(p.by[c2], p.ay[c2], t))
			var size := 7.0 + p.rad[c2] * 2.2
			var alpha := sin(f * PI) * 0.75
			glow_node.draw_texture_rect(g, Rect2(at - Vector2(size, size), Vector2(size, size) * 2.0), false, Color(1.0, 0.92, 0.6, alpha))
