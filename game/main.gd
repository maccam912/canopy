extends Node2D
## Wires the simulation to the screen: views, camera, the player's hands, and
## the layers of play that sit on top (tools that arrive, wishes, the guide).

const FAST := 8.0
const WISHES := [
	["fall3", "A fall that takes down three."],
	["shapes4", "Four shapes standing at once."],
	["tall", "A plant taller than half the jar."],
	["survivor", "A plant that loses its top and lives."],
	["fall5", "A fall that takes down five."],
	["snags", "Three dead trunks standing at once."],
	["shapes5", "Five shapes standing at once."],
	["lid", "A plant that touches the lid."],
	["thumb", "A forest where nothing grows taller than your thumb."],
	["fall10", "A fall that takes down ten."],
]
const TOOL_NOTES := {
	"jar": ["Seed jar", "A plant has set its first seed. Tap a seed to pocket it; tap the soil to start it."],
	"prop": ["Prop", "The first fall. Tap a trunk to wedge a stick under it."],
	"water": ["Water", "A log has rotted away. Hold to pour rain: richer soil, softer ground."],
	"tie": ["Tie", "Three came down together. Drag from one stem to another."],
	"wind": ["Wind", "Five came down together. Drag sideways to blow across the jar."],
}

var world: World
var back: JarBack
var front: JarFront
var fx: Fx
var visitor_view: VisitorView
var hud: Hud
var sound: Sound
var plant_layer: Node2D
var cam: Camera2D
var views := {}

var base_zoom := 1.0
var zoom := 1.0
var focus := Vector2.ZERO
var touches := {}
var gesture := ""          # "", "sun", "cut", "hold", "pinch", "pour", "blow", "tie"
var down_at := Vector2.ZERO
var down_world := Vector2.ZERO
var down_time := 0.0
var last_world := Vector2.ZERO
var moved := false
var sun_track := 0.0
var fast_latch := false
var holding_fast := false
var pinch_dist := 0.0
var pinch_mid := Vector2.ZERO
var shake := 0.0

var tool := "snip"
var unlocked := {"snip": true}
var pocket: Array = []       # seeds in the jar: [genome, species, generation]
var tie_from := []
var firsts: Array = []
var stamps: Array = []
var wish_done := {}
var wish_at := 0
var thumb_count := 0
var records := {"tallest": 0.0, "cascade": 0, "falls": 0}
var told := {}

var shot_path := ""
var shot_frames := 0
var smoke := false
var shot_done := false
var film_prefix := ""
var film_start := 0
var film_count := 0
var film_every := 10
var film_taken := 0
var frame := 0
var scripted := false
var fresh := false
var use_save := false
var save_at_end := false
var pretend_away := 0.0
var save_acc := 0.0
var catch_until := -1.0
var catch_from := 0.0
var journal := {"falls": 0, "biggest": 0, "shapes": [], "lid": false}

