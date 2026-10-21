extends Node
## The loose things and the small ones: the spinning stool (sit, spin, carry it off), the standee (carry it off), the
## cooler's door, the front doors' deadbolt, the toilet's lever and the paper towels, the cardboard bed out back, and
## the movie on the roof (the projector, its VCR, the bedsheet).
## From the web game: store/player.js (the stool: stoolSit, stoolPush, stoolStand, stoolTick, and carrying it and the
## standee), store/tv.js (onE: the toilet, the towels, the lamp, the cooler), store/staff.js (setFrontLock),
## store/chores.js (bathTick), store/customer-mode.js (cmSleep), store/roof.js (the projector and cineTick),
## store/checkout.js (how near, and the words of the tips). Where they are, and the stool's numbers: data/interact.json.
## Different here: anyone can sleep on the cardboard (the web game: customers only), and it's the clock that moves,
## nothing else happens while you're out; the deadbolt keeps the door shut but the signs in the glass don't turn; the
## cooler's thermometer reads the case's air (snacks.gd), and it's in the door's tip too; a thing set down goes where there's a clear line to it, not by
## the web game's test of the floor.

const HOLD := 0.45  # hold E this long to lift the stool or the standee
# The projector's light on the sheet: the web game's (store/roof.js, the sheet's material). A see-through picture, a
# little soft (the focus), brighter in the middle and falling off to the corners, its edge ragged where it lands on the
# folds, a faint spill past the frame; a touch of keystone, since it's aimed up a little. No tape: the VCR's blue.
const SHEET := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform sampler2D uVid : source_color, filter_linear, repeat_disable;
uniform vec4 uImg = vec4(0.5, 0.5, 1.0, 1.0);   // where the frame lands on the sheet: its middle, its size (the sheet = 1)
uniform float uProj = 0.0;                       // how strong: barely there in the sun, the picture after dark
uniform float uBlue = 1.0;
uniform float uFlip = 0.0;                       // (the cloth's own UVs run up it, as the web game's do; the flat stand-in's run down)

