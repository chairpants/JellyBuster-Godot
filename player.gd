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
const FOV := 60.0
const ZOOM := 15.0  # as far in as the wheel takes you, sat down (one notch more, looking at a screen that's playing: full screen)
const F_HOLD := 0.35  # F held this long: the time and weather wheel (wheel.gd); let go sooner, it's a tap
const FULL_AIM := 20.0  # degrees off a screen's middle you can be looking and still go full screen on it
const SEAT_EYE := 0.72  # ...and above your hips, sat down (the web game's camera rides the body's head)

var fly := false
var seat = null  # the seat you're in (one of interact.gd's), or null
var fov := FOV  # yours (the settings' FIELD OF VIEW: picture.gd)
var seat_fov := FOV  # sat down, the mouse wheel zooms; getting up puts it back
var _f_held := -1.0  # F down this long (-1: it isn't, or it's done its job); held past F_HOLD, the time and weather wheel opens
var full := false  # zoomed right in on a playing screen: its picture edge to edge, the view held still (the wheel back out lets it go)
var crouched := false
var sens_k := 1.0  # mouse sensitivity
var invert_y := false
var _step_d := 0.0
var _eye := EYE  # the view's height over your feet, stood or crouched (the step's lag, _rise, on top)
var _rise_from := 0.0  # a step just taken: the view's height behind your body's when you took it, let out over the stride
var _rise_t := 0.0
var _rise_dur := 1.0
var _tread := NAN  # the height of the tread under you, last frame: what the view stands on (NAN, off your feet: your body)
var _air_t := 0.0  # off your feet this long (INF: jumped)
var _pace := SPEED  # the pace you're walking at (not what's left of it when your body waits on the view)
var _ahead := Vector3.ZERO  # how far a step up set your body on past your stride, walked off before you go on (the view's where you'd be)
var _stairs := 0.0  # on stairs (a step up or down this recently): slower, up more than down
var _stairs_up := true
var climb = null  # on a ladder: { dir (1 up, -1 down), L (the ladder's climb), t, ... } (see fixtures.gd)

@onready var cam: Camera3D = $Camera
@onready var tapes: Node = $"../Tapes"
@onready var video: Node = $"../Video"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := "--shot" in args or "--snapshot" in args
	if not shot:  # (not for --shot: it'd take the mouse off whoever's at the machine)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not shot and not Array(args).any(func(a: String) -> bool: return preload("res://save.gd").SETUP.any(func(f: String) -> bool: return a.begins_with(f))):
		return
	# godot --path . -- --demo --shot [--at=x,y,z,yaw,pitch] (degrees) [--hour=h] [--weather=rain|snow|fog[,1 wild]] [--lights] [--off=zone] [--flash] [--film] [--walk=s]: shot.png from there, a few seconds in, then quits
	# (--snapshot instead: the whole store as built, as a scene for the editor: tools/snapshot.gd. Without either: set up as asked, and play on from there)
	for a in args:
		if a.begins_with("--hour="):
			Clock.h = a.trim_prefix("--hour=").to_float()
		elif a.begins_with("--weather="):
			var wx := a.trim_prefix("--weather=").split(",")  # (rain,1: a thunderstorm)
			$"../Weather".set_now.call_deferred(wx[0], 0.9, 0.0, wx[1].to_float() if wx.size() > 1 else 0.0)
	await get_tree().create_timer(4.0).timeout
	for a in args:
		if a == "--lights":  # every room's lights on
			for z: String in $"../Lights".zone_on:
				$"../Lights".put_zone(z, true)
		elif a == "--flash":  # a lightning strike, held (weather.gd's, at full)
			var wx: Node = $"../Weather"
			wx.set_process(false)
			wx._bolt.visible = true
			wx._bolt.light_energy = wx.BOLT.energy
			wx._bolt.light_volumetric_fog_energy = 2.0 * (1.0 - $"../Sky"._inside)
			$"../Lights".flash = 1.0
			$"../WorldEnvironment".environment.background_energy_multiplier = 5.0
		elif a == "--film":  # a test card on every screen and the projector running, the roof's too (no server needed)
			$"../Video".test_card()
			$"../Things".cine_on = true
			$"../Tapes"._screens_show(true)
		elif a.begins_with("--off="):  # and that one's off
			$"../Lights".put_zone.call_deferred(a.trim_prefix("--off="), false)
		elif a.begins_with("--at="):
			var v := a.trim_prefix("--at=").split_floats(",")
			global_position = Vector3(v[0], v[1], v[2])
			rotation.y = deg_to_rad(v[3])
			cam.rotation.x = deg_to_rad(v[4]) if v.size() > 4 else 0.0
			fly = true
			$Shape.disabled = true
	for a in args:
		if a.begins_with("--walk="):  # walk forward that many seconds (not flying, solid), and say where it got to
			fly = false
			$Shape.disabled = false
			var w := InputEventKey.new()
			w.physical_keycode = KEY_W
			w.pressed = true
			Input.parse_input_event(w)
			await get_tree().create_timer(a.trim_prefix("--walk=").to_float()).timeout
			w = w.duplicate()
			w.pressed = false
			Input.parse_input_event(w)
			print("walk: got to %s" % global_position)
	for a in args:
		if a.begins_with("--perf="):  # how it runs from here: that many seconds unthrottled, then the averages, and quit
			await _perf(a.trim_prefix("--perf=").to_float())
	if not shot:
		return
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	if "--snapshot" in args:
		preload("res://tools/snapshot.gd").save(owner)
	else:
		get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