const SAVE_PATH := "user://canopy.save"
const AWAY_CAP := 20.0 * 60.0
var guide_frame := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(Time.get_unix_time_from_system())
	var start_speed := 1.0
	var start_phi := 0.0
	var open_guide := false
	var k := 0
	while k < args.size():
		match args[k]:
			"--smoke":
				smoke = true
				world_seed = 7
				start_speed = FAST
			"--shot":
				shot_path = args[k + 1]
				shot_frames = int(float(args[k + 2]) * 60.0)
				k += 2
			"--film":
				# --film prefix start_seconds count every_frames: snip the tallest plant, save frames.
				film_prefix = args[k + 1]
				film_start = int(float(args[k + 2]) * 60.0)
				film_count = int(args[k + 3])
				film_every = int(args[k + 4])
				k += 4
			"--seed":
				world_seed = int(args[k + 1])
				k += 1
			"--speed":
				start_speed = float(args[k + 1])
				k += 1
			"--phi":
				start_phi = float(args[k + 1])
				k += 1
			"--guide":
				open_guide = true
			"--fresh":
				fresh = true
			"--use-save":
				use_save = true
			"--save-at-end":
				save_at_end = true
			"--away":
				pretend_away = float(args[k + 1])
				k += 1
			"--all-tools":
				for name: String in TOOL_NOTES:
					unlocked[name] = true
			"--warp":
				# Run the whole game faster while keeping every physics step 1/60 s.
				var warp := float(args[k + 1])
				Engine.time_scale = warp
				Engine.physics_ticks_per_second = int(60.0 * warp)
				Engine.max_physics_steps_per_frame = int(2.0 * warp)
				k += 1
		k += 1
	scripted = smoke or shot_path != "" or film_prefix != ""

	world = World.new()
	world.z_index = 1
	back = JarBack.new()
	back.z_index = -5
	plant_layer = Node2D.new()
	fx = Fx.new()
	fx.z_index = 3
	visitor_view = VisitorView.new()
	visitor_view.z_index = 4
	front = JarFront.new()
	front.z_index = 6
	hud = Hud.new()
	sound = Sound.new()
	add_child(back)
	add_child(plant_layer)
	add_child(world)
	add_child(fx)
	add_child(visitor_view)
	add_child(front)
	add_child(hud)
	add_child(sound)
	world.plant_added.connect(_on_plant_added)
	world.plant_removed.connect(_on_plant_removed)
	world.log_added.connect(_on_log_added)
	world.happened.connect(_on_event)
	var saved := {} if ((scripted and not use_save) or fresh) else _read_save()
	world.setup(world_seed, 1500.0, 780.0, saved.get("world", {}))
	back.setup(world)
	front.setup(world)
	fx.setup(world)
	visitor_view.setup(world)
	sound.setup(world)
	sound.muted = smoke
	if saved.is_empty():
		world.sun_phi = start_phi
		world.sow_starters()
	else:
		_restore(saved)
	world.speed = start_speed
	fast_latch = start_speed > 1.0

	hud.tool_picked.connect(_pick_tool)
	hud.speed_toggled.connect(func() -> void: fast_latch = not fast_latch)
	hud.guide_opened.connect(_open_guide)
	hud.wish_skipped.connect(_next_wish)
	hud.sound_toggled.connect(_toggle_sound)
	for name: String in unlocked:
		hud.unlock(name, false)
	hud.set_wish(WISHES[wish_at][1] if not wish_done.has(WISHES[wish_at][0]) else "")
	if not scripted and saved.is_empty():
		hud.nudge("Drag the sun.  Swipe across a stem to snip it.  Hold still to let time run.", 9.0)
	hud.guide_btn.visible = not world.shapes.list.is_empty()
	_show_pocket()

	cam = Camera2D.new()
	add_child(cam)
	focus = Vector2(world.jar_w * 0.5, -world.jar_h * 0.5 + 6.0)
	get_viewport().size_changed.connect(_fit)
	_fit()
	guide_frame = shot_frames - 20 if open_guide else -1


func _fit() -> void:
	var size := get_viewport_rect().size
	base_zoom = minf(size.x / (world.jar_w + 230.0), size.y / (world.jar_h + 260.0))
	_apply_camera()


func _apply_camera() -> void:
	zoom = clampf(zoom, 1.0, 5.0)
	var size := get_viewport_rect().size
	var half := size / (base_zoom * zoom) * 0.5
	var centre := Vector2(world.jar_w * 0.5, -world.jar_h * 0.5 + 6.0)
	var slack := Vector2(maxf(0.0, (world.jar_w + 230.0) * 0.5 - half.x), maxf(0.0, (world.jar_h + 260.0) * 0.5 - half.y))
	focus.x = clampf(focus.x, centre.x - slack.x, centre.x + slack.x)
	focus.y = clampf(focus.y, centre.y - slack.y, centre.y + slack.y)
	cam.position = focus
	cam.zoom = Vector2.ONE * base_zoom * zoom


func _on_plant_added(p: Plant) -> void:
	var v := PlantView.new()
	v.setup(p, Art.leaf())
	plant_layer.add_child(v)
	views[p] = v


func _on_plant_removed(p: Plant) -> void:
	var v: PlantView = views.get(p)
	if v != null:
		views.erase(p)
		v.queue_free()


