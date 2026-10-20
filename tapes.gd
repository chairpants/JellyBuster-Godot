extends Node
## Tapes: off the shelf into your hand, held up to look at, back into its slot; into the VCR and onto the TV.
## (From VaultBuster's tapes.gd, itself from the web game's store/tv.js.)
##
## Click a tape: it comes off the shelf, held up to look at. Click again: it's in your hand. Right-click while you're
## still looking: back it goes. Click its empty slot: back it goes. Click with one in hand: held up again.
## E at the theater's screen or the lounge's TV: the tape in hand goes in and plays there (and on the other screens, and
## the CRTs hung over the aisles); E again: out it comes.
## Up to 9 carried; 1-9 or the wheel picks which is in hand. , . held: rewind / fast-forward (a bar at the bottom; it plays from there half a second after they're let go). [ ] the episode before / after.
## R: turn the tape in hand over (held up, close), to read the back of its box (backbox.gd); R again: the front.
##
## The shelves' tapes are drawn a chunk of CHUNK at a time (a MultiMesh each), their covers layers of a texture array,
## filled in as Jellyfin's covers arrive (cached in user://covers720, see Library.gd). Till then: the section's colour.

const REACH := 3.4
const INV_MAX := 9
const CELL := 0.25
const CHUNK := 1024  # tapes per draw call (and per texture array)
const COVER := Vector2i(128, 192)  # a cover on the shelf. ponytail: uncompressed RGB, ~100 MB a chunk; VRAM-compress them if a big library runs short
const WORKERS := 6  # covers fetching at once
const YELLOW := Color(1, 0.831, 0)
const SCRUB_HOLD := 0.25  # rewind / fast-forward: held this long before it starts winding
const SCRUB_WAIT := 0.5  # and after both keys are let go, this long before it plays from there
const RESUME := "user://vcr.cfg"  # what's in the VCR, and how far in: kept as it plays, so the next start picks it up (_resume)
const RESUME_EVERY := 5.0
const TAPE_UNIFORMS := """uniform float scissor = 0.5;
uniform sampler2DArray covers : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 size;
varying vec2 face_uv;
varying float front;
varying float layer;"""
const TAPE_VERTEX := """void vertex() {
	face_uv = vec2(VERTEX.x / size.x + 0.5, 0.5 - VERTEX.y / size.y);
	front = NORMAL.z;
	layer = INSTANCE_CUSTOM.r;"""


static func _shader() -> String:  # the room's own light (room.gd), on a cover from the array (the box's other faces black): lit like the shelf it's on
	return preload("res://room.gd").SHADER.replace("MODES", "cull_back").replace("ALPHA_CODE", "").replace("FILTER", "filter_linear_mipmap") \
		.replace("uniform float scissor = 0.5;", TAPE_UNIFORMS).replace("void vertex() {", TAPE_VERTEX) \
		.replace("vec4 a = albedo;", "vec4 a = front > 0.5 ? vec4(texture(covers, vec3(face_uv, round(layer))).rgb, 1.0) : vec4(vec3(0.04), 1.0);")


var HAND := Transform3D(Basis.from_euler(Vector3(0.05, -0.4, 0.06)), Vector3(0.3, -0.28, -0.55))  # carried
var LOOK := Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.22))  # held up, cover to you: about 60% of the screen's height (fov 70)
var LOOK_BACK := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.165))  # turned over, closer: the small print, the box about 85% of the screen's height

var size: Vector3 = preload("res://store.gd").TAPE
var tapes: Array = []
var screens: Array = []
var hovered = null  # the tape the crosshair's on
var held = null
var inspecting := false  # held up in view (true) or carried (false)
var flipped := false  # held up, back to you
var peek = null  # the tape you've only just picked up to look at: right-click still puts it back
var aim_slot := false
var aim_tv = null  # the screen the crosshair's on
var playing = null  # { tape, idx }
var inv: Array = []  # the tapes you're carrying, the one in hand among them
var inv_sel := -1  # which of them is in hand (-1: empty-handed)

