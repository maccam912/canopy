class_name LogBody
extends RigidBody2D
## Fallen wood. A broken-off piece of a plant becomes one rigid body that knocks,
## pins, bridges and props, then rots into the soil where it lies.

const STRIDE := 6   # ax, ay, bx, by, radius, leaf (in body-local coordinates)

var world: World
var segs := PackedFloat32Array()
var genome: Genome
var species := -1
var volume := 0.0
var nutrient := 0.0
var leaf_area := 0.0
var length := 0.0
var rot := 0.0
var rot_time := 60.0
var age := 0.0
var seeds := 0
var flung := false
var landed := false
var touching := 0.0        # seconds left of "resting on a living plant"
var joint := RID()
var joint_rot := 0.0
var joint_plant: Plant
var big := false
var peak_speed := 0.0
var beetles := 0.0
var is_prop := false
var resting := 0.0
var sweep_radius := 0.0
var colliders: Array[CollisionShape2D] = []
var collision_bounds := Rect2()
var overlapping_wood: Dictionary[RID, Object] = {}


func setup(w: World, data: PackedFloat32Array, com: Vector2, vel: Vector2, spin: float) -> void:
	world = w
	position = com
	# Soil and walls are solid immediately. Check for pre-existing overlaps
	# with wood after the standing colliders have synced this tick.
	collision_layer = 0
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = true
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.02
	physics_material_override = mat
	segs = data
	var count := segs.size() / STRIDE
	var m := 0.0
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var by_size: Array = []
	for i in count:
		var o := i * STRIDE
		segs[o] -= com.x
		segs[o + 1] -= com.y
		segs[o + 2] -= com.x
		segs[o + 3] -= com.y
		var a := Vector2(segs[o], segs[o + 1])
		var b := Vector2(segs[o + 2], segs[o + 3])
		var r := segs[o + 4]
		var l := a.distance_to(b)
		volume += r * r * l
		leaf_area += segs[o + 5]
		m += T.RHO * r * r * l + T.LEAF_M * segs[o + 5]
		sweep_radius = maxf(sweep_radius, maxf(a.length(), b.length()) + r)
		lo = lo.min(a).min(b)
		hi = hi.max(a).max(b)
		by_size.append([r * r * l, i])
	length = lo.distance_to(hi)
	mass = maxf(m, 1.0)
	by_size.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	var shapes := 0
	for entry: Array in by_size:
		var i: int = entry[1]
		var o := i * STRIDE
		var a := Vector2(segs[o], segs[o + 1])
		var b := Vector2(segs[o + 2], segs[o + 3])
		var r := segs[o + 4]
		var l := a.distance_to(b)
		if shapes > 0 and (r < 1.0 or l < 4.0 or shapes >= 10):
			continue
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(maxf(r, 1.4) * 2.0, maxf(l, 3.0))
		cs.shape = rect
		cs.position = (a + b) * 0.5
		cs.rotation = (b - a).angle() + PI * 0.5
		add_child(cs)
		colliders.append(cs)
		var bounds := cs.transform * rect.get_rect()
		collision_bounds = bounds if shapes == 0 else collision_bounds.merge(bounds)
		shapes += 1
	rot_time = 22.0 + sqrt(volume) * 0.75
	big = volume > T.FALL_VOL
	linear_damp = 0.05
	angular_damp = 0.15
	var scale := minf(1.0, T.MAX_RELEASE_SPEED / maxf(_tip_speed(vel, spin), 1.0))
	linear_velocity = vel * scale
	angular_velocity = spin * scale


func _tip_speed(vel: Vector2, spin: float) -> float:
	return vel.length() + absf(spin) * sweep_radius


func _overlaps_shape(shape: Shape2D, xf: Transform2D, bounds: Rect2) -> bool:
	var other_bounds := xf * shape.get_rect()
	if not bounds.intersects(other_bounds):
		return false
	for cs in colliders:
		if cs.shape.collide(cs.global_transform, shape, xf):
			return true
	return false


## Use the shapes directly: Rapier's space queries can lag collider changes
## until the next step, after the first contact would already have happened.
func _overlaps(other: Object) -> bool:
	var bounds := global_transform * collision_bounds
	if other is Plant:
		for i in other.col_shapes.size():
			var xf := Transform2D(other.col_a[i], Vector2(other.col_x[i], other.col_y[i]))
			if _overlaps_shape(other.col_shapes[i], xf, bounds):
				return true
	elif bounds.intersects(other.global_transform * other.collision_bounds):
		for cs: CollisionShape2D in other.colliders:
			if _overlaps_shape(cs.shape, cs.global_transform, bounds):
				return true
	return false


