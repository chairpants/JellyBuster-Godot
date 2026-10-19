extends Node
## Tapes: off the shelf into your hand, held up to look at, back into its slot; into the VCR and onto the TV.
## (From VaultBuster's tapes.gd, itself from the web game's store/tv.js.)
##
## Click a tape: it comes off the shelf, held up to look at. Click again: it's in your hand. Right-click while you're
## still looking: back it goes. Click its empty slot: back it goes. Click with one in hand: held up again.
## E at the TV: the tape in hand goes in and plays; E again: out it comes. E on the couch: sit (E again: up).
## Up to 9 carried; 1-9 or the wheel picks which is in hand. [ ] wind 30 s, , . the episode before / after.
##
## The shelves' tapes are drawn a chunk of CHUNK at a time (a MultiMesh each), their covers layers of a texture array,
## filled in as Jellyfin's covers arrive (cached in user://covers, see jellyfin.gd). Till then: the section's colour.

const REACH := 3.4
const INV_MAX := 9
const CELL := 0.25
const CHUNK := 1024  # tapes per draw call (and per texture array)
const COVER := Vector2i(64, 96)  # a cover on the shelf. ponytail: uncompressed RGB, ~24 MB a chunk; VRAM-compress them if a big library runs short
const WORKERS := 6  # covers fetching at once
const YELLOW := Color(1, 0.831, 0)
const SHADER := """
shader_type spatial;
uniform sampler2DArray covers : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 size;
varying vec2 face_uv;
varying float front;
varying float layer;
void vertex() {
	face_uv = vec2(VERTEX.x / size.x + 0.5, 0.5 - VERTEX.y / size.y);
	front = NORMAL.z;
	layer = INSTANCE_CUSTOM.r;
}
void fragment() {
	bool cover = front > 0.5;
	ALBEDO = cover ? texture(covers, vec3(face_uv, round(layer))).rgb : vec3(0.04);
	ROUGHNESS = cover ? 0.35 : 0.7;  // (the clamshell's sheen)
}
"""
var HAND := Transform3D(Basis.from_euler(Vector3(0.05, -0.4, 0.06)), Vector3(0.3, -0.28, -0.55))  # carried
var LOOK := Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.34))  # held up, cover to you

var size: Vector3 = preload("res://store.gd").TAPE
var tapes: Array = []
var screens: Array = []
var seats: Array = []
var hovered = null  # the tape the crosshair's on
var held = null
var inspecting := false  # held up in view (true) or carried (false)
var peek = null  # the tape you've only just picked up to look at: right-click still puts it back
var aim_slot := false
var aim_tv = null  # the screen the crosshair's on
var aim_seat = null
var playing = null  # { tape, idx }
var inv: Array = []  # the tapes you're carrying, the one in hand among them
var inv_sel := -1  # which of them is in hand (-1: empty-handed)

var _grid := {}  # cell -> [tape index]
var _chunks: Array = []  # { mm: MultiMesh, tex: Texture2DArray }
var _hand := Node3D.new()
var _hand_cover := MeshInstance3D.new()
var _box := MeshInstance3D.new()
var _quads: Array[MeshInstance3D] = []
var _stood_at := {}
var _next_cover := 0
var _gen := 0  # which stocking the cover workers are filling (a restock leaves the old ones to give up)

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var video: Node = $"../Video"
@onready var jellyfin: Node = $"../Jellyfin"


func _ready() -> void:
	_box.mesh = _wire_box()
	_box.visible = false
	add_child(_box)
	cam.add_child(_hand)
	var body := MeshInstance3D.new()  # the tape in hand: a black box, its cover on the front
	body.mesh = BoxMesh.new()
	body.mesh.size = size
	body.mesh.material = preload("res://store.gd")._mat(Color(0.04, 0.04, 0.04), 0.7)
	_hand.add_child(body)
	_hand_cover.mesh = QuadMesh.new()
	_hand_cover.mesh.size = Vector2(size.x, size.y)
	_hand_cover.position.z = size.z / 2.0 + 0.001
	_hand_cover.material_override = StandardMaterial3D.new()
	_hand.add_child(_hand_cover)
	_hand.visible = false
	_saver_build()
	video.started.connect(_on_started)
	video.ended.connect(func() -> void: step_episode(1))
	video.failed.connect(func(why: String) -> void: hud.toast("⚠ " + why))


