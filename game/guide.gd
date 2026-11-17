class_name Guide
extends Control
## The field guide: one page per named shape, with its outline and a pressed
## leaf, then the firsts, the records and the stamps. Notes, not targets.

const PAPER := Color(0.93, 0.89, 0.78)
const INK := Color(0.22, 0.18, 0.13)
const FADED := Color(0.42, 0.37, 0.3)


class ShapeCard:
	extends Control
	var shape: Dictionary
	var names: Array

	func _init(s: Dictionary, all: Array, now: float) -> void:
		shape = s
		custom_minimum_size = Vector2(0, 190)
		var title := Label.new()
		title.text = s.name
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Guide.INK)
		title.position = Vector2(190, 14)
		add_child(title)
		var lines := PackedStringArray()
		lines.append("First named in minute %d." % (int(s.born / 60.0) + 1))
		if s.parent >= 0 and s.parent < all.size():
			lines.append("Grew out of the %s." % all[s.parent].name)
		lines.append("Tallest seen: %d cm." % int(s.tallest))
		lines.append(("%d standing now." % s.standing) if s.standing > 0 else "None standing now.")
		lines.append(Guide.habits(s.h))
		var body := Label.new()
		body.text = "\n".join(lines)
		body.add_theme_font_size_override("font_size", 15)
		body.add_theme_color_override("font_color", Guide.FADED)
		body.add_theme_constant_override("line_spacing", 2)
		body.position = Vector2(190, 50)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(440, 0)
		body.size = Vector2(440, 0)
		add_child(body)

	func _draw() -> void:
		draw_line(Vector2(12, size.y - 1), Vector2(size.x - 12, size.y - 1), Color(0, 0, 0, 0.12), 1.0)
		var hue: float = shape.hue
		var leaf_col := Color.from_hsv(hue, 0.5, 0.62)
		var wood := Color(0.3, 0.22, 0.16)
		var data: PackedFloat32Array = shape.portrait
		var count := data.size() / 6
		if count > 0:
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for i in count:
				var o := i * 6
				lo = lo.min(Vector2(data[o], data[o + 1])).min(Vector2(data[o + 2], data[o + 3]))
				hi = hi.max(Vector2(data[o], data[o + 1])).max(Vector2(data[o + 2], data[o + 3]))
			var extent := hi - lo
			var scale := minf(150.0 / maxf(extent.x, 30.0), 140.0 / maxf(extent.y, 30.0))
			var origin := Vector2(95.0 - (lo.x + hi.x) * 0.5 * scale, 154.0)
			draw_line(Vector2(30, 154), Vector2(160, 154), Color(0, 0, 0, 0.25), 1.0)
			for i in count:
				var o := i * 6
				var a := origin + Vector2(data[o], data[o + 1]) * scale
				var b := origin + Vector2(data[o + 2], data[o + 3]) * scale
				draw_line(a, b, wood, maxf(data[o + 4] * 2.0 * scale, 1.0), true)
			var tex := Art.leaf()
			for i in count:
				var o := i * 6
				var lw := data[o + 5] * scale
				if lw <= 0.0:
					continue
				var b := origin + Vector2(data[o + 2], data[o + 3]) * scale
				var dir := (Vector2(data[o + 2], data[o + 3]) - Vector2(data[o], data[o + 1])).angle()
				for side in 2:
					draw_set_transform(b, dir - 0.85 + 1.7 * side, Vector2.ONE)
					draw_texture_rect(tex, Rect2(-lw * 0.08, -lw * 0.24, lw, lw * 0.48), false, leaf_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# The pressed leaf.
		var big: float = lerpf(40.0, 76.0, shape.leaf)
		draw_set_transform(Vector2(size.x - 62.0, 44.0), -0.5, Vector2.ONE)
		draw_texture_rect(Art.leaf(), Rect2(-big * 0.5, -big * 0.24, big, big * 0.48), false, Color.from_hsv(hue, 0.42, 0.5, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var page: PanelContainer
var list: VBoxContainer
var scroll: ScrollContainer


## A sentence about a shape's habits, in words, never numbers.
static func habits(h: PackedFloat32Array) -> String:
	var bits := PackedStringArray()
	bits.append("Curls after the sun" if h[Genome.REACH] > 0.66 else ("Grows straight up" if h[Genome.REACH] < 0.33 else "Leans a little to the light"))
	bits.append("forks wide" if h[Genome.FORK] > 0.66 else ("rarely forks" if h[Genome.FORK] < 0.33 else "forks now and then"))
	bits.append("stout wood" if h[Genome.WOOD] > 0.66 else ("whippy wood" if h[Genome.WOOD] < 0.33 else "middling wood"))
	bits.append("deep roots" if h[Genome.ROOT] > 0.66 else ("shallow roots" if h[Genome.ROOT] < 0.33 else "fair roots"))
	bits.append("plump seeds" if h[Genome.SEED] > 0.66 else ("drifting seeds" if h[Genome.SEED] < 0.33 else "middling seeds"))
	bits.append("seeds late" if h[Genome.PATIENCE] > 0.66 else ("seeds early" if h[Genome.PATIENCE] < 0.33 else "seeds in its time"))
	bits.append("idles in shade" if h[Genome.THRIFT] > 0.66 else ("hungry for light" if h[Genome.THRIFT] < 0.33 else "gets by on dappled light"))
	return bits[0] + "; " + ", ".join(bits.slice(1)) + "."


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			visible = false)
	add_child(dim)
	page = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 18
	page.add_theme_stylebox_override("panel", style)
	page.anchor_left = 0.5
	page.anchor_right = 0.5
	page.anchor_top = 0.0
	page.anchor_bottom = 1.0
	page.offset_left = -390.0
	page.offset_right = 390.0
	page.offset_top = 30.0
	page.offset_bottom = -30.0
	add_child(page)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var close := Hud.IconButton.new("close", 44.0)
	close.active = true
	close.anchor_left = 0.5
	close.anchor_right = 0.5
	close.offset_left = 396.0
	close.offset_right = 440.0
	close.offset_top = 30.0
	close.offset_bottom = 74.0
	close.pressed.connect(func() -> void: visible = false)
	add_child(close)


func _heading(text: String, size := 30) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	list.add_child(l)


func _note(text: String, colour := FADED) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", colour)
	list.add_child(l)


func open(world: World, firsts: Array, stamps: Array, records: Dictionary) -> void:
	for c in list.get_children():
		c.queue_free()
	_heading("Field guide")
	var shapes := world.shapes.list
	if shapes.is_empty():
		_note("Nothing has grown up yet. A shape gets its page when one of its kind first sets seed.")
	else:
		_note("%d shapes named, %d standing." % [shapes.size(), world.shapes_standing])
	for i in range(shapes.size() - 1, -1, -1):
		list.add_child(ShapeCard.new(shapes[i], shapes, world.time))
	_heading("Firsts", 24)
	if firsts.is_empty():
		_note("None yet.")
	for f: String in firsts:
		_note("•  " + f)
	_heading("Notes", 24)
	_note("Tallest ever: %d cm.   Most brought down by one fall: %d.   Falls so far: %d." % [int(records.get("tallest", 0.0)), int(records.get("cascade", 0)), int(records.get("falls", 0))])
	_heading("Stamps", 24)
	if stamps.is_empty():
		_note("No wishes met yet.")
	for s: String in stamps:
		_note("✦  " + s, Color(0.55, 0.25, 0.18))
	visible = true
	scroll.scroll_vertical = 0