func _ignore_wood(rid: RID, other: Object) -> void:
	PhysicsServer2D.body_add_collision_exception(get_rid(), rid)
	overlapping_wood[rid] = other


func _arm_wood_contacts() -> void:
	for p in world.plants:
		if not p.removed and p != joint_plant and _overlaps(p):
			_ignore_wood(p.body, p)
	for l in world.logs:
		if l.collision_layer == 4 and _overlaps(l):
			_ignore_wood(l.get_rid(), l)
	collision_layer = 4
	collision_mask = 1 | 2 | 4


func _restore_clear_contacts() -> void:
	for rid in overlapping_wood.keys():
		var other: Variant = overlapping_wood[rid]
		var present := is_instance_valid(other)
		if present and other is Plant:
			present = not other.removed
		if present and other == joint_plant:
			continue
		if not present or not _overlaps(other):
			PhysicsServer2D.body_remove_collision_exception(get_rid(), rid)
			overlapping_wood.erase(rid)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var dt := state.step
	# Leaves catch the air, so a crown comes down slower than a bare pole.
	if leaf_area > 0.0:
		var drag := minf(leaf_area * 2.2 / mass, 2.5)
		state.linear_velocity -= state.linear_velocity * minf(1.0, drag * dt)
		state.angular_velocity -= state.angular_velocity * minf(1.0, drag * 0.6 * dt)
	var speed := _tip_speed(state.linear_velocity, state.angular_velocity)
	var too_fast := speed > T.MAX_LOG_SPEED
	if too_fast:
		var scale := T.MAX_LOG_SPEED / speed
		state.linear_velocity *= scale
		state.angular_velocity *= scale
		speed = T.MAX_LOG_SPEED
	if speed > peak_speed:
		peak_speed = speed
	var count := state.get_contact_count()
	for i in count:
		var rid := state.get_contact_collider(i)
		var pos := state.get_contact_collider_position(i)
		if rid == world.ground_rid or rid == world.wall_rid:
			if not landed:
				landed = true
				world.on_log_landed(self, pos, peak_speed)
			continue
		var plant: Plant = world.body_plant.get(rid)
		if plant != null and not overlapping_wood.has(rid):
			if not world.debug_no_log_push and not too_fast:
				# Rapier 0.36 reports the impulse toward the collider, so this
				# already points from the log into the stem it struck.
				var impulse := state.get_contact_impulse(i).limit_length(mass * T.MAX_LOG_SPEED)
				var f := impulse / dt
				plant.push(plant.seg_near(pos), pos.x, pos.y, f.x, f.y)
			touching = 0.6
		elif not landed and instance_from_id(state.get_contact_collider_id(i)) is LogBody:
			landed = true
			world.on_log_landed(self, pos, peak_speed)
	# Wood that has come to rest anywhere (propped on stems, say) is down too.
	if not landed:
		if speed < 6.0 and age > 1.0:
			resting += dt
			if resting > 1.0:
				landed = true
				world.on_log_landed(self, global_position, peak_speed)
		else:
			resting = 0.0


func tick(dt: float) -> void:
	age += dt
	if touching > 0.0:
		touching -= dt
		if sleeping:
			sleeping = false
	if joint.is_valid():
		var gone := joint_plant == null or joint_plant.removed
		if gone or age > 4.0 or (age > 0.25 and absf(rotation - joint_rot) > 1.25):
			release()
	if collision_layer == 0:
		_arm_wood_contacts()
	_restore_clear_contacts()


func hinge(plant: Plant, at: Vector2) -> void:
	joint = PhysicsServer2D.joint_create()
	PhysicsServer2D.joint_make_pin(joint, at, plant.body, get_rid())
	_ignore_wood(plant.body, plant)
	joint_plant = plant
	joint_rot = rotation


func release() -> void:
	if joint.is_valid():
		PhysicsServer2D.free_rid(joint)
		joint = RID()
	joint_plant = null


func moving() -> bool:
	return not sleeping and (linear_velocity.length_squared() > 60.0 or absf(angular_velocity) > 0.12)


func span() -> Vector2:
	var lo := 1e9
	var hi := -1e9
	var xf := global_transform
	for i in segs.size() / STRIDE:
		var o := i * STRIDE
		var a := xf * Vector2(segs[o], segs[o + 1])
		var b := xf * Vector2(segs[o + 2], segs[o + 3])
		lo = minf(lo, minf(a.x, b.x))
		hi = maxf(hi, maxf(a.x, b.x))
	return Vector2(lo, hi)
