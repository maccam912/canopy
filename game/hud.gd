class_name Hud
extends CanvasLayer
## The little interface there is: a speed button, the tools that have arrived,
## a pinned wish, passing notes, and the field guide.

signal tool_picked(name: String)
signal speed_toggled
signal guide_opened
signal wish_skipped
signal sound_toggled
signal home_picked(index: int)
signal varieties_requested
signal home_reset_requested


class IconButton:
	extends Control
	signal pressed
	var kind := ""
	var active := false
	var dots: Array[Color] = []
	var glow := 0.0

	func _init(p_kind: String, size := 58.0) -> void:
		kind = p_kind
		custom_minimum_size = Vector2(size, size)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _process(delta: float) -> void:
		if glow > 0.0:
			glow = maxf(0.0, glow - delta * 0.5)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var ink := Color(0.95, 0.92, 0.82, 0.95 if active else 0.62)
		if glow > 0.0:
			draw_circle(c, r + 6.0 * glow, Color(1.0, 0.9, 0.6, 0.35 * glow))
		draw_circle(c, r, Color(0.09, 0.12, 0.13, 0.82))
		draw_arc(c, r, 0.0, TAU, 40, Color(1.0, 0.9, 0.62, 0.9) if active else Color(1, 1, 1, 0.16), 2.0 if active else 1.2, true)
		var u := r / 26.0
		match kind:
			"slow":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -10) * u, c + Vector2(10, 0) * u, c + Vector2(-7, 10) * u]), ink)
			"fast":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -9) * u, c + Vector2(0, 0) * u, c + Vector2(-13, 9) * u]), ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(1, -9) * u, c + Vector2(14, 0) * u, c + Vector2(1, 9) * u]), ink)
			"guide":
				draw_rect(Rect2(c + Vector2(-12, -10) * u, Vector2(11, 20) * u), ink, false, 1.8)
				draw_rect(Rect2(c + Vector2(1, -10) * u, Vector2(11, 20) * u), ink, false, 1.8)
				draw_line(c + Vector2(-8, -4) * u, c + Vector2(-4, -4) * u, ink, 1.4)
				draw_line(c + Vector2(-8, 1) * u, c + Vector2(-4, 1) * u, ink, 1.4)
				draw_line(c + Vector2(4, -4) * u, c + Vector2(9, -4) * u, ink, 1.4)
			"snip":
				draw_line(c + Vector2(-11, -11) * u, c + Vector2(8, 8) * u, ink, 2.2, true)
				draw_line(c + Vector2(11, -11) * u, c + Vector2(-8, 8) * u, ink, 2.2, true)
				draw_arc(c + Vector2(10, 11) * u, 4.0 * u, 0.0, TAU, 16, ink, 1.8, true)
				draw_arc(c + Vector2(-10, 11) * u, 4.0 * u, 0.0, TAU, 16, ink, 1.8, true)
			"jar":
				draw_rect(Rect2(c + Vector2(-9, -8) * u, Vector2(18, 20) * u), ink, false, 1.8)
				draw_rect(Rect2(c + Vector2(-6, -13) * u, Vector2(12, 4) * u), ink, false, 1.8)
				for k in dots.size():
					var at := c + Vector2(-5 + (k % 3) * 5, 8 - (k / 3) * 6) * u
					draw_circle(at, 2.4 * u, dots[k])
			"prop":
				draw_line(c + Vector2(4, -14) * u, c + Vector2(-2, 13) * u, ink, 3.0, true)
				draw_line(c + Vector2(-12, 13) * u, c + Vector2(1, -2) * u, Color(1.0, 0.85, 0.55, ink.a), 2.2, true)
				draw_line(c + Vector2(-15, 13) * u, c + Vector2(14, 13) * u, ink, 1.4)
			"water":
				var pts := PackedVector2Array()
				for k in 21:
					var a := PI * k / 20.0
					pts.append(c + Vector2(cos(a) * 9.0, 4.0 + sin(a) * 9.0) * u)
				pts.append(c + Vector2(0, -14) * u)
				draw_colored_polygon(pts, Color(0.6, 0.82, 1.0, ink.a))
			"tie":
				draw_circle(c + Vector2(-11, -5) * u, 3.2 * u, ink)
				draw_circle(c + Vector2(11, -5) * u, 3.2 * u, ink)
				var arc := PackedVector2Array()
				for k in 13:
					var t := k / 12.0
					arc.append(c + Vector2(lerpf(-11, 11, t), -5 + sin(t * PI) * 12.0) * u)
				draw_polyline(arc, ink, 1.6, true)
			"wind":
				for k in 3:
					var line := PackedVector2Array()
					for j in 13:
						var t := j / 12.0
						line.append(c + Vector2(lerpf(-13, 13 - k * 4, t), -8 + k * 8 + sin(t * TAU) * 2.5) * u)
					draw_polyline(line, ink, 1.8, true)
			"sound":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -4) * u, c + Vector2(-5, -4) * u, c + Vector2(2, -10) * u, c + Vector2(2, 10) * u, c + Vector2(-5, 4) * u, c + Vector2(-11, 4) * u]), ink)
				if active:
					draw_arc(c + Vector2(2, 0) * u, 8.0 * u, -0.8, 0.8, 10, ink, 1.6, true)
					draw_arc(c + Vector2(2, 0) * u, 13.0 * u, -0.8, 0.8, 12, ink, 1.6, true)
			"close":
				draw_line(c + Vector2(-8, -8) * u, c + Vector2(8, 8) * u, ink, 2.2, true)
				draw_line(c + Vector2(8, -8) * u, c + Vector2(-8, 8) * u, ink, 2.2, true)


