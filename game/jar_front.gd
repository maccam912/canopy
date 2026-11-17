class_name JarFront
extends Node2D
## In front of the plants: the soil, the room around the jar, the glass and the sun.

const ROOM := Color(0.045, 0.06, 0.07)

var world: World
var acc := 1.0
var soil_node: Node2D
var sun_node: Node2D
var shown_phi := 99.0


var cracks: Node2D
var pressure := 0.0
var press_x := 0.0
var press_acc := 0.0


func setup(w: World) -> void:
	world = w
	cracks = Node2D.new()
	cracks.draw.connect(_draw_cracks)
	add_child(cracks)
	soil_node = Node2D.new()
	soil_node.draw.connect(_draw_soil)
	add_child(soil_node)
	move_child(soil_node, 0)
	sun_node = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sun_node.material = mat
	sun_node.draw.connect(_draw_sun)
	add_child(sun_node)


## The sun rides a rail that hugs the outside of the jar: across the lid and
## down either wall.
func sun_pos(phi: float) -> Vector2:
	var th := phi * 1.15
	var a := world.jar_w * 0.5 + 62.0
	var b := world.jar_h + 70.0
	return Vector2(world.jar_w * 0.5 + signf(sin(th)) * pow(absf(sin(th)), 0.25) * a, -pow(absf(cos(th)), 0.25) * b)


## The sun angle that puts the sun nearest a point.
func phi_at(at: Vector2) -> float:
	var a := world.jar_w * 0.5 + 62.0
	var b := world.jar_h + 70.0
	var x := clampf((at.x - world.jar_w * 0.5) / a, -1.0, 1.0)
	var y := clampf(-at.y / b, 0.0, 1.0)
	var th := atan2(signf(x) * pow(absf(x), 4.0), pow(y, 4.0))
	return clampf(th / 1.15, -1.25, 1.25)


func _process(delta: float) -> void:
	press_acc += delta
	if press_acc > 0.25:
		press_acc = 0.0
		var p := 1.0 if world.cracked else world.lid_pressure()
		if world.cracked:
			press_x = world.crack_x
		elif p > 0.0:
			for pl in world.plants:
				if pl.alive and not pl.removed and pl.lid_time > 0.0:
					press_x = pl.base_x if pl.n == 0 else pl.bx[pl.n - 1]
					break
		if absf(p - pressure) > 0.01:
			pressure = p
			cracks.queue_redraw()
	acc += delta
	if acc > 0.5:
		acc = 0.0
		soil_node.queue_redraw()
	if absf(shown_phi - world.sun_phi) > 0.0005:
		shown_phi = world.sun_phi
		sun_node.queue_redraw()


func _draw_soil() -> void:
	var s := world.soil
	var poor := Color(0.40, 0.34, 0.26)
	var loam := Color(0.13, 0.085, 0.06)
	var wet := Color(0.07, 0.09, 0.13)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in s.n + 1:
		var c := mini(i, s.n - 1)
		var f := clampf(s.rich[c] / (T.RICH0 * 1.8), 0.0, 1.0)
		var col := poor.lerp(loam, f).lerp(wet, s.wet[c] * 0.7)
		pts.append(Vector2(i * Soil.CW, s.height[i]))
		cols.append(col)
	var line := pts.duplicate()
	for i in range(s.n, -1, -1):
		pts.append(Vector2(i * Soil.CW, 92.0))
		cols.append(Color(0.07, 0.05, 0.04))
	soil_node.draw_polygon(pts, cols)
	soil_node.draw_polyline(line, Color(0.30, 0.34, 0.22, 0.9), 2.5)