func stock(store: Node) -> void:  # the store's tapes onto its shelves (store.gd has placed them), and the TV and couch
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
	screens = store.screens
	seats = store.seats
	var colours := {}  # a colour per section, till the covers come
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	mat.set_shader_parameter("size", size)
	for i in tapes.size():
		var t: Dictionary = tapes[i]
		t.merge({ "off": false, "ep": 0, "at": 0.0, "i": i })
		_grid.get_or_add(_cell(t.p), []).append(i)
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
		ch.mm.set_instance_transform(i % CHUNK, _xform(t))
		ch.mm.set_instance_custom_data(i % CHUNK, Color(i % CHUNK, 0, 0, 0))
	for sc: Dictionary in screens:  # the picture, a hair in front of each screen
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sc.w, sc.h)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = m
		q.mesh = quad
		q.position = Vector3(sc.x, sc.y, sc.z) + Vector3(sin(sc.ry), 0, cos(sc.ry)) * 0.006
		q.rotation.y = sc.ry
		add_child(q)
		_quads.append(q)
	_screens_show(false)
	print("tapes: %d on the shelves in %d chunks" % [tapes.size(), _chunks.size()])
	_gen += 1
	_next_cover = 0
	for w in WORKERS:
		_cover_worker(_gen)


func _cover_worker(gen: int) -> void:  # covers onto the shelf, the next one not yet asked for, till they're all done
	var n := 0
	while gen == _gen and _next_cover < tapes.size():
		var t: Dictionary = tapes[_next_cover]
		_next_cover += 1
		var img: Image = await jellyfin.cover(t.cover)
		if gen != _gen:
			return
		if img != null:
			img.resize(COVER.x, COVER.y, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGB8)
			img.generate_mipmaps()
			_chunks[t.i / CHUNK].tex.update_layer(img, t.i % CHUNK)
		n += 1
		if n % 16 == 0:
			await get_tree().process_frame  # (cached ones come back at once: a few a frame, not all of them in one)


func _xform(t: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, t.ry), t.p)


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
		var m: StandardMaterial3D = q.mesh.material
		m.albedo_texture = video.texture if tape else _saver.get_texture()
		m.albedo_color = Color(0.85, 0.85, 0.85) if tape else Color.WHITE  # (the web game's -15%: blown-out whites were blinding)


func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


func _local(t: Dictionary, world: Vector3) -> Vector3:  # in the tape's own frame: x across the cover, y up it, z out of it
	return Basis(Vector3.UP, -t.ry) * (world - t.p)


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
	_chunks[t.i / CHUNK].mm.set_instance_transform(t.i % CHUNK, _xform(t) if on else Transform3D(Basis.from_scale(Vector3.ZERO), t.p))


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
	var m: StandardMaterial3D = _hand_cover.material_override
	var path: String = jellyfin.cover_path(t.cover)
	m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(path)) if FileAccess.file_exists(path) else null
	m.albedo_color = Color.WHITE if m.albedo_texture != null else Color(0.3, 0.3, 0.35)
	_hand.transform = HAND
	_hand.visible = true


func release() -> void:  # clears the hand without touching the shelf (into the VCR)
	held = null
	inspecting = false
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
	if held != null:
		_hand.transform = _hand.transform.interpolate_with(LOOK if inspecting else HAND, minf(1.0, dt * 14.0))
	hud.inventory(inv.map(func(e: Dictionary) -> Dictionary: return { "name": e.t, "used": wind_frac(e) }), inv_sel)
	hud.now_playing("%s%s\n%s%s%s   [ ] wind · , . episode" % ["❚❚ " if video.paused else "▶ ", playing.tape.t, "%d of %d · " % [playing.idx + 1, playing.tape.e.size()] if playing.tape.e.size() > 1 else "", _clock(video.position), " / " + _clock(video.duration) if video.duration > 0.0 else ""] if playing != null and not video.url.is_empty() else "")
	if playing != null and not video.url.is_empty():  # the tape winds forward as it plays
		playing.tape.ep = playing.idx
		playing.tape.at = video.position
		if video.duration > 0.0:
			playing.tape.d = video.duration


func _physics_process(_dt: float) -> void:
	hud.tip(_aim())


func seek_by(d: float) -> void:  # wind it on, or back, where it sits in the machine
	if playing == null or video.url.is_empty():
		return
	var to := maxf(0.0, video.position + d)
	if video.duration > 0.0 and to >= video.duration - 1.0:
		step_episode(1)  # off the end of this one
		return
	video.seek(to)
	playing.tape.at = to