func _perf(secs: float) -> void:  # (--perf=s: frames a second, and what each frame drew and cost, averaged; the slowest frame)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(1.0).timeout  # (settled)
	var sums := { "draws": 0.0, "objects": 0.0, "prims": 0.0, "process": 0.0, "physics": 0.0 }
	var frames := 0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < secs * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		sums.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		sums.prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sums.physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("perf: %.1f fps (%.2f ms a frame, slowest %.1f) · %d draw calls · %d objects · %dk triangles · scripts %.2f ms · physics %.2f ms" % [1000.0 / ms, ms, worst, sums.draws / frames, sums.objects / frames, sums.prims / frames / 1000.0, sums.process / frames, sums.physics / frames])
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
			seat_fov = clampf(seat_fov + (-2.0 if into else 2.0), ZOOM, fov)  # (a notch of the wheel: the web game's 100 * 0.02 degrees)
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
	_stride_reset()
	cam.position = Vector3(0, EYE, 0)
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
	_stride_reset()
	cam.position = Vector3(0, EYE, 0)
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
		seat_fov = fov  # walking resets the seat's zoom
	if _f_held >= 0.0:
		_f_held += dt
		if _f_held >= F_HOLD:
			_f_held = -1.0
			$"../Wheel".open()
	if full and (seat == null or not _playing()):
		_full_screen(false)  # (got up, or the tape's out: back to the room)
	cam.fov += (seat_fov - cam.fov) * minf(1.0, dt * 8.0)
	crouched = seat == null and climb == null and not fly and _key(KEY_C) > 0.0
	if seat == null and climb == null:
		_eye += ((CROUCH_EYE if crouched else EYE) - _eye) * minf(1.0, dt * 10.0)
		var base := global_position.y if is_nan(_tread) else _tread
		cam.position = Vector3(0, base - global_position.y + _eye + _rise(), 0) - global_basis.inverse() * _ahead  # (off the tread you're over, a step's rise let out over the stride; and back where your pace has you)
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
	var speed := (RUN if _key(KEY_SHIFT) > 0.0 else SPEED) * (0.55 if crouched else 1.0)
	if fly:
		var up := _key(KEY_SPACE) - _key(KEY_CTRL)
		global_position += (cam.global_basis * dir + Vector3.UP * up) * speed * 2.0 * dt
		velocity = Vector3.ZERO
		_stride_reset()
		return
	_rise_t += dt
	_stairs = maxf(0.0, _stairs - dt)
	if _stairs > 0.0:  # (some of each stride goes into the rise, or holding back on the way down)
		speed *= STAIRS_UP if _stairs_up else STAIRS_DOWN
	var v := global_basis * dir * speed
	_pace = speed
	velocity.x = v.x
	velocity.z = v.z
	var jumped := false
	if is_on_floor():
		jumped = Input.is_physical_key_pressed(KEY_SPACE)
		velocity.y = JUMP if jumped else 0.0
	else:
		velocity.y -= 9.8 * dt
	_step_up(dt)
	if dir == Vector3.ZERO:
		_ahead = Vector3.ZERO  # (stood still: the view settles where the body is)
	elif _ahead != Vector3.ZERO:  # what a step up carried you on, walked off: the body waits while the view catches up
		var stride := Vector2(velocity.x, velocity.z).length() * dt
		var pay := minf(_ahead.length(), stride)
		_ahead = _ahead.move_toward(Vector3.ZERO, pay)
		var k := (stride - pay) / stride if stride > 0.0 else 0.0
		velocity.x *= k
		velocity.z *= k
	move_and_slide()
	_air_t = 0.0 if is_on_floor() else _air_t + dt
	if jumped:
		_air_t = INF  # (off your feet till you land: the view goes with you)
	if not is_on_floor() and _air_t < 0.2:  # off the edge of a step, not jumping: down onto the next (its nosing will do), not a fall
		var drop := KinematicCollision3D.new()
		if test_move(global_transform, Vector3.DOWN * GLUE, drop) and drop.get_normal().y > 0.3:
			global_position.y += drop.get_travel().y
			velocity.y = 0.0
			_air_t = 0.0
	# the view goes by the tread under you, not your body (which rolls down a stair's nosings as if a ramp, and is up the
	# next step before you're over it): a tread higher or lower than last frame's is a step, a stride's rise or fall
	var under := _tread_under(global_position - _ahead) if _air_t < 0.2 else NAN
	if not is_nan(under) and absf(under - global_position.y) > REACH:
		under = NAN  # (further down than that: off an edge, falling. The view goes with your body)
	if not is_nan(under) and not is_nan(_tread) and absf(under - _tread) > 0.06 and absf(under - _tread) < REACH:  # (more than a mat, a rug; less than being put somewhere else)
		_stepped(under - _tread)
	_tread = under
	if global_position.y < -10.0:  # fell out of the level (a floor moved or deleted): back where the game starts you
		global_position = Vector3(0, 0.3, -6)
		velocity = Vector3.ZERO
	if is_on_floor():  # your own footsteps, quieter (you're wearing sneakers)
		_step_d += Vector2(get_real_velocity().x, get_real_velocity().z).length() * dt
		if _step_d > (0.95 if speed > 4.0 else 0.72):
			_step_d = 0.0
			$"../Ambience".step(global_position, 0.35 if crouched else 0.6)


