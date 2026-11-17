class_name PlantView
extends Node2D
## Draws one plant as simple strokes whose width is the wood's thickness.
## Leaves brighten with the light they earn, so shade is readable at a glance.

var p: Plant
var light_v := -1
var leaf_tex: Texture2D
var wood := Color()
var twig := Color()
var leaf_col := Color()
var wobble := 0.0


func setup(plant: Plant, tex: Texture2D) -> void:
	p = plant
	leaf_tex = tex
	var hue := p.genome.hue
	wood = Color.from_hsv(fposmod(0.06 + (hue - 0.5) * 0.06, 1.0), 0.38, 0.30)
	leaf_col = Color.from_hsv(hue, 0.58, 0.86)
	twig = wood.lerp(leaf_col, 0.45)
	wobble = fposmod(p.id * 0.61, 1.0)


func _process(_delta: float) -> void:
	if p.dirty or light_v != p.world.light_version:
		p.dirty = false
		light_v = p.world.light_version
		queue_redraw()


func _draw() -> void:
	var n := p.n
	var dead := not p.alive
	var full := p.leaf_w * p.leaf_op * 0.8
	var w_col := wood if not dead else Color(0.33, 0.31, 0.29)
	for i in n:
		var a := Vector2(p.ax[i], p.ay[i])
		var b := Vector2(p.bx[i], p.by[i])
		var r := p.rad[i]
		var c := w_col
		if r < 1.6 and not dead:
			c = twig.lerp(w_col, clampf((r - 0.6), 0.0, 1.0))
		var s := p.strain[i]
		if s > 0.5:
			# Wood under strain pales toward the colour of a fresh split.
			c = c.lerp(Color(1.0, 0.86, 0.62), clampf((s - 0.5) * 1.6, 0.0, 0.85))
		draw_line(a, b, c, maxf(r * 2.0, 1.3))
		if r > 1.4:
			draw_circle(b, r, c)
	if p.rad[0] > 1.4:
		draw_circle(Vector2(p.base_x, p.base_y), p.rad[0], w_col)
	var big := p.genome.h[Genome.LEAF]
	var count := 1 if big > 0.6 else (2 if big > 0.3 else 3)
	for i in n:
		var lw := p.leaf[i]
		if lw <= 0.0:
			continue
		var lit := clampf(p.lgain[i] / full, 0.0, 1.0)
		var col: Color
		if dead:
			col = Color(0.5, 0.36, 0.2, 0.9)
		else:
			col = leaf_col * (0.34 + 0.66 * lit)
			col.a = 1.0
		var at := Vector2(p.bx[i], p.by[i])
		var dir := p.ang[i] - PI * 0.5
		var size := lw * (1.0 if count == 1 else (0.78 if count == 2 else 0.62))
		for k in count:
			var spread := 0.0
			if count == 1:
				spread = 0.9 if (i % 2 == 0) else -0.9
			elif count == 2:
				spread = -0.8 + 1.6 * k
			else:
				spread = -1.1 + 1.1 * k
			draw_set_transform(at, dir + spread, Vector2.ONE)
			draw_texture_rect(leaf_tex, Rect2(-size * 0.08, -size * 0.24, size, size * 0.48), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