func _on_log_added(l: LogBody) -> void:
	var v := LogView.new()
	v.body = l
	v.leaf_tex = Art.leaf()
	l.add_child(v)


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != 1 or not data.has("world"):
		return {}
	return data


func save_game() -> void:
	if (scripted and not save_at_end) or world == null:
		return
	var items := []
	for item: Array in pocket:
		items.append([item[0].h, item[0].hue, item[1], item[2]])
	var data := {
		"version": 1, "at": Time.get_unix_time_from_system(), "world": world.save_state(),
		"unlocked": unlocked, "firsts": firsts, "stamps": stamps, "wish_done": wish_done, "wish_at": wish_at,
		"records": records, "told": told, "pocket": items, "muted": sound.muted,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(data)


func _restore(d: Dictionary) -> void:
	unlocked = d.unlocked
	firsts = d.firsts
	stamps = d.stamps
	wish_done = d.wish_done
	wish_at = d.wish_at
	records = d.records
	told = d.told
	for item: Array in d.pocket:
		pocket.append([Genome.make(Array(item[0]), item[1]), item[2], item[3]])
	if d.muted:
		_toggle_sound()
	# The forest kept growing while the game was closed, up to a cap.
	var away := clampf(Time.get_unix_time_from_system() - float(d.at) + pretend_away, 0.0, AWAY_CAP)
	if away > 30.0:
		catch_from = world.time
		catch_until = world.time + away
		Engine.time_scale = 6.0
		Engine.physics_ticks_per_second = 360
		Engine.max_physics_steps_per_frame = 12
		hud.say("Catching up on %d minutes away…" % maxi(1, int(away / 60.0)), "", 600.0)


func _catch_up() -> void:
	world.speed = 24.0
	if world.time < catch_until:
		return
	catch_until = -1.0
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 4
	hud.toast_time = 0.0
	var lines: Array[String] = []
	var minutes := int((world.time - catch_from) / 60.0)
	lines.append("The forest grew for %d minute%s." % [minutes, "" if minutes == 1 else "s"])
	if journal.falls > 0:
		lines.append("%d fall%s%s." % [journal.falls, "" if journal.falls == 1 else "s", (", the biggest taking down %d" % journal.biggest) if journal.biggest >= 2 else ""])
	else:
		lines.append("Nothing fell.")
	for name: String in journal.shapes:
		lines.append("A new shape appeared: %s." % name)
	if journal.lid:
		lines.append("Something touched the lid.")
	hud.show_journal(lines)


func _process(delta: float) -> void:
	frame += 1
	save_acc += delta
	if save_acc > 30.0 and catch_until < 0.0:
		save_acc = 0.0
		save_game()
	if gesture == "hold" and not holding_fast and Time.get_ticks_msec() * 0.001 - down_time > 0.32:
		holding_fast = true
	if gesture == "pour":
		_pour(delta)
	var want_fast := fast_latch or holding_fast or Input.is_key_pressed(KEY_SPACE)
	if catch_until >= 0.0:
		_catch_up()
	elif not scripted:
		world.speed = FAST if want_fast else 1.0
	hud.set_fast(want_fast, world.falling)
	if gesture != "blow" and world.wind != 0.0:
		world.wind = move_toward(world.wind, 0.0, delta * 220.0)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 3.0)
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * shake * 7.0
	else:
		cam.offset = Vector2.ZERO
	if frame == guide_frame:
		_open_guide()
	if film_prefix != "":
		_film()
	if smoke and frame >= 600:
		# The shipped build must be running Rapier, not Godot's fallback physics.
		if PhysicsServer2D.get_class() == "RapierPhysicsServer2D":
			print("CANOPY_SMOKE_PASS plants=%d t=%.0f physics=%s" % [world.plants.size(), world.time, PhysicsServer2D.get_class()])
		else:
			print("ERROR: physics server is %s, not Rapier" % PhysicsServer2D.get_class())
		get_tree().quit()
	if shot_path != "" and frame >= shot_frames and not shot_done:
		shot_done = true
		if save_at_end:
			save_game()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("SHOT ", shot_path, " t=", world.time, " plants=", world.plants.size(), " logs=", world.logs.size(), " falls=", world.count_falls, " fps=", Engine.get_frames_per_second(), " visitors=", world.visitors.counts)
		get_tree().quit()


