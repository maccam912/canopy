extends Node2D
## Wires the simulation to the screen: views, camera, and one-finger input.

const FAST := 8.0

var world: World
var back: JarBack
var front: JarFront
var fx: Fx
var plant_layer: Node2D
var cam: Camera2D
var views := {}

var base_zoom := 1.0
var zoom := 1.0
var focus := Vector2.ZERO
var touches := {}
var gesture := ""          # "", "sun", "cut", "hold", "pinch"
var down_at := Vector2.ZERO
var down_time := 0.0
var last_world := Vector2.ZERO
var sun_track := 0.0
var fast_latch := false
var holding_fast := false
var pinch_dist := 0.0
var pinch_mid := Vector2.ZERO

var shot_path := ""
var shot_frames := 0
var smoke := false
var shot_done := false
var frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(Time.get_unix_time_from_system())
	var start_speed := 1.0
	var start_phi := 0.0
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
			"--seed":
				world_seed = int(args[k + 1])
				k += 1
			"--speed":
				start_speed = float(args[k + 1])
				k += 1
			"--phi":
				start_phi = float(args[k + 1])
				k += 1
			"--warp":
				# Run the whole game faster while keeping every physics step 1/60 s.
				var warp := float(args[k + 1])
				Engine.time_scale = warp
				Engine.physics_ticks_per_second = int(60.0 * warp)
				Engine.max_physics_steps_per_frame = int(2.0 * warp)
				k += 1
		k += 1

	world = World.new()
	world.z_index = 1
	back = JarBack.new()
	back.z_index = -5
	plant_layer = Node2D.new()
	fx = Fx.new()
	fx.z_index = 3
	front = JarFront.new()
	front.z_index = 6
	add_child(back)
	add_child(plant_layer)
	add_child(world)
	add_child(fx)
	add_child(front)
	world.plant_added.connect(_on_plant_added)
	world.plant_removed.connect(_on_plant_removed)
	world.log_added.connect(_on_log_added)
	world.setup(world_seed)
	back.setup(world)
	front.setup(world)
	fx.setup(world)
	world.sun_phi = start_phi
	world.sow_starters()
	world.speed = start_speed
	fast_latch = start_speed > 1.0

	cam = Camera2D.new()
	add_child(cam)
	focus = Vector2(world.jar_w * 0.5, -world.jar_h * 0.5 + 6.0)
	get_viewport().size_changed.connect(_fit)
	_fit()


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
	views[p.id] = v


func _on_plant_removed(p: Plant) -> void:
	var v: PlantView = views.get(p.id)
	if v != null:
		views.erase(p.id)
		v.queue_free()


func _on_log_added(l: LogBody) -> void:
	var v := LogView.new()
	v.body = l
	v.leaf_tex = Art.leaf()
	l.add_child(v)


func _process(delta: float) -> void:
	frame += 1
	if gesture == "hold" and not holding_fast and Time.get_ticks_msec() * 0.001 - down_time > 0.32:
		holding_fast = true
	var want := FAST if (fast_latch or holding_fast or Input.is_key_pressed(KEY_SPACE)) else 1.0
	if not smoke and shot_path == "":
		world.speed = want
	if smoke and frame >= 600:
		print("CANOPY_SMOKE_PASS plants=%d t=%.0f" % [world.plants.size(), world.time])
		get_tree().quit()
	if shot_path != "" and frame >= shot_frames and not shot_done:
		shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("SHOT ", shot_path, " t=", world.time, " plants=", world.plants.size(), " logs=", world.logs.size(), " falls=", world.count_falls, " fps=", Engine.get_frames_per_second())
		get_tree().quit()


# ------------------------------------------------------------------ input ----

func to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
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
			touches.erase(event.index)
			if gesture == "pinch":
				if touches.size() < 2:
					gesture = ""
			elif touches.is_empty():
				_up()
	elif event is InputEventScreenDrag:
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
		if event.keycode == KEY_F:
			fast_latch = not fast_latch
		elif event.keycode == KEY_ESCAPE and OS.get_name() != "Android":
			get_tree().quit()


func _down(screen: Vector2) -> void:
	var at := to_world(screen)
	down_at = screen
	down_time = Time.get_ticks_msec() * 0.001
	last_world = at
	holding_fast = false
	if at.distance_to(front.sun_pos(world.sun_phi)) < 90.0 / minf(zoom, 2.0) + 30.0 or at.y < world.lid_y - 24.0 or at.x < -24.0 or at.x > world.jar_w + 24.0:
		gesture = "sun"
		world.sun_vel = 0.0
		sun_track = 0.0
	else:
		gesture = "hold"


func _move(screen: Vector2) -> void:
	var at := to_world(screen)
	if gesture == "sun":
		var phi := front.phi_at(at)
		var dt := maxf(get_process_delta_time(), 0.008)
		sun_track = lerpf(sun_track, (phi - world.sun_phi) / dt, 0.4)
		world.sun_phi = phi
	elif gesture == "hold":
		if screen.distance_to(down_at) > 10.0 and not holding_fast:
			gesture = "cut"
	if gesture == "cut":
		_cut(last_world, at)
		fx.swipe(last_world, at)
	last_world = at


func _up() -> void:
	if gesture == "sun":
		# A flick sets the sun swinging; a slow release parks it.
		world.sun_vel = clampf(sun_track * 0.25, -0.6, 0.6) if absf(sun_track) > 0.5 else 0.0
	_cancel()


func _cancel() -> void:
	gesture = ""
	holding_fast = false


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
				world.snip(p, i, t, signf(to.x - from.x))
				break