var root: Control
var speed_btn: IconButton
var guide_btn: IconButton
var sound_btn: IconButton
var tray: HBoxContainer
var tool_btns := {}
var toast: Label
var toast_sub: Label
var toast_queue: Array = []
var toast_time := 0.0
var wish: Button
var hint: Label
var hint_time := 0.0
var guide: Guide
var shelf: HBoxContainer
var planting_menu: MenuButton
var reset_dialog: ConfirmationDialog


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var left := VBoxContainer.new()
	left.position = Vector2(14, 14)
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	speed_btn = IconButton.new("slow")
	speed_btn.pressed.connect(func() -> void: speed_toggled.emit())
	left.add_child(speed_btn)
	guide_btn = IconButton.new("guide")
	guide_btn.pressed.connect(func() -> void: guide_opened.emit())
	guide_btn.visible = false
	left.add_child(guide_btn)
	sound_btn = IconButton.new("sound", 44.0)
	sound_btn.active = true
	sound_btn.pressed.connect(func() -> void: sound_toggled.emit())
	left.add_child(sound_btn)
	for button in [speed_btn, guide_btn, sound_btn]:
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	tray = HBoxContainer.new()
	tray.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tray.offset_bottom = -12.0
	tray.add_theme_constant_override("separation", 12)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tray)
	for name: String in ["snip", "jar", "prop", "water", "tie", "wind"]:
		var b := IconButton.new(name)
		b.visible = name == "snip"
		b.active = name == "snip"
		b.pressed.connect(func() -> void: tool_picked.emit(name))
		tray.add_child(b)
		tool_btns[name] = b

	toast = _label(26, Color(1.0, 0.95, 0.82))
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.offset_top = 92.0
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	root.add_child(toast)
	toast_sub = _label(16, Color(0.86, 0.88, 0.8))
	toast_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_sub.offset_top = 128.0
	toast_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_sub.modulate.a = 0.0
	root.add_child(toast_sub)

	hint = _label(15, Color(0.8, 0.85, 0.8, 0.8))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -84.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	root.add_child(hint)

	wish = Button.new()
	wish.flat = true
	wish.focus_mode = Control.FOCUS_NONE
	wish.add_theme_font_size_override("font_size", 15)
	wish.add_theme_color_override("font_color", Color(0.9, 0.88, 0.76, 0.75))
	wish.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8, 1.0))
	wish.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wish.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wish.offset_top = 16.0
	wish.offset_right = -18.0
	wish.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wish.visible = false
	wish.pressed.connect(func() -> void: wish_skipped.emit())
	root.add_child(wish)

	shelf = HBoxContainer.new()
	shelf.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	shelf.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shelf.offset_top = 10.0
	shelf.add_theme_constant_override("separation", 6)
	shelf.visible = false
	root.add_child(shelf)

	planting_menu = MenuButton.new()
	planting_menu.text = "Planting ▾"
	planting_menu.flat = false
	planting_menu.custom_minimum_size = Vector2(112, 48)
	left.add_child(planting_menu)
	var menu := planting_menu.get_popup()
	menu.add_theme_constant_override("v_separation", 18)
	menu.add_item("Add varieties", 0)
	menu.add_item("Reset current home…", 1)
	menu.id_pressed.connect(_choose_planting)

	reset_dialog = ConfirmationDialog.new()
	reset_dialog.dialog_autowrap = true
	reset_dialog.ok_button_text = "Reset home"
	for button in [reset_dialog.get_ok_button(), reset_dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(112, 44)
	root.add_child(reset_dialog)

	guide = Guide.new()
	guide.visible = false
	root.add_child(guide)


func _choose_planting(id: int) -> void:
	match id:
		0:
			varieties_requested.emit()
		1:
			home_reset_requested.emit()


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## True if a screen point is on a button or the open guide, so the forest ignores it.
func blocks(at: Vector2) -> bool:
	if guide.visible:
		return true
	if shelf.visible and shelf.get_global_rect().grow(4.0).has_point(at):
		return true
	for b: Control in [speed_btn, guide_btn, sound_btn, wish, planting_menu] + tool_btns.values():
		if b.is_visible_in_tree() and b.get_global_rect().grow(4.0).has_point(at):
			return true
	return false


## The shelf of homes the forest has outgrown.
func set_homes(names: Array[String], current: int) -> void:
	for c in shelf.get_children():
		c.queue_free()
	shelf.visible = names.size() > 1
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.flat = i != current
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7) if i == current else Color(0.85, 0.85, 0.8, 0.7))
		var idx := i
		b.pressed.connect(func() -> void: home_picked.emit(idx))
		shelf.add_child(b)


