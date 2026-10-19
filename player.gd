extends CharacterBody3D
## First person. WASD to walk, the mouse to look, Shift to run, Space to jump, hold C to crouch (the web game's: lower,
## and slower). Sat down, the mouse wheel zooms in and out; getting up puts the view back.
## E: the couch, the TV (see tapes.gd). Click: tapes (see tapes.gd).
## F: fly (through walls too; Space up, Ctrl down).
## Esc frees the mouse; click to take it back.

const SPEED := 3.2
const RUN := 6.5
const JUMP := 4.2
const SENS := 0.0025
const EYE := 1.6  # the camera, above your feet
const CROUCH_EYE := 1.03  # ...crouched (the web game: 1.06 of 1.65), and you go at 0.55 of your pace
const FOV := 70.0
const ZOOM := 28.0  # as far in as the wheel takes you, sat down
const SEAT_EYE := 0.72  # ...and above your hips, sat down (the web game's camera rides the body's head)

var fly := false
var spawn := Vector3.ZERO  # where the store starts you (store.gd)
var seat = null  # the seat you're in (store.gd's couch), or null
var seat_fov := FOV  # sat down, the mouse wheel zooms; getting up puts it back
var crouched := false
var sens_k := 1.0  # mouse sensitivity
var invert_y := false

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--shot" in args:  # (not for --shot: it'd take the mouse off whoever's at the machine)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# godot --path . -- --demo --shot [--at=x,y,z,yaw,pitch] (degrees): shot.png from there, a few seconds in, then quits
	await get_tree().create_timer(3.0).timeout
	for a in args:
		if a.begins_with("--at="):
			var v := a.trim_prefix("--at=").split_floats(",")
			global_position = Vector3(v[0], v[1], v[2])
			rotation.y = deg_to_rad(v[3])
			cam.rotation.x = deg_to_rad(v[4]) if v.size() > 4 else 0.0
			fly = true
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * SENS * sens_k)
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * SENS * sens_k * (-1.0 if invert_y else 1.0), -1.5, 1.5)
	elif e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_MIDDLE and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()  # (the click that takes the mouse back doesn't also pick something up)
	elif e is InputEventMouseButton and e.pressed and seat != null and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		seat_fov = clampf(seat_fov + (2.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -2.0), ZOOM, FOV)  # (a notch of the wheel: the web game's 100 * 0.02 degrees)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.physical_keycode == KEY_F and seat == null:
			fly = not fly
			$Shape.disabled = fly


func sit(s: Dictionary) -> void:  # looking the way the seat faces
	seat = s
	$Shape.disabled = true
	velocity = Vector3.ZERO
	cam.position.y = EYE
	global_position = Vector3(s.x, s.y + s.hipY + SEAT_EYE - EYE, s.z)
	rotation.y = s.ry + PI
	cam.rotation.x = 0.0


func stand(at: Vector3, yaw: float) -> void:  # back where you were stood
	seat = null
	$Shape.disabled = fly
	global_position = at
	rotation.y = yaw


func _process(dt: float) -> void:
	if seat == null:
		seat_fov = FOV  # walking resets the seat's zoom
	cam.fov += (seat_fov - cam.fov) * minf(1.0, dt * 8.0)
	crouched = seat == null and not fly and Input.is_physical_key_pressed(KEY_C)
	if seat == null:
		cam.position.y += ((CROUCH_EYE if crouched else EYE) - cam.position.y) * minf(1.0, dt * 10.0)
	var cap: CapsuleShape3D = $Shape.shape  # (down with you: under what you can crouch under)
	cap.height = 1.15 if crouched else 1.7
	$Shape.position.y = cap.height / 2.0


func _physics_process(dt: float) -> void:
	if seat != null:
		return
	var dir := Vector3(_key(KEY_D) - _key(KEY_A), 0, _key(KEY_S) - _key(KEY_W)).normalized()
	var speed := (RUN if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED) * (0.55 if crouched else 1.0)
	if fly:
		var up := _key(KEY_SPACE) - _key(KEY_CTRL)
		global_position += (cam.global_basis * dir + Vector3.UP * up) * speed * 2.0 * dt
		velocity = Vector3.ZERO
		return
	var v := global_basis * dir * speed
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = JUMP if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
	else:
		velocity.y -= 9.8 * dt
	_step_up(dt)
	move_and_slide()
	if global_position.y < -10.0:  # fell out of the level: back where the store starts you
		global_position = spawn
		velocity = Vector3.ZERO


const STEP := 0.32  # as high as you'll step up without jumping: a curb, a stair


func _step_up(dt: float) -> void:  # walking into something low: up onto it (the web game's floor is just the height under you; here it takes doing)
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if not is_on_floor() or motion.length() < 0.001:
		return
	var from := global_transform
	var probe := motion.normalized() * maxf(motion.length(), 0.12)  # (a little ahead: far enough to be over the edge)
	if not test_move(from, probe) or test_move(from, Vector3.UP * STEP):
		return  # nothing in the way, or no headroom
	var raised := from.translated(Vector3.UP * STEP)
	if test_move(raised, probe):
		return  # still in the way that high: a wall
	var landing := KinematicCollision3D.new()
	if test_move(raised.translated(probe), Vector3.DOWN * STEP, landing) and landing.get_normal().y > 0.7 and landing.get_travel().length() < STEP - 0.01:
		global_position = raised.origin + probe + landing.get_travel()


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0
