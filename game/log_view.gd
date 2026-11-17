class_name LogView
extends Node2D
## Fallen wood: the same strokes as the plant it came from, greying as it rots.

var body: LogBody
var leaf_tex: Texture2D
var shown_rot := -1.0
var shown_age := -1.0


func _process(_delta: float) -> void:
	var stage := floorf(body.rot * 24.0)
	var wither := minf(floorf(body.age * 2.0), 24.0)
	if stage != shown_rot or wither != shown_age:
		shown_rot = stage
		shown_age = wither
		queue_redraw()


func _draw() -> void:
	var rot := clampf(body.rot, 0.0, 1.0)
	var hue := body.genome.hue if body.genome != null else 0.3
	var fresh := Color.from_hsv(fposmod(0.06 + (hue - 0.5) * 0.06, 1.0), 0.38, 0.30)
	var old := Color(0.2, 0.22, 0.17)
	var c := fresh.lerp(old, minf(1.0, rot * 1.4))
	c.a = 1.0 - maxf(0.0, rot - 0.6) * 2.2
	var shrink := 1.0 - rot * 0.45
	var count := body.segs.size() / LogBody.STRIDE
	for i in count:
		var o := i * LogBody.STRIDE
		var a := Vector2(body.segs[o], body.segs[o + 1])
		var b := Vector2(body.segs[o + 2], body.segs[o + 3])
		var r := body.segs[o + 4] * shrink
		draw_line(a, b, c, maxf(r * 2.0, 1.2))
		if r > 1.4:
			draw_circle(b, r, c)
			draw_circle(a, r, c)
	# Leaves wither over the first seconds on the ground, then drop away.
	var age := body.age
	if age < 12.0:
		var green := Color.from_hsv(hue, 0.58, 0.7)
		var brown := Color(0.5, 0.36, 0.2)
		var lc := green.lerp(brown, clampf(age / 6.0, 0.0, 1.0))
		lc.a = clampf((12.0 - age) / 4.0, 0.0, 1.0)
		for i in count:
			var o := i * LogBody.STRIDE
			var lw := body.segs[o + 5]
			if lw <= 0.0:
				continue
			var a := Vector2(body.segs[o], body.segs[o + 1])
			var b := Vector2(body.segs[o + 2], body.segs[o + 3])
			var dir := (b - a).angle()
			draw_set_transform(b, dir + (0.9 if i % 2 == 0 else -0.9), Vector2.ONE)
			draw_texture_rect(leaf_tex, Rect2(-lw * 0.08, -lw * 0.24, lw, lw * 0.48), false, lc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