var _resume_t := 0.0
var _scrub := { "to": -1.0, "held": 0.0, "wait": 0.0, "dir": 1.0 }  # rewinding / fast-forwarding: to where (-1: not), how long the key's been held, the wait after it's let go
var _grid := {}  # cell -> [tape index]
var _chunks: Array = []  # { mm: MultiMesh, tex: Texture2DArray }
var _hand := Node3D.new()
var _hand_cover := MeshInstance3D.new()
var _hand_back := MeshInstance3D.new()
var _backs: Node = preload("res://backbox.gd").new()
var _dwell := { "on": null, "t": 0.0 }  # the tape the crosshair's settled on, and how long: past DWELL, its back starts drawing
const DWELL := 0.25
var _box := MeshInstance3D.new()
var _quads: Array[MeshInstance3D] = []
var _next_cover := 0
var _gen := 0  # which stocking the cover workers are filling (a restock leaves the old ones to give up)
var _shrinking := {}  # covers being loaded and shrunk (WorkerThreadPool tasks): seen through before the game closes

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var video: Node = $"../Video"


func _ready() -> void:
	_box.mesh = _wire_box()
	_box.visible = false
	add_child(_box)
	cam.add_child(_hand)
	var body := MeshInstance3D.new()  # the tape in hand: a black box, its cover on the front
	body.mesh = BoxMesh.new()
	body.mesh.size = size
	body.mesh.material = StandardMaterial3D.new()
	body.mesh.material.albedo_color = Color(0.04, 0.04, 0.04)
	_hand.add_child(body)
	_hand_cover.mesh = QuadMesh.new()
	_hand_cover.mesh.size = Vector2(size.x, size.y)
	_hand_cover.position.z = size.z / 2.0 + 0.001
	_hand_cover.material_override = StandardMaterial3D.new()
	_hand.add_child(_hand_cover)
	_hand_back.mesh = _hand_cover.mesh
	_hand_back.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -size.z / 2.0 - 0.001))
	var bm := StandardMaterial3D.new()
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC  # (read up close and at an angle: crisp)
	bm.albedo_color = Color(0.12, 0.12, 0.14)
	_hand_back.material_override = bm
	_hand.add_child(_hand_back)
	for mi: MeshInstance3D in [body, _hand_cover, _hand_back]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # (it moves with you: a shadow from it, and every light near you would draw its shadows again each frame)
	add_child(_backs)
	_hand.visible = false
	_saver_build()
	video.started.connect(_on_started)
	video.ended.connect(func() -> void: step_episode(1))
	video.failed.connect(func(why: String) -> void: hud.toast("⚠ " + why))
	stock.call_deferred($"../Store")  # (once the store's built its shelves)


func stock(store: Node) -> void:  # the store's tapes onto its shelves (store.gd has placed them), and the pictures onto the screens
	for c in _chunks:
		c.mi.queue_free()
	for q in _quads:
		q.queue_free()
	_chunks.clear()
	_quads.clear()
	_grid.clear()
	inv.clear()
	inv_sel = -1
	held = null
	_hand.visible = false
	if playing != null:
		video.stop()
		playing = null
	tapes = store.slots
	screens = Level.data().screens.filter(func(sc: Dictionary) -> bool: return sc.kind in ["theater", "tv"])
	var colours := {}  # a colour per section, till the covers come
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = _shader()
	mat.set_shader_parameter("size", size)
	for i in tapes.size():
		var t: Dictionary = tapes[i]
		t.merge({ "off": false, "ep": 0, "at": 0.0, "i": i })
		_grid.get_or_add(_cell(t.xf.origin), []).append(i)
		if i % CHUNK == 0:
			var n := mini(CHUNK, tapes.size() - i)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = BoxMesh.new()
			mm.mesh.size = size
			mm.instance_count = n
			var images: Array[Image] = []
			for j in n:
				var c: Color = colours.get_or_add(tapes[i + j].c, Color.from_hsv(colours.size() * 0.13, 0.45, 0.55))
				var img := Image.create(COVER.x, COVER.y, false, Image.FORMAT_RGB8)
				img.fill(c)
				img.generate_mipmaps()
				images.append(img)
			var tex := Texture2DArray.new()
			tex.create_from_images(images)
			var m: ShaderMaterial = mat.duplicate()
			m.set_shader_parameter("covers", tex)
			mm.mesh.material = m
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			add_child(mi)
			_chunks.append({ "mm": mm, "tex": tex, "mi": mi })
		var ch: Dictionary = _chunks[i / CHUNK]
		ch.mm.set_instance_transform(i % CHUNK, t.xf)
		ch.mm.set_instance_custom_data(i % CHUNK, Color(i % CHUNK, 0, 0, 0))
	for sc: Dictionary in screens + Level.data().get("minis", []):  # the picture, a hair in front of each screen (the theater's, and the CRTs over the aisles)
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sc.w, sc.h)
		quad.material = $"../Picture".material(true)  # (the picture menu's brightness and the rest)
		q.mesh = quad
		if sc.has("q"):
			q.basis = Basis(Quaternion(sc.q[0], sc.q[1], sc.q[2], sc.q[3]))
			q.position = Vector3(sc.p[0], sc.p[1], sc.p[2]) + q.basis.z * 0.006
		else:
			q.position = Vector3(sc.x, sc.y, sc.z) + Vector3(sin(sc.ry), 0, cos(sc.ry)) * 0.006
			q.rotation.y = sc.ry
		add_child(q)
		_quads.append(q)
	_screens_show(false)
	print("tapes: %d on the shelves in %d chunks" % [tapes.size(), _chunks.size()])
	_resume()
	_gen += 1
	_next_cover = 0
	for w in WORKERS:
		_cover_worker(_gen)