func _film() -> void:
	if frame == film_start:
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		world.speed = 1.0
		var best: Plant = null
		for p in world.plants:
			if p.alive and (best == null or p.height > best.height):
				best = p
		if best != null:
			var toward := 1.0 if best.base_x < world.jar_w * 0.5 else -1.0
			world.snip(best, 0, 0.6, toward)
	if frame >= film_start and (frame - film_start) % film_every == 0 and film_taken < film_count:
		film_taken += 1
		var n := film_taken
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s%02d.png" % [film_prefix, n])
		if n == film_count:
			print("FILM done t=", world.time, " falls=", world.count_falls, " best=", world.best_cascade)
			get_tree().quit()


# ------------------------------------------------------- what the forest does ----

func _minute() -> String:
	return "Minute %d" % (int(world.time / 60.0) + 1)


func _first(key: String, text: String) -> bool:
	if told.has(key):
		return false
	told[key] = true
	firsts.append("%s: %s" % [_minute(), text])
	return true


func _unlock(name: String) -> void:
	if unlocked.has(name):
		return
	unlocked[name] = true
	hud.unlock(name)
	hud.say(TOOL_NOTES[name][0], TOOL_NOTES[name][1], 7.0)
	sound.chime(1.33)


func _shape_name(id: int) -> String:
	return world.shapes.list[id].name if id >= 0 else "seedling"


func _on_event(kind: String, d: Dictionary) -> void:
	if catch_until >= 0.0:
		match kind:
			"fall":
				journal.falls += 1
				journal.biggest = maxi(journal.biggest, d.count)
			"new_shape":
				journal.shapes.append(d.shape.name)
			"lid":
				journal.lid = true
	match kind:
		"seeded":
			if _first("seed", "the first seed ripened, on a %s." % _shape_name(d.plant.species)):
				_unlock("jar")
		"new_shape":
			hud.guide_btn.visible = true
			if world.shapes.list.size() == 1:
				hud.guide_btn.glow = 2.0
			hud.say("New shape: " + d.shape.name, Guide.habits(d.shape.h), 5.0)
		"fall":
			records.falls = world.count_falls
			shake = maxf(shake, clampf(d.volume / 9000.0, 0.15, 0.9))
			if _first("fall", "the first fall, a %s %d cm tall." % [_shape_name(d.species), int(d.height)]):
				_unlock("prop")
			var count: int = d.count
			if count > records.cascade:
				records.cascade = count
			if count >= 3 and _first("fall3", "the first fall of three."):
				_unlock("tie")
			if count >= 5 and _first("fall5", "the first fall of five."):
				_unlock("wind")
			if count >= 10:
				_first("fall10", "the first fall of ten.")
			if count >= 3:
				_grant("fall3")
			if count >= 5:
				_grant("fall5")
			if count >= 10:
				_grant("fall10")
			if d.alive and not d.whole and not d.snip:
				_first("survivor", "a %s lost its top and lived." % _shape_name(d.species))
				_grant("survivor")
		"break":
			if d.alive and not d.whole and not d.snip and d.volume > 150.0:
				_grant("survivor")
		"cascade_end":
			if d.count >= 3:
				hud.say("%d came down together." % d.count, "", 3.5)
		"rotted":
			if d.volume > 300.0 and _first("rot", "the first log rotted into the soil."):
				_unlock("water")
		"lid":
			if _first("lid", "a %s touched the lid." % _shape_name(d.plant.species)):
				hud.say("It touched the lid.", "", 4.0)
			_grant("lid")
		"impact":
			shake = maxf(shake, clampf(d.volume / 7000.0, 0.0, 1.0) * clampf(d.speed / 200.0, 0.2, 1.0))
		"visitor":
			var lines := {
				"fireflies": ["fireflies", "Fireflies have found the new gap."],
				"beetles": ["beetles", "Beetles have come for the rotting wood."],
				"bird": ["bird", "A bird has come to sit in the tallest crown."],
				"squirrel": ["squirrel", "A squirrel has come for the plump seeds."],
				"owl": ["owl", "An owl has settled in an old tree."],
			}
			var line: Array = lines[d.kind]
			if _first("visit_" + line[0], line[1].to_lower().trim_suffix(".")):
				hud.say(line[1], "", 4.0)
			if d.kind == "owl":
				sound.play("hoot", 1.0, -14.0)
			elif d.kind == "bird":
				sound.play("chirp", randf_range(0.9, 1.2), -18.0)
		"owl_left":
			sound.play("hoot", 0.85, -10.0)
			hud.say("The owl has left its tree.", "", 4.0)
			_first("owl_left", "an owl left its tree.")
		"bird_startled":
			sound.play("chirp", 1.4, -14.0)
		"bird_drop", "buried":
			sound.play("pop", 0.7, -24.0)
		"brace_broke":
			if not d.grip:
				sound.play("snap", 1.8, -12.0)
		"grip":
			if d.plant.grips >= 2:
				_first("vine", "the first vine: a plant riding on a %s." % _shape_name(d.host.species))
		"census":
			records.tallest = world.tallest_ever
			if world.shapes_standing >= 4:
				_grant("shapes4")
			if world.shapes_standing >= 5:
				_grant("shapes5")
			if world.tallest_ever > world.jar_h * 0.5:
				_grant("tall")
			var living := 0
			var tallest := 0.0
			var snags := 0
			for p in world.plants:
				if p.removed:
					continue
				if p.alive:
					living += 1
					tallest = maxf(tallest, p.height)
				elif p.volume > T.FALL_VOL:
					snags += 1
			if snags >= 3:
				_grant("snags")
			thumb_count = thumb_count + 1 if (living >= 12 and tallest < 110.0) else 0
			if thumb_count >= 12:
				_grant("thumb")


