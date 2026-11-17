class_name VisitorView
extends Node2D
## Draws the visitors: fireflies glow, everything else is a small dark shape.

## The jar is shown small on a phone, so creatures are drawn larger than life.
const SIZE := 2.0

var world: World
var glow: Node2D


func setup(w: World) -> void:
	world = w
	glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.draw.connect(_draw_glow)
	add_child(glow)


func _process(_delta: float) -> void:
	queue_redraw()
	glow.queue_redraw()


func _draw() -> void:
	var now := world.clock
	for v in world.visitors.list:
		match v.kind:
			Visitors.BEETLE:
				var dir := v.goal.normalized() if v.goal.length() > 0.01 else Vector2.RIGHT
				var a := dir.angle()
				draw_set_transform(v.pos, a, Vector2.ONE * 1.5)
				draw_circle(Vector2.ZERO, 2.6, Color(0.12, 0.1, 0.08))
				draw_circle(Vector2(2.6 * v.face, 0), 1.4, Color(0.08, 0.07, 0.06))
				draw_line(Vector2(-1.5, -0.4), Vector2(1.5, -0.4), Color(0.35, 0.45, 0.4, 0.8), 0.6)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			Visitors.BIRD:
				_bird(v, now)
			Visitors.SQUIRREL:
				_squirrel(v, now)
			Visitors.OWL:
				_owl(v, now)


func _bird(v: Visitors.Visitor, now: float) -> void:
	var body := Color.from_hsv(v.hue, 0.35, 0.32)
	var f := v.face
	var p := v.pos
	var flying := v.state != "sit"
	draw_set_transform(p, 0.0, Vector2(f, 1.0) * SIZE)
	draw_circle(Vector2(0, 0), 4.2, body)
	draw_circle(Vector2(4.5, -2.5), 2.8, body)
	draw_colored_polygon(PackedVector2Array([Vector2(7, -3), Vector2(10, -2.2), Vector2(7, -1.4)]), Color(0.85, 0.6, 0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -1), Vector2(-10, -3), Vector2(-9, 1)]), body)
	draw_circle(Vector2(5.4, -3.2), 0.7, Color(0.95, 0.92, 0.8))
	if flying:
		var flap := sin(now * 18.0 + v.phase) * 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(-2, -1), Vector2(2, -1), Vector2(-1, -2 - flap)]), body.darkened(0.2))
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-3, -2), Vector2(2, -3), Vector2(-4, 1)]), body.darkened(0.25))
	if v.carrying != null:
		draw_circle(Vector2(8.5, 0), 1.8, Color.from_hsv(v.carrying.hue, 0.35, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _squirrel(v: Visitors.Visitor, now: float) -> void:
	var c := Color(0.55, 0.32, 0.18)
	var f := v.face
	var hop := absf(sin(now * 14.0 + v.phase)) * 3.0 if absf(v.vel.x) > 1.0 else 0.0
	var digging := v.state == "dig"
	draw_set_transform(v.pos + Vector2(0, -hop), 0.0, Vector2(f, 1.0) * SIZE)
	# Tail curls up behind.
	var tail := PackedVector2Array()
	for k in 9:
		var t := k / 8.0
		tail.append(Vector2(-6.0 - sin(t * 2.6) * 7.0, -3.0 - t * 15.0))
	draw_polyline(tail, c.lightened(0.15), 5.0)
	draw_circle(Vector2(0, -5), 5.0, c)
	draw_circle(Vector2(6, -8 if not digging else -3), 3.4, c)
	draw_circle(Vector2(7.5, -9 if not digging else -4), 0.8, Color(0.05, 0.05, 0.05))
	draw_line(Vector2(5, -11 if not digging else -6), Vector2(4, -14 if not digging else -9), c, 1.6)
	if v.carrying != null:
		draw_circle(Vector2(9.5, -6 if not digging else -2), 2.0, Color.from_hsv(v.carrying.hue, 0.35, 0.9))
	if digging:
		for k in 3:
			var t := fposmod(now * 3.0 + k * 0.33, 1.0)
			draw_circle(Vector2(10 + t * 8.0, -t * 9.0 + t * t * 9.0), 1.2, Color(0.25, 0.18, 0.12, 1.0 - t))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _owl(v: Visitors.Visitor, now: float) -> void:
	var c := Color(0.42, 0.36, 0.3)
	var p := v.pos
	var sitting := v.state == "sit"
	draw_set_transform(p, 0.0, Vector2.ONE * SIZE)
	if sitting:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 2), Vector2(-7, -9), Vector2(-4, -15), Vector2(4, -15), Vector2(7, -9), Vector2(6, 2)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(-5, -15), Vector2(-4, -19), Vector2(-2, -15)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(5, -15), Vector2(4, -19), Vector2(2, -15)]), c)
		var blink := fposmod(now * 0.23 + v.phase, 1.0) < 0.03
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(2.4 * side, -11), 2.2, Color(0.95, 0.85, 0.55))
			if not blink:
				draw_circle(Vector2(2.4 * side, -11), 1.0, Color(0.05, 0.04, 0.03))
		draw_colored_polygon(PackedVector2Array([Vector2(-1, -9), Vector2(1, -9), Vector2(0, -7)]), Color(0.75, 0.6, 0.3))
		draw_line(Vector2(-4, -4), Vector2(4, -4), c.darkened(0.25), 0.8)
		draw_line(Vector2(-3, -1), Vector2(3, -1), c.darkened(0.25), 0.8)
	else:
		var flap := sin(now * 9.0 + v.phase) * 9.0
		draw_circle(Vector2(0, 0), 5.5, c)
		draw_colored_polygon(PackedVector2Array([Vector2(-3, -1), Vector2(-16, -2 - flap), Vector2(-10, 3)]), c.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([Vector2(3, -1), Vector2(16, -2 - flap), Vector2(10, 3)]), c.darkened(0.15))
		draw_circle(Vector2(-2, -2), 1.5, Color(0.95, 0.85, 0.55))
		draw_circle(Vector2(2, -2), 1.5, Color(0.95, 0.85, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow() -> void:
	var tex := Art.glow()
	var now := world.clock
	for v in world.visitors.list:
		if v.kind != Visitors.FIREFLY:
			continue
		var pulse := 0.5 + 0.5 * sin(now * 2.6 + v.phase * 3.0)
		pulse *= pulse
		var a := pulse * clampf(1.0 + v.t / 3.0, 0.0, 1.0) if v.t < 0.0 else pulse
		glow.draw_texture_rect(tex, Rect2(v.pos - Vector2(12, 12), Vector2(24, 24)), false, Color(0.85, 1.0, 0.45, 0.55 * a))
		glow.draw_circle(v.pos, 1.3, Color(1.0, 1.0, 0.7, 0.9 * a))