func _exit_tree() -> void:
	_gen += 1  # (the workers stop)
	for task: int in _shrinking:
		WorkerThreadPool.wait_for_task_completion(task)
	_shrinking.clear()


func _cover_worker(gen: int) -> void:  # covers onto the shelf, the next one not yet asked for, till they're all done
	var n := 0
	while gen == _gen and _next_cover < tapes.size():
		var t: Dictionary = tapes[_next_cover]
		_next_cover += 1
		var path: String = Library.cover_path(t.cover)
		var img: Image = null if FileAccess.file_exists(path) else await Library.cover(t.cover)  # (fetched if it isn't kept yet)
		var shelf := [img]
		var task := WorkerThreadPool.add_task(func() -> void:  # loading and shrinking it, off the main thread: 1600-odd of them would stall the first seconds
			var im: Image = shelf[0] if shelf[0] != null else Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if im != null:
				im.resize(COVER.x, COVER.y, Image.INTERPOLATE_LANCZOS)  # (720 tall down to the shelf's: Lanczos, so it stays sharp)
				im.convert(Image.FORMAT_RGB8)
				im.generate_mipmaps()
			shelf[0] = im)
		_shrinking[task] = true
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		_shrinking.erase(task)
		WorkerThreadPool.wait_for_task_completion(task)
		if gen != _gen:
			return
		if shelf[0] != null:
			_chunks[t.i / CHUNK].tex.update_layer(shelf[0], t.i % CHUNK)
		n += 1


# ---- nothing playing: the bouncing logo on the TV (VaultBuster's, from the web game's lounge.js)

const DVD_TINTS := ["#ffd400", "#4dd0e1", "#ff6b6b", "#8affc1", "#c792ea", "#ffab40", "#ffffff"]

var _saver := SubViewport.new()
var _logo := Panel.new()
var _dvd := { "v": Vector2(78, 61), "tint": 0 }
var _on_screens := false  # a tape's picture is up (else: the screensaver)


func _saver_build() -> void:
	_saver.size = Vector2i(320, 240)
	_saver.disable_3d = true
	_saver.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_saver)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(320, 240)
	_saver.add_child(black)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#00349c")
	box.border_color = Color("#ffd400")
	box.set_border_width_all(3)
	box.set_corner_radius_all(8)
	_logo.add_theme_stylebox_override("panel", box)
	_logo.size = Vector2(90, 90)
	_logo.position = Vector2(40, 30)
	var words := Label.new()
	words.text = "JELLY\nVAULT"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Arial", "sans-serif"])
	font.font_italic = true
	font.font_weight = 900
	words.add_theme_font_override("font", font)
	words.add_theme_font_size_override("font_size", 15)
	words.add_theme_constant_override("line_spacing", -4)
	words.add_theme_color_override("font_color", Color("#ffd400"))
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.set_anchors_preset(Control.PRESET_FULL_RECT)
	_logo.add_child(words)
	_saver.add_child(_logo)
	_logo.modulate = Color.WHITE.lerp(Color(DVD_TINTS[0]), 0.33)


