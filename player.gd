extends CharacterBody3D
## First person. WASD to walk, the mouse to look, Shift to run, Space to jump, hold C to crouch (the web game's: lower,
## and slower). Sat down, the mouse wheel zooms in and out; all the way in on a screen that's playing, one notch more and
## its picture fills the view (the view held still), one back out and it's the room again (or F, in and out). Getting up
## puts the view back. H hides the words on screen (hud.gd).
## E: whatever the crosshair's on (see interact.gd). Click: tapes (see tapes.gd). L: skip an hour (see clock.gd).
## F, stood up: fly (through walls too; Space up, Ctrl down).
## Esc frees the mouse; click to take it back.

const SPEED := 3.2
const RUN := 6.5
const JUMP := 4.2
const SENS := 0.0025
const EYE := 1.6  # the camera, above your feet
const CROUCH_EYE := 1.03  # ...crouched (the web game: 1.06 of 1.65), and you go at 0.55 of your pace
const FOV := 70.0
const ZOOM := 15.0  # as far in as the wheel takes you, sat down (one notch more, looking at a screen that's playing: full screen)
const F_HOLD := 0.35  # F held this long: the time and weather wheel (wheel.gd); let go sooner, it's a tap
const FULL_AIM := 20.0  # degrees off a screen's middle you can be looking and still go full screen on it
const SEAT_EYE := 0.72  # ...and above your hips, sat down (the web game's camera rides the body's head)

var fly := false
var seat = null  # the seat you're in (one of interact.gd's), or null
var seat_fov := FOV  # sat down, the mouse wheel zooms; getting up puts it back
var _f_held := -1.0  # F down this long (-1: it isn't, or it's done its job); held past F_HOLD, the time and weather wheel opens
var full := false  # zoomed right in on a playing screen: its picture edge to edge, the view held still (the wheel back out lets it go)
var crouched := false
var sens_k := 1.0  # mouse sensitivity
var invert_y := false
var _step_d := 0.0
var climb = null  # on a ladder: { dir (1 up, -1 down), L (the ladder's climb), t, ... } (see fixtures.gd)

@onready var cam: Camera3D = $Camera
@onready var tapes: Node = $"../Tapes"
@onready var video: Node = $"../Video"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not ("--shot" in args or "--snapshot" in args):  # (not for --shot: it'd take the mouse off whoever's at the machine)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	# godot --path . -- --demo --shot [--at=x,y,z,yaw,pitch] (degrees) [--hour=h]: shot.png from there, a few seconds in, then quits
	# (--snapshot instead: the whole store as built, as a scene for the editor: tools/snapshot.gd)
	for a in args:
		if a.begins_with("--hour="):
			Clock.h = a.trim_prefix("--hour=").to_float()
	await get_tree().create_timer(4.0).timeout
	for a in args:
		if a.begins_with("--at="):
			var v := a.trim_prefix("--at=").split_floats(",")
			global_position = Vector3(v[0], v[1], v[2])
			rotation.y = deg_to_rad(v[3])
			cam.rotation.x = deg_to_rad(v[4]) if v.size() > 4 else 0.0
			fly = true
			$Shape.disabled = true
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	if "--snapshot" in args:
		preload("res://tools/snapshot.gd").save(owner)
	else:
		get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not full:
		rotate_y(-e.relative.x * SENS * sens_k)
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * SENS * sens_k * (-1.0 if invert_y else 1.0), -1.5, 1.5)
	elif e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_MIDDLE and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()  # (the click that takes the mouse back doesn't also pick something up)
	elif e is InputEventMouseButton and e.pressed and seat != null and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var into: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
		if full and not into:
			_full_screen(false)  # (back out: the room, as zoomed as it was)
		elif into and seat_fov <= ZOOM and _on_a_screen():
			_full_screen(true)
		elif not full:
			seat_fov = clampf(seat_fov + (-2.0 if into else 2.0), ZOOM, FOV)  # (a notch of the wheel: the web game's 100 * 0.02 degrees)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.physical_keycode == KEY_F:
			_f_held = 0.0  # (a tap or a hold: _process, and the key coming back up, tell which)
	elif e is InputEventKey and not e.pressed and e.physical_keycode == KEY_F and _f_held >= 0.0:
		_f_held = -1.0
		_f_tap()