func _draw() -> void:
	var w := world.jar_w
	var h := world.jar_h
	var far := 6000.0
	var kind := world.kind
	var room := ROOM
	if kind == "hillside":
		room = Color(0.06, 0.09, 0.1)
	# The room outside the home hides anything that pokes past the glass.
	draw_rect(Rect2(-far, -far, far, far * 2.0), room)
	draw_rect(Rect2(w, -far, far, far * 2.0), room)
	draw_rect(Rect2(-far, -far, far * 2.0 + w, far - h), room)
	draw_rect(Rect2(-far, 92.0, far * 2.0 + w, far), room)
	match kind:
		"hillside":
			# No glass and no lid (the hills are drawn behind the plants).
			draw_rect(Rect2(-300.0, 92.0, w + 600.0, 30.0), Color(0.12, 0.09, 0.06))
			return
		"tank":
			draw_rect(Rect2(-260.0, 92.0, w + 520.0, 16.0), Color(0.16, 0.16, 0.17))
			var frame := Color(0.22, 0.24, 0.25)
			draw_rect(Rect2(-12.0, -h - 12.0, w + 24.0, h + 104.0), frame, false, 12.0)
			draw_rect(Rect2(0.0, -h, w, h + 92.0), Color(0.75, 0.92, 0.95, 0.04))
			draw_rect(Rect2(20.0, -h + 20.0, 9.0, h * 0.6), Color(1, 1, 1, 0.05))
			draw_rect(Rect2(-18.0, -h - 26.0, w + 36.0, 14.0), Color(0.18, 0.19, 0.2))
		"greenhouse":
			draw_rect(Rect2(-260.0, 92.0, w + 520.0, 18.0), Color(0.3, 0.27, 0.22))
			var mull := Color(0.82, 0.85, 0.8, 0.55)
			var panes := int(round(w / 350.0))
			for k in panes + 1:
				var x := w * k / panes
				draw_line(Vector2(x, -h), Vector2(x, 92.0), mull, 3.0 if k % panes == 0 else 1.6)
			draw_line(Vector2(0, -h * 0.5), Vector2(w, -h * 0.5), Color(0.82, 0.85, 0.8, 0.25), 1.2)
			# A shallow peaked roof.
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -h), Vector2(w * 0.5, -h - 60.0), Vector2(w + 10, -h), Vector2(w + 10, -h - 6.0), Vector2(w * 0.5, -h - 66.0), Vector2(-10, -h - 6.0)]), Color(0.82, 0.85, 0.8, 0.7))
			draw_rect(Rect2(-5.0, -h, w + 10.0, h + 97.0), Color(0.8, 0.9, 0.85, 0.3), false, 4.0)
		_:
			# Shelf.
			draw_rect(Rect2(-260.0, 92.0, w + 520.0, 16.0), Color(0.19, 0.13, 0.09))
			draw_rect(Rect2(-260.0, 108.0, w + 520.0, 5.0), Color(0.10, 0.07, 0.05))
			# Glass.
			var glass := Color(0.72, 0.9, 0.88, 0.34)
			draw_rect(Rect2(-5.0, -h - 5.0, w + 10.0, h + 97.0), glass, false, 5.0)
			draw_rect(Rect2(0.0, -h, 16.0, h + 92.0), Color(1, 1, 1, 0.035))
			draw_rect(Rect2(26.0, -h + 30.0, 7.0, h * 0.55), Color(1, 1, 1, 0.06))
			draw_rect(Rect2(w - 22.0, -h + 60.0, 5.0, h * 0.4), Color(1, 1, 1, 0.04))
			# Lid.
			draw_rect(Rect2(-14.0, -h - 20.0, w + 28.0, 18.0), Color(0.33, 0.25, 0.17))
			draw_rect(Rect2(-14.0, -h - 20.0, w + 28.0, 4.0), Color(0.45, 0.35, 0.24))
	# The sun's rail.
	var arc := PackedVector2Array()
	for k in 97:
		arc.append(sun_pos(lerpf(-1.25, 1.25, k / 96.0)))
	draw_polyline(arc, Color(1.0, 0.9, 0.6, 0.10), 2.0)


## Cracks spread through the glass from where a plant presses on the lid.
func _draw_cracks() -> void:
	if pressure <= 0.02 or not world.has_lid:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(press_x)
	var origin := Vector2(press_x, world.lid_y)
	var col := Color(0.9, 0.97, 1.0, 0.75)
	for arm in 7:
		var reach := pressure * rng.randf_range(60.0, 220.0)
		var dir := Vector2.from_angle(rng.randf_range(0.15, PI - 0.15))
		var pts := PackedVector2Array([origin])
		var at := origin
		var steps := 6
		for k in steps:
			dir = dir.rotated(rng.randf_range(-0.6, 0.6))
			at += dir * reach / steps
			pts.append(at)
		cracks.draw_polyline(pts, col, 1.4 if arm < 3 else 0.9, true)


func _draw_sun() -> void:
	var at := sun_pos(world.sun_phi)
	var g := Art.glow()
	sun_node.draw_texture_rect(g, Rect2(at - Vector2(150, 150), Vector2(300, 300)), false, Color(1.0, 0.8, 0.45, 0.5))
	sun_node.draw_texture_rect(g, Rect2(at - Vector2(70, 70), Vector2(140, 140)), false, Color(1.0, 0.92, 0.7, 0.9))
	sun_node.draw_circle(at, 22.0, Color(1.0, 0.96, 0.82))