const STEP := 0.32  # as high as you'll step up without jumping: a curb, a stair
const TREAD := 0.27  # a stair's going (the booth's, the iron stair's): a stride a step, the view's rise let out over it
const STAIRS_UP := 0.5  # your pace on stairs, of the flat's: up, half of each stride's spent lifting you
const STAIRS_DOWN := 0.7  # ...down, a step at a time, held back
const GLUE := 0.5  # off the edge of a step, down to what's this far under you: you step down to it (an open stair's next nosing), not fall
const REACH := 0.7  # the tread under you this far from your body is still the one you're on: down an open stair, your body's on the nosing above while you're over the next one down
const ON_STAIRS := 0.45  # a step up or down this recently, you're still on the stairs (they come a stride apart)


func _step_up(dt: float) -> void:  # walking into something low: up onto it (the web game's floor is just the height under you; here it takes doing)
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if not is_on_floor() or motion.length() < 0.001 or _ahead.length() > 0.01:
		return  # (or still on from the last step up: the next waits on your stride)
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
		_ahead += probe  # (on past the edge to stand on it: more than this stride, to come off the next ones)


func _tread_under(at: Vector3) -> float:  # the height of what's straight under you, your feet's reach about (NAN: nothing)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 1.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else NAN


func _stepped(h: float) -> void:  # the tread under you's a step h higher (or lower): the view, left where it was, follows over the stride
	_rise_from = _rise() - h
	_rise_t = 0.0
	_rise_dur = clampf(TREAD / _pace, 0.14, 0.5)
	_stairs = ON_STAIRS
	_stairs_up = h > 0.0
	_step_d = 0.0  # a footfall on each step
	$"../Ambience".step(global_position, 0.35 if crouched else 0.6)


func _rise() -> float:  # the view's height behind (or ahead of) the tread's: eased in and out over the stride, a step at a time
	var k := clampf(_rise_t / _rise_dur, 0.0, 1.0)
	return _rise_from * (1.0 - k * k * (3.0 - 2.0 * k))


func _stride_reset() -> void:  # (sat down, on a ladder, flying: no step under way)
	_rise_from = 0.0
	_ahead = Vector3.ZERO
	_stairs = 0.0
	_eye = EYE
	_tread = NAN


func _key(k: Key) -> float:  # (not while typing: the cover search's box, covers.gd; the register, pos.gd)
	return 1.0 if Input.is_physical_key_pressed(k) and not get_viewport().gui_get_focus_owner() is LineEdit and not $"../POS".open else 0.0