func say(title: String, sub := "", seconds := 4.5) -> void:
	if toast_queue.size() < 4:
		toast_queue.append([title, sub, seconds])


func nudge(text: String, seconds := 5.0) -> void:
	hint.text = text
	hint_time = seconds


func set_tool(name: String) -> void:
	for k: String in tool_btns:
		tool_btns[k].active = k == name
		tool_btns[k].queue_redraw()


func unlock(name: String, flash := true) -> void:
	var b: IconButton = tool_btns[name]
	b.visible = true
	if flash:
		b.glow = 2.0


func set_fast(on: bool, forced_slow: bool) -> void:
	var want := "fast" if on and not forced_slow else "slow"
	if speed_btn.kind != want or speed_btn.active != on:
		speed_btn.kind = want
		speed_btn.active = on
		speed_btn.queue_redraw()


func set_pocket(colours: Array[Color]) -> void:
	var b: IconButton = tool_btns["jar"]
	b.dots = colours
	b.queue_redraw()


func set_wish(text: String) -> void:
	wish.visible = text != ""
	wish.text = "✧ " + text if text != "" else ""


func _process(delta: float) -> void:
	if toast_time > 0.0:
		toast_time -= delta
		var a := clampf(minf(toast_time * 1.5, 1.0), 0.0, 1.0)
		toast.modulate.a = lerpf(toast.modulate.a, a, minf(1.0, delta * 6.0))
		toast_sub.modulate.a = toast.modulate.a
	elif not toast_queue.is_empty():
		var t: Array = toast_queue.pop_front()
		toast.text = t[0]
		toast_sub.text = t[1]
		toast_time = t[2]
	else:
		toast.modulate.a = maxf(0.0, toast.modulate.a - delta * 2.0)
		toast_sub.modulate.a = toast.modulate.a
	if hint_time > 0.0:
		hint_time -= delta
		hint.modulate.a = lerpf(hint.modulate.a, 1.0 if hint_time > 0.6 else 0.0, minf(1.0, delta * 5.0))
	else:
		hint.modulate.a = maxf(0.0, hint.modulate.a - delta * 2.0)