## A wish can only be met by the forest; meeting it earns a stamp and nothing else.
func _grant(id: String) -> void:
	if wish_done.has(id):
		return
	if WISHES[wish_at][0] != id:
		return
	wish_done[id] = true
	stamps.append("%s  (%s)" % [WISHES[wish_at][1], _minute().to_lower()])
	hud.say("A wish, met.", WISHES[wish_at][1], 5.0)
	sound.chime(0.75)
	_next_wish()


func _next_wish() -> void:
	for step in WISHES.size():
		wish_at = (wish_at + 1) % WISHES.size()
		if not wish_done.has(WISHES[wish_at][0]):
			hud.set_wish(WISHES[wish_at][1])
			return
	hud.set_wish("")


func _open_guide() -> void:
	hud.guide.open(world, firsts, stamps, records)


func _toggle_sound() -> void:
	sound.muted = not sound.muted
	AudioServer.set_bus_mute(0, sound.muted)
	hud.sound_btn.active = not sound.muted
	hud.sound_btn.queue_redraw()


func _pick_tool(name: String) -> void:
	tool = name
	hud.set_tool(name)
	match name:
		"snip":
			hud.nudge("Swipe across a stem to cut it.", 3.0)
		"jar":
			hud.nudge("Tap a seed, or a plant carrying seeds, to pocket one.  Tap the soil to start it.", 5.0)
		"prop":
			hud.nudge("Tap a trunk to wedge a stick under it.", 4.0)
		"water":
			hud.nudge("Hold to pour.", 3.0)
		"tie":
			hud.nudge("Drag from one stem to another.", 4.0)
		"wind":
			hud.nudge("Drag left or right and hold.", 4.0)


# ------------------------------------------------------------------ input ----