func _saver_tick(dt: float) -> void:
	_saver.render_target_update_mode = SubViewport.UPDATE_DISABLED if _on_screens else SubViewport.UPDATE_ALWAYS
	if _on_screens:
		return
	var at: Vector2 = _logo.position + _dvd.v * dt
	var room := Vector2(_saver.size) - _logo.size
	var bounced := false
	for axis in 2:
		if at[axis] <= 0.0 or at[axis] >= room[axis]:
			at[axis] = clampf(at[axis], 0.0, room[axis])
			_dvd.v[axis] = absf(_dvd.v[axis]) * (1.0 if at[axis] <= 0.0 else -1.0)
			bounced = true
	_logo.position = at
	if bounced:  # recolours on each bounce, classic-screensaver style
		_dvd.tint = (_dvd.tint + 1) % DVD_TINTS.size()
		_logo.modulate = Color.WHITE.lerp(Color(DVD_TINTS[_dvd.tint]), 0.33)


func _screens_show(tape: bool) -> void:  # the tape's picture, or back to the bouncing logo
	_on_screens = tape
	for q in _quads:
		var m: ShaderMaterial = q.mesh.material
		m.set_shader_parameter("uTex", video.texture if tape else _saver.get_texture())
		m.set_shader_parameter("uFx", 1.0 if tape else 0.0)  # (the logo as it is)
		m.set_shader_parameter("uK", 0.85 if tape else 1.0)  # (the web game's -15%: blown-out whites were blinding)


func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


func _wire_box() -> ArrayMesh:  # the highlight: the tape's edges, in yellow
	var h := size / 2.0
	var pts := PackedVector3Array()
	for a in 3:
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var p := Vector3.ZERO
				p[(a + 1) % 3] = s1 * h[(a + 1) % 3]
				p[(a + 2) % 3] = s2 * h[(a + 2) % 3]
				p[a] = -h[a]
				pts.append(p)
				p[a] = h[a]
				pts.append(p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = YELLOW
	mesh.surface_set_material(0, m)
	return mesh


func set_on_shelf(t: Dictionary, on: bool) -> void:
	t.off = not on
	_chunks[t.i / CHUNK].mm.set_instance_transform(t.i % CHUNK, t.xf if on else Transform3D(Basis.from_scale(Vector3.ZERO), t.xf.origin))


# ---- in your hand

func pickup(t: Dictionary) -> void:  # off the shelf, held up to look at (whatever was in hand goes into the inventory)
	if not inv_make_room():
		hud.toast("Your hands are full: 9 is all you can carry")
		return
	set_on_shelf(t, false)
	_take(t)
	inspecting = true


func inv_make_room() -> bool:  # before picking something new up: stash what's in hand, or refuse at 9
	if inv.size() >= INV_MAX:
		return false
	inv_stash()
	return true


func inv_stash() -> void:  # what's in hand, out of it (still carried)
	held = null
	inspecting = false
	flipped = false
	peek = null  # swapping away from a tape counts as taking it
	_hand.visible = false
	inv_sel = -1


func inv_select(i: int) -> void:  # 1-9, or the wheel: that one into your hand (an empty slot: empty-handed)
	if i == inv_sel or i < 0 or i >= INV_MAX:
		return
	inv_stash()
	if i < inv.size():
		inv_sel = i
		show_tape(inv[i])


func _take(t: Dictionary) -> void:  # into your hand, and so into the inventory
	inv.append(t)
	inv_sel = inv.size() - 1
	show_tape(t)


func _gone() -> void:  # what was in hand has left it (shelved, into the VCR): the next one comes out
	var was := inv_sel
	if was >= 0:
		inv.remove_at(was)
	inv_sel = -1
	if not inv.is_empty():
		inv_select(mini(maxi(was, 0), inv.size() - 1))


func show_tape(t: Dictionary) -> void:  # the tape in your hand, its cover full size (from the cache, if it's come)
	held = t
	inspecting = false
	flipped = false
	var m: StandardMaterial3D = _hand_cover.material_override
	var path: String = Library.cover_path(t.cover)
	m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(path)) if FileAccess.file_exists(path) else null
	m.albedo_color = Color.WHITE if m.albedo_texture != null else Color(0.3, 0.3, 0.35)
	_hand.transform = HAND
	_hand.visible = true
	_show_back(t)