func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_E:
		on_e()
		return
	if e is InputEventKey and e.pressed and playing != null:  # the VCR's transport: [ and ] wind it back and on (held: keeps going), , and . the one before and the next on the tape
		match e.physical_keycode:
			KEY_BRACKETLEFT: seek_by(-30.0)
			KEY_BRACKETRIGHT: seek_by(30.0)
			KEY_COMMA:
				if not e.echo and playing.idx > 0:
					playing.tape.at = 0.0
					play_episode(playing.idx - 1)
			KEY_PERIOD:
				if not e.echo:
					step_episode(1)
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


func on_e() -> void:
	if player.seat != null:  # E always stands you up
		player.stand(_stood_at.at, _stood_at.yaw)
	elif aim_tv != null:
		vcr_use()
	elif aim_seat != null:
		_stood_at = { "at": player.global_position, "yaw": player.rotation.y }
		player.sit(aim_seat)


# ---- what the crosshair's on: returns the tip

func _aim() -> String:
	hovered = null
	aim_slot = false
	aim_tv = null
	aim_seat = null
	_box.visible = false
	if player.seat != null:
		return "E — stand up"
	if player.fly:
		return ""
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 6.0)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var hit_d: float = from.distance_to(hit.position) if hit else INF
	if held != null and inspecting:
		return "%s\n%s\nClick — keep it · Right-click — put it back" % [held.t, held.c]
	if held != null and held.off:  # its own empty slot: within 8 cm of the middle of it, nothing solid in front
		var at: Vector3 = held.p - from
		var t := at.dot(dir)
		aim_slot = t > 0.3 and t < REACH and (at - dir * t).length() < 0.08 and hit_d > t - 0.15
		if aim_slot:
			_show_box(held)
			return "Click — put %s back" % held.t
	if hit and hit_d < REACH:  # a tape: the one whose cover the crosshair lands on
		var best := INF
		var c := _cell(hit.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for i: int in _grid.get(c + Vector3i(dx, dy, dz), []):
						var t: Dictionary = tapes[i]
						var l := _local(t, hit.position)
						if not t.off and absf(l.x) < size.x / 2.0 + 0.012 and absf(l.y) < size.y / 2.0 + 0.01 and absf(l.z) < 0.05 and l.length() < best:
							best = l.length()
							hovered = t
		if hovered != null:
			_show_box(hovered)
			return "%s\n%s" % [hovered.t, hovered.c]
	for sc: Dictionary in screens:  # the TV: you have to actually be looking at it
		var n := Vector3(sin(sc.ry), 0, cos(sc.ry))
		var facing := dir.dot(n)
		if facing > -0.01:
			continue
		var t: float = (Vector3(sc.x, sc.y, sc.z) - from).dot(n) / facing
		var on := from + dir * t - Vector3(sc.x, sc.y, sc.z)
		if t > 0.0 and t < sc.reach and t < hit_d + 0.2 and absf(on.dot(Vector3(cos(sc.ry), 0, -sin(sc.ry)))) < sc.w / 2.0 and absf(on.y) < sc.h / 2.0:
			aim_tv = sc
			if held != null:
				return "E — put “%s” in" % held.t
			return "E — eject the tape" if playing != null else "Take a tape off the shelves to play it here"
	if hit and hit_d < 3.2:  # a seat: the nearest to where the crosshair lands
		var best := 0.8
		for s: Dictionary in seats:
			var off: float = hit.position.distance_to(Vector3(s.x, s.y + s.hipY, s.z))
			if off < best:
				best = off
				aim_seat = s
	if aim_seat != null:
		return "E — sit on the couch"
	return "Holding %s" % held.t if held != null else ""


func _show_box(t: Dictionary) -> void:
	_box.transform = _xform(t)
	_box.visible = true


# ---- the VCR

func vcr_use() -> void:  # E on the TV: the tape in hand goes in, and the one that was in comes out into your hand
	if held != null:
		var tape: Dictionary = held
		var old = playing.tape if playing != null else null
		video.audio.position = Vector3(aim_tv.x, aim_tv.y, aim_tv.z)
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
	_screens_show(false)
	if inv_make_room():
		_take(tape)  # the tape comes back out into your hand
	else:
		set_on_shelf(tape, true)  # hands full (9 already): it goes home
		hud.toast("%s went back on its shelf" % tape.t)