func _f_tap() -> void:  # sat down with a tape on: full screen and back; stood up: flying
	if seat != null and (full or _playing()):
		_full_screen(not full)
	elif seat == null and climb == null:
		fly = not fly
		$Shape.disabled = fly


func _playing() -> bool:
	return tapes.playing != null and not video.url.is_empty()


func _on_a_screen() -> bool:  # a tape's playing, and you're looking at a screen it's on
	if not _playing():
		return false
	var fwd := -cam.global_basis.z
	for sc: Dictionary in Level.data().screens:
		if rad_to_deg(fwd.angle_to(Vector3(sc.x, sc.y, sc.z) - cam.global_position)) < FULL_AIM:
			return true
	return false


func _full_screen(on: bool) -> void:
	full = on
	hud.full_screen(video.texture if on else null, video.content)


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


func start_climb(dir: int, L: Dictionary, ladders: Dictionary) -> void:  # up (1) or down (-1) a ladder (the web game's roofClimb)
	climb = { "dir": dir, "L": L, "t": 0.0, "from": cam.global_position, "roof_y": ladders.roofY, "dur": ladders.dur }
	$Shape.disabled = true
	velocity = Vector3.ZERO
	rotation.y = L.yaw  # facing the rungs, up or down
	cam.position.y = EYE
	cam.rotation.x = 0.0


func _climb(dt: float) -> void:  # walk the step to the foot, then up and out (or over the edge and down): the climb in the web game's roofTick
	var c: Dictionary = climb
	c.t = minf(c.dur, c.t + dt)
	var k: float = c.t / c.dur
	var e := k * k * (3.0 - 2.0 * k)
	var step := 0.04 * sin(k * PI * 12.0)  # a rung at a time
	var y_hi: float = c.roof_y + EYE
	var a := minf(1.0, k * 5.0)
	var at := Vector3(lerpf(c.from.x, c.L.x, a), 0.0, lerpf(c.from.z, c.L.z, a))
	var end: Dictionary = c.L.up if c.dir > 0 else c.L.down
	at.y = (EYE + (y_hi + 0.15 - EYE) * e if c.dir > 0 else y_hi + 0.15 + (EYE - y_hi - 0.15) * e) + step
	if k > 0.92:
		at = at.lerp(Vector3(end.x, y_hi if c.dir > 0 else EYE, end.z), (k - 0.92) / 0.08)
	global_position = at - Vector3(0, EYE, 0)
	if c.t >= c.dur:
		climb = null
		$Shape.disabled = fly
		global_position = Vector3(end.x, (c.roof_y if c.dir > 0 else 0.0) + 0.05, end.z)


func _process(dt: float) -> void:
	if seat == null:
		seat_fov = FOV  # walking resets the seat's zoom
	if _f_held >= 0.0:
		_f_held += dt
		if _f_held >= F_HOLD:
			_f_held = -1.0
			$"../Wheel".open()
	if full and (seat == null or not _playing()):
		_full_screen(false)  # (got up, or the tape's out: back to the room)
	cam.fov += (seat_fov - cam.fov) * minf(1.0, dt * 8.0)
	crouched = seat == null and climb == null and not fly and Input.is_physical_key_pressed(KEY_C)
	if seat == null and climb == null:
		cam.position.y += ((CROUCH_EYE if crouched else EYE) - cam.position.y) * minf(1.0, dt * 10.0)
	var cap: CapsuleShape3D = $Shape.shape  # (down with you: under what you can crouch under)
	cap.height = 1.15 if crouched else 1.7
	$Shape.position.y = cap.height / 2.0


func _physics_process(dt: float) -> void:
	if climb != null:
		_climb(dt)
		return
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
	if global_position.y < -10.0:  # fell out of the level (a floor moved or deleted): back where the game starts you
		global_position = Vector3(0, 0.3, -6)
		velocity = Vector3.ZERO
	if is_on_floor():  # your own footsteps, quieter (you're wearing sneakers)
		_step_d += Vector2(get_real_velocity().x, get_real_velocity().z).length() * dt
		if _step_d > (0.95 if speed > 4.0 else 0.72):
			_step_d = 0.0
			$"../Ambience".step(global_position, 0.35 if crouched else 0.6)


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