func _show_back(t: Dictionary) -> void:  # the back of the box, once it's drawn (asked as soon as it's in hand, so it's there when it's turned over)
	var m: StandardMaterial3D = _hand_back.material_override
	m.albedo_texture = null
	m.albedo_color = Color(0.12, 0.12, 0.14)
	var tex: Texture2D = await _backs.build(t)
	if held == t and tex != null:
		m.albedo_texture = tex
		m.albedo_color = Color.WHITE


func release() -> void:  # clears the hand without touching the shelf (into the VCR)
	held = null
	inspecting = false
	flipped = false
	peek = null
	_hand.visible = false
	_gone()


func wind_frac(t: Dictionary) -> float:  # how far through the whole tape it's wound, 0..1: episodes played + the part of the current one
	var n: int = t.e.size()
	var d: float = t.get("d", t.e[t.ep][3] if t.e[t.ep][3] > 0.0 else 1500.0)
	return minf(1.0, (t.ep + minf(1.0, t.at / d)) / n)


func put_back() -> void:  # back into its own shelf slot
	if held != null:
		set_on_shelf(held, true)
	release()


func _process(dt: float) -> void:
	_saver_tick(dt)
	if hovered != _dwell.on:
		_dwell = { "on": hovered, "t": 0.0 }
	elif hovered != null and _dwell.t < DWELL:
		_dwell.t += dt
		if _dwell.t >= DWELL:
			_backs.build(hovered)  # (not waited on: it's ready, or nearly, by the time it's picked up and turned over)
	if held != null:
		_hand.transform = _hand.transform.interpolate_with((LOOK_BACK if flipped else LOOK) if inspecting else HAND, minf(1.0, dt * 14.0))
	hud.inventory(inv.map(func(e: Dictionary) -> Dictionary: return { "name": e.t, "used": wind_frac(e) }), inv_sel)
	_scrub_tick(dt)
	hud.now_playing("%s%s\n%s%s%s   hold , . rewind/FF · [ ] episode" % ["❚❚ " if video.paused else "▶ ", playing.tape.t, "%d of %d · " % [playing.idx + 1, playing.tape.e.size()] if playing.tape.e.size() > 1 else "", _clock(video.position), " / " + _clock(video.duration) if video.duration > 0.0 else ""] if playing != null and not video.url.is_empty() else "")
	if playing != null and not video.url.is_empty():  # the tape winds forward as it plays
		playing.tape.ep = playing.idx
		playing.tape.at = video.position
		if video.duration > 0.0:
			playing.tape.d = video.duration
		_resume_t += dt
		if _resume_t >= RESUME_EVERY:
			_resume_t = 0.0
			_resume_save()


func _resume_save() -> void:  # (nothing in the machine: nothing to pick up next time)
	if playing == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESUME))
		return
	var cf := ConfigFile.new()
	cf.set_value("vcr", "id", playing.tape.e[playing.idx][2])
	cf.set_value("vcr", "at", video.position)
	cf.set_value("vcr", "speaker", video.audio.position)
	cf.set_value("vcr", "reach", video.audio.unit_size)
	cf.save(RESUME)


func _resume() -> void:  # what was in the VCR when the game last closed: off its shelf and back in, from where it was
	var cf := ConfigFile.new()
	if cf.load(RESUME) != OK:
		return
	var id: String = cf.get_value("vcr", "id", "")
	for t: Dictionary in tapes:
		for i in t.e.size():
			if t.e[i][2] == id:
				t.ep = i
				t.at = cf.get_value("vcr", "at", 0.0)
				set_on_shelf(t, false)
				video.audio.position = cf.get_value("vcr", "speaker", Vector3.ZERO)
				video.audio.unit_size = cf.get_value("vcr", "reach", 3.0)
				_speaker(video.audio.unit_size > 5.0)
				play_episode(i, t)
				print("tapes: %s back in the VCR, from %s" % [t.e[i][1], _clock(t.at)])
				return