func to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if hud.blocks(event.position):
				return
			touches[event.index] = event.position
			if touches.size() == 1:
				_down(event.position)
			elif touches.size() == 2:
				_cancel()
				gesture = "pinch"
				var pts: Array = touches.values()
				pinch_dist = pts[0].distance_to(pts[1])
				pinch_mid = (pts[0] + pts[1]) * 0.5
		else:
			if not touches.has(event.index):
				return
			touches.erase(event.index)
			if gesture == "pinch":
				if touches.size() < 2:
					gesture = ""
			elif touches.is_empty():
				_up(event.position)
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if gesture == "pinch" and touches.size() >= 2:
			var pts: Array = touches.values()
			var dist: float = pts[0].distance_to(pts[1])
			var mid: Vector2 = (pts[0] + pts[1]) * 0.5
			var before := to_world(mid)
			zoom *= dist / maxf(pinch_dist, 1.0)
			focus -= (mid - pinch_mid) / (base_zoom * zoom)
			_apply_camera()
			focus += before - to_world(mid)
			_apply_camera()
			pinch_dist = dist
			pinch_mid = mid
		elif touches.size() == 1:
			_move(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := to_world(event.position)
			zoom *= 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_apply_camera()
			focus += before - to_world(event.position)
			_apply_camera()
	elif event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
		focus -= event.relative / (base_zoom * zoom)
		_apply_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				fast_latch = not fast_latch
			KEY_G:
				if hud.guide.visible:
					hud.guide.visible = false
				else:
					_open_guide()
			KEY_ESCAPE:
				if hud.guide.visible:
					hud.guide.visible = false
				elif OS.get_name() != "Android":
					get_tree().quit()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var names := ["snip", "jar", "prop", "water", "tie", "wind"]
				var pick: String = names[event.keycode - KEY_1]
				if unlocked.has(pick):
					_pick_tool(pick)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null and hud.guide.visible:
		hud.guide.visible = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if catch_until < 0.0:
			save_game()


func _down(screen: Vector2) -> void:
	var at := to_world(screen)
	down_at = screen
	down_world = at
	down_time = Time.get_ticks_msec() * 0.001
	last_world = at
	moved = false
	holding_fast = false
	var outside := at.y < world.lid_y - 24.0 or at.x < -24.0 or at.x > world.jar_w + 24.0
	if outside or at.distance_to(front.sun_pos(world.sun_phi)) < 90.0 / minf(zoom, 2.0) + 30.0:
		gesture = "sun"
		world.sun_vel = 0.0
		sun_track = 0.0
		return
	match tool:
		"water":
			gesture = "pour"
		"wind":
			gesture = "blow"
		"tie":
			tie_from = world.pick_stem(at, 34.0 / minf(zoom, 2.0) + 8.0)
			gesture = "tie" if not tie_from.is_empty() else "hold"
		_:
			gesture = "hold"


func _move(screen: Vector2) -> void:
	var at := to_world(screen)
	if screen.distance_to(down_at) > 10.0:
		moved = true
	match gesture:
		"sun":
			var phi := front.phi_at(at)
			var dt := maxf(get_process_delta_time(), 0.008)
			sun_track = lerpf(sun_track, (phi - world.sun_phi) / dt, 0.4)
			world.sun_phi = phi
		"hold":
			if moved and not holding_fast and tool == "snip":
				gesture = "cut"
		"blow":
			world.wind = clampf((at.x - down_world.x) * 1.1, -220.0, 220.0)
		"tie":
			fx.preview = PackedVector2Array([tie_from[2], at])
	if gesture == "cut":
		_cut(last_world, at)
		fx.swipe(last_world, at)
	last_world = at


func _up(screen: Vector2) -> void:
	var at := to_world(screen)
	var quick := Time.get_ticks_msec() * 0.001 - down_time < 0.32 and not moved
	match gesture:
		"sun":
			# A flick sets the sun swinging; a slow release parks it.
			world.sun_vel = clampf(sun_track * 0.25, -0.6, 0.6) if absf(sun_track) > 0.5 else 0.0
		"hold":
			if quick and tool == "jar":
				_jar_tap(at)
			elif quick and tool == "prop":
				_prop_tap(at)
		"tie":
			var to := world.pick_stem(at, 34.0 / minf(zoom, 2.0) + 8.0)
			if not to.is_empty() and to[0] != tie_from[0]:
				world.add_tie(tie_from[0], tie_from[2], to[0], to[2])
				sound.play("pop", 0.7, -14.0)
				_trim_braces()
	_cancel()


func _cancel() -> void:
	gesture = ""
	holding_fast = false
	fx.preview = PackedVector2Array()


## Snip: any stem the swipe crosses is cut where it crosses.
func _cut(from: Vector2, to: Vector2) -> void:
	if from.distance_squared_to(to) < 0.01:
		return
	var lo := minf(from.x, to.x)
	var hi := maxf(from.x, to.x)
	var list: Array[Plant] = world.plants.duplicate()
	for p: Plant in list:
		if p.removed:
			continue
		var reach := p.height + 60.0
		if p.base_x < lo - reach or p.base_x > hi + reach:
			continue
		for i in p.n:
			var a := Vector2(p.ax[i], p.ay[i])
			var b := Vector2(p.bx[i], p.by[i])
			var hit: Variant = Geometry2D.segment_intersects_segment(from, to, a, b)
			if hit != null:
				var t := a.distance_to(hit) / maxf(a.distance_to(b), 0.001)
				if p.rad[i] >= 3.0 and p.rings.size() >= 2:
					fx.show_rings(hit, p.rings, p.rad[i])
				world.snip(p, i, t, signf(to.x - from.x))
				sound.snip()
				break


## Seed jar: pocket a seed from the air, the soil or a plant; start it anywhere.
func _jar_tap(at: Vector2) -> void:
	var reach := 30.0 / minf(zoom, 2.0) + 10.0
	if pocket.size() < 6:
		var best: World.SeedBit = null
		var best_d := reach
		for s in world.seeds:
			var d := Vector2(s.x, s.y).distance_to(at)
			if d < best_d:
				best_d = d
				best = s
		if best != null:
			pocket.append([best.genome, best.species, best.generation])
			world.take_seed(best)
			fx.sparkle(Vector2(best.x, best.y), best.genome.hue)
			sound.play("pop", 1.4, -12.0)
			_show_pocket()
			return
		var stem := world.pick_stem(at, reach)
		if not stem.is_empty():
			var p: Plant = stem[0]
			if p.alive and p.seeds_ripe > 0:
				p.seeds_ripe -= 1
				pocket.append([p.genome.child(world.rng), p.species, p.generation + 1])
				fx.sparkle(stem[2], p.genome.hue)
				sound.play("pop", 1.4, -12.0)
				_show_pocket()
				return
			elif p.alive and at.y < world.soil.ground_y(at.x) - 30.0:
				hud.nudge("That one has no ripe seed yet.", 2.5)
				return
	if not pocket.is_empty() and at.x > 4.0 and at.x < world.jar_w - 4.0:
		var item: Array = pocket.pop_front()
		var s := world.spawn_seed(item[0], at.x, minf(at.y, world.soil.ground_y(at.x) - 2.0), 0.0, 0.0, null)
		if s != null:
			s.species = item[1]
			s.generation = item[2]
			s.delay = 0.5
			s.life = maxf(s.life, 200.0)
		sound.play("pop", 0.9, -14.0)
		_show_pocket()
	elif pocket.is_empty():
		hud.nudge("The jar is empty. Tap a seed to pocket it.", 2.5)


func _show_pocket() -> void:
	var colours: Array[Color] = []
	for item: Array in pocket:
		colours.append(Color.from_hsv(item[0].hue, 0.5, 0.95))
	hud.set_pocket(colours)


func _prop_tap(at: Vector2) -> void:
	var stem := world.pick_stem(at, 30.0 / minf(zoom, 2.0) + 10.0, 1.2)
	if stem.is_empty():
		hud.nudge("Tap a trunk.", 2.0)
		return
	world.add_prop(stem[0], stem[2])
	sound.play("snip", 0.5, -8.0)
	_trim_braces()


func _trim_braces() -> void:
	var mine := 0
	for b in world.braces:
		if not b.grip:
			mine += 1
	var i := 0
	while mine > 8 and i < world.braces.size():
		if not world.braces[i].grip:
			world.braces.remove_at(i)
			mine -= 1
		else:
			i += 1


func _pour(delta: float) -> void:
	var x := clampf(last_world.x, 6.0, world.jar_w - 6.0)
	world.soil.water(x, delta * 0.5)
	sound.rain_level = 1.0
	fx.rain(Vector2(x, last_world.y))
	if randf() < delta * 5.0:
		sound.drip()