void fragment() {
	vec2 pu = (vec2(UV.x, mix(UV.y, 1.0 - UV.y, uFlip)) - uImg.xy) / uImg.zw + 0.5;   // where on the picture this bit of sheet is
	pu.x = (pu.x - 0.5) / (1.0 + 0.035 * (pu.y - 0.5)) + 0.5;
	float n = 0.006 * sin(pu.y * 41.0) + 0.004 * sin(pu.y * 97.0 + 1.7) + 0.005 * sin(pu.x * 57.0 + 0.4);
	float m = smoothstep(-0.012, 0.025, pu.x + n) * (1.0 - smoothstep(0.975, 1.012, pu.x - n)) * smoothstep(-0.012, 0.03, pu.y - n) * (1.0 - smoothstep(0.97, 1.012, pu.y + n));
	vec2 q = pu - 0.5;
	float hot = 1.05 - 0.55 * dot(q, q) * 4.0;
	vec2 c = clamp(vec2(pu.x, 1.0 - pu.y), 0.0, 1.0), px = vec2(1.6 / 528.0, 1.6 / 352.0);   // (a little soft: four taps round the one)
	vec3 vid = (texture(uVid, c).rgb * 2.0 + texture(uVid, c + px * vec2(1.0, 0.0)).rgb + texture(uVid, c - px * vec2(1.0, 0.0)).rgb + texture(uVid, c + px * vec2(0.0, 1.0)).rgb + texture(uVid, c - px * vec2(0.0, 1.0)).rgb) / 6.0;
	vec3 img = mix(vid, vec3(0.06, 0.16, 0.78), uBlue);
	float halo = (1.0 - m) * 0.06 * (1.0 - smoothstep(0.0, 0.12, max(max(-pu.x, pu.x - 1.0), max(-pu.y, pu.y - 1.0))));
	ALBEDO = (img * m * hot + vec3(halo)) * uProj * 1.15 * 0.85;   // (0.85: the cloth it lands on)
}
"""

var T := {}  # data/interact.json's things
var aim := ""
var on_stool := false
var stool_by = null  # one of the staff has it (fetching it, carrying it, sat on it: staff.gd): it's not yours to take meanwhile
var carrying := ""  # "stool" | "cutout" | ""
var cooler_open := false
var locked := false
const OPEN_SIGN := preload("res://world/sign_open.png")  # (the level's sign says CLOSED on both faces)
var _signs: Array = []  # the front door's sign: [its face, faces the street?, its CLOSED picture]
var cine_on := false
var flush_t := 0.0
var tap := false
var _stream := MeshInstance3D.new()
var lifting := false  # E's being held on something that lifts (interact.gd)

var _stool: Node3D
var _stool_top: Node3D
var _cutout: Node3D
var _cooler: Node3D
var _turn: Node3D
var _water: Node3D
var _water_y := 0.0
var _vel := 0.0
var _angle := 0.0
var _spot_ok := true
var _stood := {}
var _wake := -1.0  # the hour you'll wake at, asleep on the cardboard
var _block := StaticBody3D.new()  # the front doors, bolted
var _sheet := MeshInstance3D.new()
var _sheet_mat := ShaderMaterial.new()
var _blue := 1.0  # no tape in: the VCR's blue
var _cloth: MeshInstance3D

@onready var player: CharacterBody3D = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var tapes: Node = $"../Tapes"
@onready var sky: Node3D = $"../Sky"
@onready var video: Node = $"../Video"


func set_locked(on: bool) -> void:  # the deadbolt (E on it, or a saved store coming back: save.gd); the door's sign turned round with it
	locked = on
	_block.get_child(0).disabled = not locked
	if _turn:
		_turn.rotation.z = PI / 2 if locked else 0.0
	for s: Array in _signs:  # [face, faces the street?]: the street sees OPEN while it's unlocked, CLOSED once it's locked; in here, the other side
		var open: bool = s[1] != locked
		var m: StandardMaterial3D = s[0].mesh.surface_get_material(0).duplicate()  # (a sign: drawn unlit, not the room's)
		m.albedo_texture = OPEN_SIGN if open else s[2]
		s[0].set_surface_override_material(0, m)


func _ready() -> void:
	T = Level.data().things
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):
		var p := n.global_position
		if n is MeshInstance3D:
			if p.distance_to(_v(T.lock.turn)) < 0.01:
				_turn = n
			elif T.flush.water != null and p.distance_to(_v(T.flush.water)) < 0.01:
				_water = n
				_water_y = n.position.y
		elif n.get_child_count():
			if p.distance_to(Vector3(T.stool.x, 0, T.stool.z)) < 0.02:
				if _stool != null:
					continue  # (a part of it with the same origin: the first one found is the whole stool)
				_stool = n
				for c in n.get_children():
					if c is Node3D and not c is MeshInstance3D and absf(c.position.y - T.stool.SEAT) < 0.01:
						_stool_top = c  # everything that turns
			elif _cutout == null and p.distance_to(Vector3(T.cutout.x, 0, T.cutout.z)) < 0.02:
				_cutout = n
			elif _cooler == null and p.distance_to(_v(T.cooler.pivot)) < 0.02:
				_cooler = n
	for what in [["the stool", _stool], ["the standee", _cutout], ["the cooler's door", _cooler], ["the deadbolt", _turn]]:
		if what[1] == null:
			push_warning("%s isn't where the web game has it in the level (moved, or deleted?)" % what[0])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.8, 2.3, 0.1)  # (both leaves: the left one's doorway, to x -1.75, was left open)
	shape.shape = box
	shape.disabled = true
	_block.position = Vector3(0.0, 1.15, 0.1)
	_block.add_child(shape)
	add_child(_block)
	for m: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):  # (on the right leaf: one face each way)
		var tex := preload("res://level.gd").texture_of(m)
		if tex in ["vaultbuster_45.jpg", "vaultbuster_46.jpg"]:
			_signs.append([m, m.global_basis.z.z < 0.0, m.mesh.surface_get_material(0).albedo_texture])
	set_locked(locked)  # (open for business: OPEN to the street)
	if T.sink != null:  # the tap's stream: there while it's running
		var water := CylinderMesh.new()
		water.top_radius = 0.006
		water.bottom_radius = 0.007
		water.height = 0.17
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.albedo_color = Color(0.75, 0.88, 1.0, 0.55)
		water.material = wm
		_stream.mesh = water
		_stream.position = _v(T.sink.spout) + Vector3(0, -0.02, 0)
		_stream.visible = false
		add_child(_stream)
	var s: Dictionary = T.cine.sheet  # the picture on the bedsheet: light added to the cloth, over the whole sheet (the shader knows where the frame lands)
	var quad := QuadMesh.new()
	quad.size = Vector2(s.w, s.h)
	var sh := Shader.new()
	sh.code = SHEET
	_sheet_mat.shader = sh
	_sheet_mat.set_shader_parameter("uVid", video.texture)
	_sheet_mat.set_shader_parameter("uImg", Vector4(s.img[0], s.img[1], s.img[2], s.img[3]))
	quad.material = _sheet_mat
	_sheet.mesh = quad
	_sheet.basis = Basis(Quaternion(s.q[0], s.q[1], s.q[2], s.q[3]))
	_sheet.position = _v(s.p) + _sheet.basis.z * 0.05
	_sheet.visible = false
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if mi.global_position.distance_to(_v(s.p)) < 0.02:
			_cloth = mi  # the sheet itself: the light goes on it, folds and all (a flat picture in front would cut through them)
	if _cloth == null:
		push_warning("the bedsheet isn't where the web game has it: the picture's on a flat stand-in")
		_sheet_mat.set_shader_parameter("uFlip", 1.0)
		add_child(_sheet)


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _stool_at() -> Vector3:
	return _stool.global_position if _stool else Vector3(T.stool.x, 0, T.stool.z)


func _process(dt: float) -> void:
	# the stool: bearing friction winds the spin down (a constant drag plus a little that grows with speed); you turn with the seat
	if _vel > 0.0:
		var drag: float = (T.stool.DRAG + T.stool.VISC * _vel) * (1.0 if on_stool or stool_by != null else T.stool.EMPTY) * dt
		var v := maxf(0.0, _vel - drag)
		var d := (_vel + v) / 2.0 * dt  # averaged over the step, so a stop lands smoothly
		_vel = v
		_angle += d
		if on_stool:
			player.rotation.y += d
	if _stool_top:
		Level.put(_stool_top, "rotation:y", _angle)
	if on_stool and (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)):
		_stool_stand()  # any move key gets you up
	if carrying != "":  # carried a little ahead of you; where it would go down, if there's a clear line there
		var n: Node3D = _stool if carrying == "stool" else _cutout
		var fwd := -player.global_basis.z
		var spot: Vector3 = player.global_position + fwd * T.stool.CARRY_D
		n.global_position = Vector3(spot.x, player.global_position.y, spot.z)
		n.rotation.y = player.rotation.y
		var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 0.6, 0), spot + fwd * 0.3 + Vector3(0, 0.6, 0))
		q.exclude = [player.get_rid()]
		_spot_ok = player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if _cooler:
		Level.put(_cooler, "rotation:y", Level.ease_to(_cooler.rotation.y, T.cooler.openA if cooler_open else 0.0, dt * 5.0))  # swings out ~100 degrees
	if flush_t > 0.0 and _water:  # the bowl drains and refills after a flush
		flush_t = maxf(0.0, flush_t - dt)
		var t := 6.0 - flush_t
		_water.position.y = _water_y - T.flush.drop * (t / 1.3 if t < 1.3 else maxf(0.0, 1.0 - (t - 1.3) / 3.8))
		_water.rotation.z += dt * (5.0 if t < 2.5 else 0.0)  # swirl
	elif flush_t > 0.0:
		flush_t = maxf(0.0, flush_t - dt)
	if tap:  # its stream shimmers
		var now := Time.get_ticks_msec() / 1000.0
		_stream.scale = Vector3(1.0 + sin(now * 40.0) * 0.08, 1.0, 1.0 + cos(now * 37.0) * 0.08)
	if _wake >= 0.0 and (Clock.h >= _wake or Clock.warp <= Clock.h):  # morning, or near enough
		_wake = -1.0
		hud.fade("")
		player.set_physics_process(true)
	# the movie on the roof: in the sun it's barely there; after dark it's the picture
	var k := (0.06 + 0.9 * pow(1.0 - sky.level, 1.5)) if cine_on else 0.0
	_blue += ((0.0 if tapes.playing != null and video._shown > 0 else 1.0) - _blue) * minf(1.0, dt * 4.0)
	_sheet.visible = k > 0.0
	if _cloth and _cloth.material_overlay != (_sheet_mat if k > 0.0 else null):  # (each only when it changes: a material touched, everything it's on is, and every light that sees them draws its shadows again)
		_cloth.material_overlay = _sheet_mat if k > 0.0 else null
	for p: Array in [["uProj", k], ["uBlue", _blue]]:
		if _sheet_mat.get_shader_parameter(p[0]) != p[1]:
			_sheet_mat.set_shader_parameter(p[0], p[1])


# ---- what the crosshair's on (called from interact.gd, after the doors); returns the tip, "" if it's nothing of ours

func take_aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	aim = ""
	if carrying != "":
		aim = "carry"
		var what := "stool" if carrying == "stool" else "standee"
		return "E — set the %s down" % what if _spot_ok else "No room for the %s here" % what
	if player.global_position.y > 3.4:  # up on the roof: the projector and its VCR
		for part in [["proj", T.cine.proj], ["vcr", T.cine.vcr]]:
			var to := _v(part[1]) - from
			var t := to.dot(dir)
			if t > 0.2 and t < 2.4 and (to - dir * t).length() < 0.28:
				aim = part[0]
				if aim == "proj":
					return "E — turn the projector %s" % ("off" if cine_on else "on")
				if tapes.held != null:
					return "E — put %s in" % tapes.held.t
				return ("E — eject" + ("" if cine_on else "\nthe projector's off")) if tapes.playing != null else "The VCR\nbring a tape up"
	if not hit:
		return ""
	var at: Vector3 = hit.position
	if hit_d < 2.4 and at.distance_to(_v(T.register.pos)) < 0.55:  # the register's terminal (pos.gd)
		aim = "register"
		return "E — log in to the register"
	if hit_d < 2.2:
		if _stool and stool_by == null and Vector2(at.x - _stool_at().x, at.z - _stool_at().z).length() < 0.34 and at.y < _stool_at().y + 0.9:
			aim = "stool"
			return "Lifting…" if lifting else "E — sit on the stool\nHold E — pick it up"
		if at.distance_to(_v(T.lock.at)) < 0.2:
			aim = "lock"
			return "E — %s the front doors" % ("unlock" if locked else "lock")
		if at.distance_to(_v(T.flush.at)) < 0.16:
			aim = "flush"
			return "Flushing…" if flush_t > 0.0 else "E — flush"
		if T.sink != null and at.distance_to(_v(T.sink.at)) < 0.32:
			aim = "sink"
			return "E — turn the tap %s" % ("off" if tap else "on")
		if T.towels != null and at.distance_to(_v(T.towels.at)) < 0.25:
			aim = "towels"
			return "E — take a paper towel"
	if hit_d < 2.6:
		if _cutout and Vector2(at.x - _cutout.global_position.x, at.z - _cutout.global_position.z).length() < 0.5 and at.y < 2.0:
			aim = "cutout"
			return "Lifting…" if lifting else "Hold E — pick up the standee"
		if (at.distance_to(_v(T.cooler.hit)) < 0.75 or (_cooler and cooler_open and at.distance_to(_cooler.global_position + Vector3(0, 1.0, 0)) < 0.9)):
			aim = "cooler"
			return "E — %s the cooler" % ("close" if cooler_open else "open")
		var b := _v(T.bed.at)
		if absf(at.x - b.x) < 0.6 and absf(at.z - b.z) < 1.2 and at.y < 0.6:
			aim = "bed"
			return "E — lie down a while (3 hours)\nsomebody's cardboard bed"
	return ""


func holdable() -> bool:  # E held on these lifts them
	return carrying == "" and not on_stool and (aim == "stool" or aim == "cutout")


func pick_up() -> void:  # (the hold came good)
	if not holdable():
		return
	carrying = aim
	if carrying == "stool":
		_vel = 0.0
	_solid(_stool if carrying == "stool" else _cutout, false)


func _solid(n: Node, on: bool) -> void:  # what's in your arms doesn't bump into things
	for b: StaticBody3D in n.find_children("*", "StaticBody3D", true, false):
		b.collision_layer = 1 if on else 0


func on_e_first() -> bool:  # before anything else gets E: on the stool it's a shove; with your arms full it's putting that down
	if on_stool:
		_vel = minf(T.stool.MAX, _vel + T.stool.PUSH)
		return true
	if carrying != "":
		if _spot_ok:
			_solid(_stool if carrying == "stool" else _cutout, true)
			carrying = ""
		return true
	return false


func on_e() -> bool:
	match aim:
		"stool":  # sit facing the way you were looking
			_stood = { "at": player.global_position, "yaw": player.rotation.y }
			_angle = player.rotation.y
			on_stool = true
			player.sit({ "kind": "stool", "x": _stool_at().x, "y": _stool_at().y, "z": _stool_at().z, "ry": player.rotation.y - PI, "hipY": T.stool.SEAT + 0.05 })
		"register":
			$"../POS".log_in()
		"cutout":
			pass  # (a tap does nothing: it wants holding)
		"cooler":
			cooler_open = not cooler_open
			$"../Ambience".door("cooler", "open" if cooler_open else "close", Vector3(T.cooler.pivot[0], 1.1, T.cooler.pivot[2]))
		"lock":
			set_locked(not locked)
		"flush":
			if flush_t <= 0.0:
				flush_t = 6.0
				$"../Ambience".flush(_v(T.flush.at))
		"sink":
			tap = not tap
			$"../Ambience".water(_v(T.sink.at), tap)
			_stream.visible = tap
		"towels":
			hud.toast("Turn the tap off first" if tap else "You dry your hands")
		"bed":
			_wake = minf(Clock.CLOSE, Clock.h + 3.0)  # ponytail: never past midnight, as L; sleeping through to morning wants Clock rolling the day
			Clock.warp = _wake
			hud.fade("Zzz…")
			player.set_physics_process(false)
		"proj":
			cine_on = not cine_on
		"vcr":
			tapes.vcr_use()
			if tapes.playing != null:
				cine_on = true  # (a tape in: the projector comes on with it)
		_:
			return false
	return true


func _stool_stand() -> void:  # step off toward where you're facing, or anywhere clear, or back where you came from
	on_stool = false
	var c := _stool_at()
	for da in [0.0, 1.2, -1.2, 2.4, -2.4, PI]:
		var a: float = player.rotation.y + da
		var to := Vector3(c.x - sin(a) * 0.62, c.y, c.z - cos(a) * 0.62)
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), to + Vector3(0, 1.0, 0))
		q.exclude = [player.get_rid()]
		if player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			player.stand(to, player.rotation.y)
			return
	player.stand(_stood.at, _stood.yaw)