func _scrub_tick(dt: float) -> void:  # rewind / fast-forward: held, the spot it'll pick up from runs back or on (faster the longer it's held), on the bar at the bottom; both let go, and a moment later it's there
	var rew := Input.is_physical_key_pressed(KEY_COMMA)
	var ff := Input.is_physical_key_pressed(KEY_PERIOD)
	if playing == null or video.url.is_empty() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		rew = false
		ff = false
		if playing == null:
			_scrub.to = -1.0
	if rew or ff:
		if _scrub.to < 0.0:
			_scrub.to = video.position
			_scrub.held = 0.0
		_scrub.held += dt
		_scrub.wait = SCRUB_WAIT
		_scrub.dir = (1.0 if ff else 0.0) - (1.0 if rew else 0.0)
		if _scrub.held > SCRUB_HOLD:  # (a tap does nothing: only held)
			var speed := minf(10.0 * pow(2.0, _scrub.held - SCRUB_HOLD), 300.0)  # seconds of tape a second: 10, doubling every second held, up to 5 minutes
			_scrub.to = clampf(_scrub.to + _scrub.dir * speed * dt, 0.0, video.duration if video.duration > 0.0 else INF)
	elif _scrub.to >= 0.0:
		_scrub.wait -= dt
		if _scrub.wait <= 0.0:
			if _scrub.held > SCRUB_HOLD:
				seek_to(_scrub.to)
			_scrub.to = -1.0
	var shown: bool = _scrub.to >= 0.0 and _scrub.held > SCRUB_HOLD
	hud.seek_bar(_scrub.to if shown else -1.0, video.duration, ("◀◀ " if _scrub.dir < 0.0 else "▶▶ ") + _clock(_scrub.to) + (" / " + _clock(video.duration) if video.duration > 0.0 else "") if shown else "")


func seek_to(to: float) -> void:  # wind it to there, where it sits in the machine
	if playing == null or video.url.is_empty():
		return
	to = maxf(0.0, to)
	if video.duration > 0.0 and to >= video.duration - 1.0:
		step_episode(1)  # off the end of this one
		return
	video.seek(to)
	playing.tape.at = to


func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and playing != null:  # the VCR's transport: [ and ] the one before and the next on the tape (, and . rewind and fast-forward, held: _scrub_tick)
		match e.physical_keycode:
			KEY_BRACKETLEFT:
				if playing.idx > 0:
					playing.tape.at = 0.0
					play_episode(playing.idx - 1)
			KEY_BRACKETRIGHT:
				step_episode(1)
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_R and held != null and player.seat == null:  # turn it over (held up first, if it was only carried)
		flipped = not flipped or not inspecting
		inspecting = true
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode >= KEY_1 and e.physical_keycode <= KEY_9:
		inv_select(e.physical_keycode - KEY_1)
		return
	if not e is InputEventMouseButton or not e.pressed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or player.fly:
		return
	if (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) and player.seat == null and inv.size() > 1:
		inv_select(posmod((inv_sel if inv_sel >= 0 else 0) + (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), inv.size()))  # (sat down, the wheel's the zoom)
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:  # right click puts down what's in hand, if it's only being looked at
		if held != null and held == peek:
			put_back()
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if held != null and inspecting:  # tuck the held-up tape back in hand (it's yours now)
			inspecting = false
			flipped = false
			peek = null
		elif aim_slot:  # slotted back into its own spot on the shelf
			put_back()
		elif hovered != null:  # another one: whatever's in hand goes into the inventory
			var t: Dictionary = hovered
			pickup(t)
			if held == t:
				peek = t
		elif held != null:  # hold it up to look at it
			inspecting = true


# ---- what the crosshair's on (interact.gd asks, after the doors and the rest); returns the tip, "" if it's nothing of ours

func clear_aim() -> void:
	hovered = null
	aim_slot = false
	aim_tv = null
	_box.visible = false


func aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	clear_aim()
	if held != null and inspecting:
		return "" if flipped else "%s\n%s\nClick — keep it · Right-click — put it back · R — turn it over" % [held.t, held.c]
	if held != null and held.off:  # its own empty slot: within 8 cm of the middle of it, nothing solid in front
		var at: Vector3 = held.xf.origin - from
		var t := at.dot(dir)
		aim_slot = t > 0.3 and t < REACH and (at - dir * t).length() < 0.08 and hit_d > t - 0.15
		if aim_slot:
			_show_box(held)
			return "Click — put %s back" % held.t
	if hit and hit_d < REACH:  # a tape: the cover the crosshair's on, of those near where it lands on the shelf
		var best := INF
		var c := _cell(hit.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for i: int in _grid.get(c + Vector3i(dx, dy, dz), []):
						var t: Dictionary = tapes[i]
						if t.off:
							continue
						var inv: Transform3D = t.xf.affine_inverse()
						var o := inv * from
						var d := inv.basis * dir
						if d.z >= 0.0:
							continue  # (from behind)
						var k := (size.z / 2.0 - o.z) / d.z  # where the ray meets the cover's plane
						var l := o + d * k
						if k > 0.0 and k < best and absf(l.x) < size.x / 2.0 and absf(l.y) < size.y / 2.0:
							best = k
							hovered = t
		if hovered != null:
			_show_box(hovered)
			return "%s\n%s" % [hovered.t, hovered.c]
	for sc: Dictionary in screens:  # the screen: you have to actually be looking at it
		var n := Vector3(sin(sc.ry), 0, cos(sc.ry))
		var facing := dir.dot(n)
		if facing > -0.01:
			continue
		var t: float = (Vector3(sc.x, sc.y, sc.z) - from).dot(n) / facing
		var on := from + dir * t - Vector3(sc.x, sc.y, sc.z)
		if t > 0.0 and t < sc.reach and t < hit_d + 0.2 and absf(on.dot(Vector3(cos(sc.ry), 0, -sin(sc.ry)))) < sc.w / 2.0 and absf(on.y) < sc.h / 2.0:
			aim_tv = sc
			if held != null:
				return "Press E to put “%s” on" % held.t
			return "Press E to eject the tape" if playing != null else "Take a tape off the shelves to play it here"
	return ""


func _show_box(t: Dictionary) -> void:
	_box.transform = t.xf
	_box.visible = true


# ---- the VCR

func vcr_use() -> void:  # E on the screen: the tape in hand goes in, and the one that was in comes out into your hand
	if held != null:
		var tape: Dictionary = held
		var old = playing.tape if playing != null else null
		video.audio.position = Vector3(aim_tv.x, aim_tv.y, aim_tv.z)
		_speaker(aim_tv.kind == "theater")
		play_episode(tape.ep, tape)  # it plays from wherever it's wound to
		release()
		if old != null:
			if inv_make_room():
				_take(old)
			else:
				set_on_shelf(old, true)
	elif playing != null:
		eject()


func play_episode(idx: int, tape: Dictionary = playing.tape if playing != null else {}) -> void:
	if tape.is_empty():
		return
	idx = clampi(idx, 0, tape.e.size() - 1)
	var at: float = tape.at if idx == tape.ep else 0.0
	if tape.has("d") and at > tape.d - 5.0:
		at = 0.0  # (wound right to the end: from the top)
	playing = { "tape": tape, "idx": idx }
	tape.ep = idx
	hud.toast("Loading: %s…" % tape.t)
	video.play_episode(tape.e[idx], at)
	_screens_show(true)


func _on_started() -> void:
	if playing == null:
		return
	hud.toast("Now Playing: %s" % playing.tape.e[playing.idx][1])


func step_episode(d: int) -> void:  # the next one on the tape, when one runs out
	if playing == null:
		return
	if playing.idx + d >= playing.tape.e.size():
		playing.tape.at = 0.0  # run out: it sits in the machine, at the end
		_screens_show(false)
		return
	playing.tape.at = 0.0
	play_episode(playing.idx + d)


func eject() -> void:
	var tape: Dictionary = playing.tape
	video.stop()
	playing = null
	_resume_save()
	_screens_show(false)
	if inv_make_room():
		_take(tape)  # the tape comes back out into your hand
	else:
		set_on_shelf(tape, true)  # hands full (9 already): it goes home
		hud.toast("%s went back on its shelf" % tape.t)


func _speaker(theater: bool) -> void:  # a TV: a speaker in the room, fading off; the theater: the whole auditorium, as loud from any seat (ambience.gd's Theater bus does the room)
	video.audio.unit_size = 8.0 if theater else 4.5  # (kept: the resume file tells them apart by it, over 5 the theater)
	video.audio.panning_strength = 0.0 if theater else 1.0  # (the film's own stereo, left and right, wherever you sit: not swung round to the screen's side)
	video.audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if theater else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	video.audio.attenuation_filter_db = 0.0 if theater else -24.0
	video.audio.bus = "Theater" if theater else "Master"
