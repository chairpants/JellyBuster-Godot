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
const SLEEVE_SHINE := 0.3  # (more, and the covers wash out grey seen from below)
const FOCUS_BLUR := 0.1  # how soft the store goes behind a tape held up
const GUIDE_C := Color(1.0, 0.75, 0.2)  # a tape asked for at the register: amber
const HOME_C := Color(0.35, 1.0, 0.55)  # the gap the tape in hand goes back in
const COVER := Vector2i(128, 192)  # a cover on the shelf. ponytail: uncompressed RGB, ~100 MB a chunk; VRAM-compress them if a big library runs short
const WORKERS := 6  # covers fetching at once
const YELLOW := Color(1, 0.831, 0)
const SCRUB_HOLD := 0.25  # rewind / fast-forward: held this long before it starts winding
const SCRUB_WAIT := 0.5  # and after both keys are let go, this long before it plays from there
const RESUME := "user://vcr.cfg"  # what's in the VCR, and how far in: kept as it plays, so the next start picks it up (_resume)
const RESUME_EVERY := 5.0
const TELL_EVERY := 30.0  # seconds between telling Jellyfin how far in (jellyfin.gd's report)
var _told_t := 0.0
var _copies := {}  # id -> the store's extra copies of it (their covers come with the original's: _cover_worker)
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
const THEATER_GROW := 6.2 / 5.7  # the theater's picture, past its screen by this much: its edges tuck in behind the proscenium's pillars, header and stage (the screen's 6.84 m, the opening 7.40 x 4.79: tools/remodel.gd)
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
var sub_lang := ""  # subtitles in this language when there are some (T; "": off). Kept (save.gd)
var audio_lang := ""  # the sound track in this language when there's one (Y; "": the film's own default). Kept
var _tracks := { "id": "", "audio": [], "subs": [], "sub": -1 }  # what's playing's sound and (text) subtitle tracks, from Jellyfin, and which subtitles are on

var _resume_t := 0.0
var _scrub := { "to": -1.0, "held": 0.0, "wait": 0.0, "dir": 1.0 }  # rewinding / fast-forwarding: to where (-1: not), how long the key's been held, the wait after it's let go
var _grid := {}  # cell -> [tape index]
var _chunks: Array = []  # { mm: MultiMesh, tex: Texture2DArray }
var _hand := Node3D.new()
var _hand_cover := MeshInstance3D.new()
var _hand_back := MeshInstance3D.new()
var _backs: Node = preload("res://backbox.gd").new()
var _covers: CanvasLayer = preload("res://covers.gd").new()  # I: a new cover from Jellyfin
var _dwell := { "on": null, "t": 0.0 }  # the tape the crosshair's settled on, and how long: past DWELL, its back starts drawing
const DWELL := 0.25
var _box := MeshInstance3D.new()
var _focus := CameraAttributesPractical.new()  # a tape held up to read: what's past it goes soft
var _home: MeshInstance3D  # where the tape in hand lives on the shelf: its gap, glowing, so it's easy to take back
var _home_t := 0.0
var _guide: MeshInstance3D  # a tape asked for at the register (pos.gd's SHOW ME): glowing on its shelf till it's picked up
var sought = null
var _quads: Array[MeshInstance3D] = []
var _next_cover := 0
var _gen := 0  # which stocking the cover workers are filling (a restock leaves the old ones to give up)
var _shrinking := {}  # covers being loaded and shrunk (WorkerThreadPool tasks): seen through before the game closes

var _looks := Vector3.ZERO  # paused, winding, cue: as the screens last had them
const REEL := 1200.0  # seconds to a reel, for the theater's cue dots
var in_theater := false  # the tape went in the theater's VCR (cinema.gd's curtains stay open for it)
@onready var cinema: Node = $"../Cinema"
@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var video: Node = $"../Video"


func _ready() -> void:
	_box.mesh = _wire_box()
	_box.visible = false
	add_child(_box)
	_home = _marker(size * 0.96, HOME_C, 0.7, 0.6)
	_guide = _marker(size * 1.1, GUIDE_C, 1.6, 1.2)  # (round the tape, not in its gap; a wider light: found from across the store)
	cam.add_child(_hand)
	_focus.dof_blur_far_enabled = true
	_focus.dof_blur_far_distance = 0.6
	_focus.dof_blur_far_transition = 1.2
	_focus.dof_blur_amount = 0.0
	cam.attributes = _focus
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
	get_parent().add_child.call_deferred(_covers)  # (beside us: it reaches back for recover(), and hears its keys before the player does)
	_hand.visible = false
	_saver_build()
	video.started.connect(_on_started)
	video.ended.connect(func() -> void:
		if cinema.busy:  # (an intro run out, not the tape)
			cinema.next()
			return
		if playing != null:
			Library.report(playing.tape.e[playing.idx][2], 0.0, true)  # (watched)
			Library.played[playing.tape.e[playing.idx][2]] = true
			if not playing.tape.get("seen", false) and playing.tape.e.all(func(ep: Array) -> bool: return Library.played.has(ep[2])):
				playing.tape.seen = true
				recover(playing.tape, false)  # (its sticker on, every copy's)
		step_episode(1))
	video.failed.connect(func(why: String) -> void:
		if cinema.busy:  # (an intro that wouldn't play: on to the next)
			cinema.next()
			return
		hud.toast("⚠ " + why))
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
	_copies.clear()
	for t: Dictionary in tapes:
		if t.has("copy"):
			_copies.get_or_add(t.id, []).append(t)
	screens = Level.data().screens.filter(func(sc: Dictionary) -> bool: return sc.kind in ["theater", "tv"])
	var colours := {}  # a colour per section, till the covers come
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = _shader()
	mat.set_shader_parameter("shine", SLEEVE_SHINE)  # (the sleeves: plastic)
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
			var images: Array[Image] = []  # a cover a title: a copy in the same chunk shares its original's (t.layer)
			var layers := {}  # id -> its layer
			for j in n:
				var u: Dictionary = tapes[i + j]
				u.layer = layers.get_or_add(u.id + ("~" if u.get("wrapped", false) else ""), layers.size())  # (one in brown paper: a layer of its own)
				if u.layer < images.size():
					continue
				if u.get("wrapped", false):
					images.append(_paper())
					continue
				var c: Color = colours.get_or_add(u.c, Color.from_hsv(colours.size() * 0.13, 0.45, 0.55))
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
		ch.mm.set_instance_custom_data(i % CHUNK, Color(t.layer, 0, 0, 0))
	for sc: Dictionary in screens + Level.data().get("minis", []):  # the picture, a hair in front of each screen (the theater's, and the CRTs over the aisles)
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sc.w, sc.h) * (THEATER_GROW if sc.get("kind") == "theater" else 1.0)
		quad.material = $"../Picture".material(true)  # (the picture menu's brightness and the rest)
		quad.material.set_shader_parameter("uLook", 2.0 if sc.get("kind") == "theater" else 1.0)  # (film in the theater; a tape on a TV everywhere else: picture.gd)
		q.mesh = quad
		if sc.has("q"):
			q.basis = Basis(Quaternion(sc.q[0], sc.q[1], sc.q[2], sc.q[3]))
			q.position = Vector3(sc.p[0], sc.p[1], sc.p[2]) + q.basis.z * 0.006
		else:
			q.position = Vector3(sc.x, sc.y, sc.z) + Vector3(sin(sc.ry), 0, cos(sc.ry)) * 0.006
			q.rotation.y = sc.ry
		add_child(q)
		_quads.append(q)
	_screens_show(video.card)  # (--film: the test card up, no tape needed)
	print("tapes: %d on the shelves in %d chunks, %d covers" % [tapes.size(), _chunks.size(), _chunks.reduce(func(a: int, ch: Dictionary) -> int: return a + ch.tex.get_layers(), 0)])
	_resume()
	_gen += 1
	_next_cover = 0
	for w in WORKERS:
		_cover_worker(_gen)
	_hang_posters(_gen)


const POSTER_GLOW := 0.35  # how bright a poster is with the store dark (on top of the room's light when it's on)
var _posters: Array[MeshInstance3D] = []  # the store's poster frames (VaultBuster's 23: its own posters weren't ours to keep)


func _hang_posters(gen: int) -> void:  # the library's own covers up on the walls: movies first, a series once, shuffled each opening
	if _posters.is_empty():
		var poster := RegEx.create_from_string("vaultbuster_(164|16[6-9]|17\\d|18[0-7])\\.")
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			var m := mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
			if m is ShaderMaterial and m.get_shader_parameter("tex") is Texture2D and poster.search(m.get_shader_parameter("tex").resource_path):
				_posters.append(mi)
		print("tapes: %d poster frames" % _posters.size())
	var picks: Array = []
	var seen := {}
	var pool := tapes.duplicate()
	pool.shuffle()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.kind == "movie" and b.kind != "movie")
	for t: Dictionary in pool:
		if picks.size() == _posters.size():
			break
		if not seen.has(t.cover[0]):
			seen[t.cover[0]] = true
			picks.append(t)
	for i in picks.size():
		var img: Image = await Library.cover(picks[i].cover)
		if gen != _gen:
			return
		if img == null:
			continue  # (the demo, or no picture: the frame stays as it was)
		img.flip_y()  # (the frames' UVs run bottom to top)
		img.generate_mipmaps()
		var m: ShaderMaterial = _posters[i].mesh.surface_get_material(0).duplicate()
		m.set_shader_parameter("tex", ImageTexture.create_from_image(img))
		m.set_shader_parameter("albedo", Color.WHITE)
		m.set_shader_parameter("emission_tex", m.get_shader_parameter("tex"))  # (lit by their marquee bulbs, not the store's switches: a glow of their own)
		m.set_shader_parameter("use_emission_tex", true)
		m.set_shader_parameter("emission", Vector3.ONE * POSTER_GLOW)
		_posters[i].set_surface_override_material(0, m)


func _exit_tree() -> void:
	_gen += 1  # (the workers stop)
	for p: String in _sharp_loading:
		WorkerThreadPool.wait_for_task_completion(_sharp_loading[p][0])
	for task: int in _shrinking:
		WorkerThreadPool.wait_for_task_completion(task)
	_shrinking.clear()


func _cover_worker(gen: int) -> void:  # covers onto the shelf, the next one not yet asked for, till they're all done
	var n := 0
	while gen == _gen and _next_cover < tapes.size():
		var t: Dictionary = tapes[_next_cover]
		_next_cover += 1
		if t.has("copy"):
			continue
		var path: String = Library.cover_path(t.cover)
		var img: Image = null if FileAccess.file_exists(path) else await Library.cover(t.cover)  # (fetched if it isn't kept yet)
		var shelf := [img]
		var task := WorkerThreadPool.add_task(func() -> void:  # loading and shrinking it, off the main thread: 1600-odd of them would stall the first seconds
			var im: Image = shelf[0] if shelf[0] != null else Image.load_from_file(path) if FileAccess.file_exists(path) else null
			if im != null:
				im.resize(COVER.x, COVER.y, Image.INTERPOLATE_LANCZOS)  # (720 tall down to the shelf's: Lanczos, so it stays sharp)
				_stickered(im, t)
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
			for c: Dictionary in [t] + _copies.get(t.id, []):
				if not c.get("wrapped", false):
					_chunks[c.i / CHUNK].tex.update_layer(shelf[0], c.layer)
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


func _screens_show(tape: bool, tex: Texture2D = null) -> void:  # the tape's picture (or another: cinema.gd's cards), or back to the bouncing logo
	_on_screens = tape
	for q in _quads:
		var m: ShaderMaterial = q.mesh.material
		m.set_shader_parameter("uTex", (tex if tex else video.texture) if tape else _saver.get_texture())
		m.set_shader_parameter("uFx", 1.0 if tape else 0.0)  # (the logo as it is)
		m.set_shader_parameter("uK", 0.85 if tape else 1.0)  # (the web game's -15%: blown-out whites were blinding)


func _looks_tick() -> void:  # what the screens' looks need to know (picture.gd): paused, winding, a cue dot before the reel runs out. Only when it changes
	var cue := 0.0
	var d: float = playing.tape.e[playing.idx][3] if playing != null and playing.tape.e[playing.idx].size() > 3 else 0.0
	if d > 0.0 and not video.paused:  # (a reel's twenty minutes: dots 8 s and 1 s before each change, four frames each, as a projectionist's cue marks)
		var left: float = REEL - fmod(video.position, REEL)
		if video.position + left < d - 30.0 and (absf(left - 8.0) < 0.085 or absf(left - 1.0) < 0.085):
			cue = 1.0
	var now := Vector3(1.0 if video.paused and playing != null else 0.0, _scrub.dir if _scrub.to >= 0.0 else 0.0, cue)
	if now == _looks:
		return
	_looks = now
	for q in _quads:
		var m: ShaderMaterial = q.mesh.material
		m.set_shader_parameter("uPaused", now.x)
		m.set_shader_parameter("uScrub", now.y)
		m.set_shader_parameter("uCue", now.z)


func named(t: Dictionary) -> String:  # what it's called, as far as you can tell: one in brown paper doesn't say
	return "A blind date, in brown paper" if t.get("wrapped", false) else t.t


static var _paper_img: Image
static func _paper() -> Image:  # a tape wrapped in brown paper and tied with string, a blank tag on it (the store's display: BLIND DATE)
	if _paper_img != null:
		return _paper_img
	var img := Image.create(COVER.x, COVER.y, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in COVER.y:
		for x in COVER.x:
			var g := 0.03 * sin(x * 0.9 + y * 0.13) + rng.randf_range(-0.035, 0.035)  # (the paper's grain, and a crease or two)
			img.set_pixel(x, y, Color(0.66 + g, 0.5 + g, 0.33 + g))
	var string := Color(0.9, 0.86, 0.76)
	img.fill_rect(Rect2i(COVER.x / 2 - 2, 0, 4, COVER.y), string)
	img.fill_rect(Rect2i(0, COVER.y * 2 / 5 - 2, COVER.x, 4), string)
	img.fill_rect(Rect2i(COVER.x / 2 + 6, COVER.y * 2 / 5 + 10, COVER.x / 3, COVER.y / 7), Color(0.95, 0.93, 0.86))  # the tag
	img.generate_mipmaps()
	_paper_img = img
	return img


func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


func _marker(box: Vector3, c: Color, reach: float, energy: float) -> MeshInstance3D:  # a glowing box on a shelf slot, pulsing (_process)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	mi.set_meta("c", c)
	var glow := OmniLight3D.new()  # (a little of it on the tapes either side: seen from down the aisle, not only head on)
	glow.light_color = c
	glow.omni_range = reach
	glow.light_energy = energy
	glow.position.z = size.z  # (out of the slot, in front of the shelf)
	mi.add_child(glow)
	add_child(mi)
	return mi


# ---- the covers right in front of you, sharp: the shelf's are 128 x 192 (all of them in memory at once); the nearest few
# get their 720-tall cover laid over them, loaded off the main thread, the last SHARP_KEEP kept

const SHARP := { "n": 24, "near": 1.6, "every": 0.25, "keep": 64 }
var _sharp: Array = []  # [quad, its tape or null]
var _sharp_tex := {}  # cover path -> ImageTexture (the most recent SHARP.keep)
var _sharp_loading := {}  # cover path -> task
var _sharp_t := 0.0


func _sharp_tick(dt: float) -> void:
	if _sharp.is_empty():
		if tapes.is_empty():
			return
		var look := StandardMaterial3D.new()  # (lit as the shelf is: the room's light, a sleeve's shine)
		look.albedo_texture = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGB8))
		var base: ShaderMaterial = $"../Room"._room_material(look, false)
		for i in SHARP.n:
			var q := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(size.x, size.y)
			q.mesh = quad
			var m: ShaderMaterial = base.duplicate()
			m.set_shader_parameter("shine", SLEEVE_SHINE)
			q.material_override = m
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.visible = false
			add_child(q)
			_sharp.append([q, null])
	for s: Array in _sharp:  # (one taken off the shelf: its cover goes with it, now)
		if s[1] != null and s[1].get("off", false):
			s[0].visible = false
			s[1] = null
	_sharp_t += dt
	if _sharp_t < SHARP.every:
		return
	_sharp_t = 0.0
	var eye := cam.global_position
	var near := []
	for t: Dictionary in tapes:
		var to: Vector3 = t.xf.origin - eye
		if not t.get("off", false) and not t.get("wrapped", false) and to.length_squared() < SHARP.near * SHARP.near and t.xf.basis.z.dot(to) < 0.0:
			near.append([to.length_squared(), t])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var want := near.slice(0, SHARP.n).map(func(p: Array) -> Dictionary: return p[1])
	var free := []
	for s: Array in _sharp:
		if s[1] == null or not s[1] in want:
			s[0].visible = false
			s[1] = null
			free.append(s)
	for t: Dictionary in want:
		if _sharp.any(func(s: Array) -> bool: return s[1] == t) or free.is_empty():
			continue
		var tex: ImageTexture = _sharp_cover(t)
		if tex == null:
			continue  # (loading, or none: the shelf's will do meanwhile)
		var s: Array = free.pop_back()
		s[1] = t
		s[0].transform = t.xf.translated_local(Vector3(0, 0, size.z / 2.0 + 0.0015))
		s[0].material_override.set_shader_parameter("tex", tex)
		s[0].visible = true


func _sharp_cover(t: Dictionary) -> ImageTexture:  # the 720 cover as a texture, or null till it's loaded (asked for in the background)
	var file: String = Library.cover_path(t.cover)
	var path := file + ("+seen" if t.get("seen", false) else "")  # (kept by how it looks)
	if _sharp_tex.has(path):
		var tex: ImageTexture = _sharp_tex[path]
		_sharp_tex.erase(path)
		_sharp_tex[path] = tex  # (most recent last)
		return tex
	if _sharp_loading.has(path):
		var task: int = _sharp_loading[path][0]
		if not WorkerThreadPool.is_task_completed(task):
			return null
		WorkerThreadPool.wait_for_task_completion(task)
		var img: Image = _sharp_loading[path][1][0]
		_sharp_loading.erase(path)
		if img == null:
			return null
		_sharp_tex[path] = ImageTexture.create_from_image(img)
		if _sharp_tex.size() > SHARP.keep:
			_sharp_tex.erase(_sharp_tex.keys()[0])
		return _sharp_tex[path]
	if FileAccess.file_exists(file) and _sharp_loading.size() < 4:
		var out := [null]
		var task := WorkerThreadPool.add_task(func() -> void:
			var img := Image.load_from_file(file)
			if img != null:
				_stickered(img, t)
				img.generate_mipmaps()
			out[0] = img)
		_sharp_loading[path] = [task, out]
	return null


func guide(t) -> void:  # light that tape's slot (null: stop)
	sought = t
	if t != null:
		hud.toast("%s: the %s shelf, lit up" % [t.t, t.c])


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


func recover(t: Dictionary, say := true) -> void:  # its cover's been changed on the server (covers.gd), or it's just been watched: fetched again, onto the shelf, and into your hand
	var img: Image = await Library.cover(t.cover)
	if img == null:
		return
	var im := img.duplicate()  # (as _cover_worker does it, here on the main thread: it's only the one)
	im.resize(COVER.x, COVER.y, Image.INTERPOLATE_LANCZOS)
	_stickered(im, t)
	im.convert(Image.FORMAT_RGB8)
	im.generate_mipmaps()
	for c: Dictionary in tapes.filter(func(x: Dictionary) -> bool: return x.id == t.id and not x.get("wrapped", false)):  # (it, and its copies; not one in brown paper)
		c.seen = t.get("seen", false)
		if held == c:
			var m: StandardMaterial3D = _hand_cover.material_override
			m.albedo_texture = _mipped(_stickered(img.duplicate(), c))
			m.albedo_color = Color.WHITE
		_chunks[c.i / CHUNK].tex.update_layer(im, c.layer)
	if say:
		hud.toast("New cover: %s" % t.t)


static var _sticker: Image = (load("res://world/sticker_seen.png") as Texture2D).get_image()  # a rental store's round sticker: SEEN IT


static func _stickered(img: Image, t: Dictionary) -> Image:  # watched: the sticker on, low on the cover's right (as a store's staff put them on)
	if not t.get("seen", false):
		return img
	var w := img.get_width() / 4
	var s := _sticker.duplicate()
	s.resize(w, w, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	img.blend_rect(s, Rect2i(0, 0, w, w), Vector2i(img.get_width() - w - w / 6, img.get_height() - w - w / 4))
	img.convert(Image.FORMAT_RGB8)
	return img


static func _mipped(img: Image) -> ImageTexture:  # (the cover in hand: carried, it's small and far off; held up, near and big. Without its smaller copies, small it shimmers)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func show_tape(t: Dictionary) -> void:  # the tape in your hand, its cover full size (from the cache, if it's come)
	held = t
	inspecting = false
	flipped = false
	var m: StandardMaterial3D = _hand_cover.material_override
	var path: String = Library.cover_path(t.cover)
	m.albedo_texture = _mipped(_paper()) if t.get("wrapped", false) else _mipped(_stickered(Image.load_from_file(path), t)) if FileAccess.file_exists(path) else null
	m.albedo_color = Color.WHITE if m.albedo_texture != null else Color(0.3, 0.3, 0.35)
	_hand.transform = HAND
	_hand.visible = true
	_show_back(t)


func _show_back(t: Dictionary) -> void:  # the back of the box, once it's drawn (asked as soon as it's in hand, so it's there when it's turned over)
	var m: StandardMaterial3D = _hand_back.material_override
	m.albedo_texture = null
	m.albedo_color = Color(0.12, 0.12, 0.14)
	if t.get("wrapped", false):  # (no peeking)
		m.albedo_texture = _mipped(_paper())
		m.albedo_color = Color.WHITE
		return
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
	_looks_tick()
	_sharp_tick(dt)
	_focus.dof_blur_amount = move_toward(_focus.dof_blur_amount, FOCUS_BLUR if held != null and inspecting else 0.0, dt * FOCUS_BLUR * 4.0)
	_focus.dof_blur_far_enabled = _focus.dof_blur_amount > 0.0
	_home_t += dt
	var k := 0.5 + 0.5 * sin(_home_t * TAU * 0.8)  # (a slow pulse)
	if sought != null and (sought.get("off", false) or sought == held):
		sought = null  # (found: taken off the shelf)
	for pair: Array in [[_home, held], [_guide, sought]]:
		var mi: MeshInstance3D = pair[0]
		mi.visible = pair[1] != null
		if mi.visible:
			mi.transform = pair[1].xf
			(mi.mesh.material as StandardMaterial3D).albedo_color = Color(mi.get_meta("c") * (1.2 + 1.3 * k), 0.35 + 0.35 * k)  # (past white at the top: it blooms)
	if hovered != _dwell.on:
		_dwell = { "on": hovered, "t": 0.0 }
	elif hovered != null and _dwell.t < DWELL:
		_dwell.t += dt
		if _dwell.t >= DWELL:
			_backs.build(hovered)  # (not waited on: it's ready, or nearly, by the time it's picked up and turned over)
	if held != null:
		_hand.transform = _hand.transform.interpolate_with((LOOK_BACK if flipped else LOOK) if inspecting else HAND, minf(1.0, dt * 14.0))
	hud.inventory(inv.map(func(e: Dictionary) -> Dictionary: return { "name": named(e), "used": wind_frac(e) }), inv_sel)
	_scrub_tick(dt)
	var heard: bool = hud.is_full_screen() or $"../Ambience".film_clear  # (close enough to the screen to hear it plainly: else it's someone else's film)
	hud.caption(video.caption() if playing != null and not video.url.is_empty() and heard else "")
	hud.now_playing("%s%s\n%s%s%s   / pause · hold , . rewind/FF · [ ] episode" % ["❚❚ " if video.paused else "▶ ", playing.tape.t, "%d of %d · " % [playing.idx + 1, playing.tape.e.size()] if playing.tape.e.size() > 1 else "", _clock(video.position), " / " + _clock(video.duration) if video.duration > 0.0 else ""] if playing != null and not video.url.is_empty() else "")
	if playing != null and not video.url.is_empty():  # the tape winds forward as it plays
		playing.tape.ep = playing.idx
		playing.tape.at = video.position
		if video.duration > 0.0:
			playing.tape.d = video.duration
		_resume_t += dt
		if _resume_t >= RESUME_EVERY:
			_resume_t = 0.0
			_resume_save()
			_told_t += RESUME_EVERY
			if _told_t >= TELL_EVERY and not video.paused:
				_told_t = 0.0
				Library.report(playing.tape.e[playing.idx][2], video.position)


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
	var args := OS.get_cmdline_user_args()
	if "--shot" in args or "--snapshot" in args:  # (the same views every time, the VCR left as it was: as save.gd does)
		return
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
				video.audio.unit_size = cf.get_value("vcr", "reach", 4.8)
				_speaker(video.audio.unit_size > 5.0)
				play_episode(i, t)
				print("tapes: %s back in the VCR, from %s" % [t.e[i][1], _clock(t.at)])
				return


func _scrub_tick(dt: float) -> void:  # rewind / fast-forward: held, the spot it'll pick up from runs back or on (faster the longer it's held), on the bar at the bottom; both let go, and a moment later it's there
	var typing: bool = $"../POS".open  # (, and . typed at the register aren't the VCR's)
	var rew := Input.is_physical_key_pressed(KEY_COMMA) and not typing
	var ff := Input.is_physical_key_pressed(KEY_PERIOD) and not typing
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


var _pressed: Array = ["", 0]  # the last button, and when


func transport(what: String, s := 0.0) -> void:  # the VCR's buttons, however they're pressed: its keys, the media keys, the desktop's player controls (mpris.gd). stop only pauses: the tape stays in
	if playing == null:
		return
	var key: String = "play" if what in ["playpause", "play", "pause"] else what  # (one press of a media key can come twice, to the window and through Windows' controls: the second's dropped)
	if what not in ["pos", "seek"] and key == _pressed[0] and Time.get_ticks_msec() - _pressed[1] < 250:
		return
	_pressed = [key, Time.get_ticks_msec()]
	match what:
		"playpause", "play", "pause", "stop":
			if not video.url.is_empty():
				video.pause(not video.paused if what == "playpause" else what != "play")
		"prev":
			if playing.idx > 0:
				playing.tape.at = 0.0
				play_episode(playing.idx - 1)
		"next":
			step_episode(1)
		"seek":
			seek_to(video.position + s)
		"pos":
			seek_to(s)


func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and playing != null:  # the VCR's transport: [ and ] the one before and the next on the tape, / pause (, and . rewind and fast-forward, held: _scrub_tick); the keyboard's media keys, when the desktop lets them through (mostly it hands them to mpris.gd instead)
		match e.keycode:
			KEY_MEDIAPLAY:
				transport("playpause")
			KEY_MEDIASTOP:
				transport("stop")
			KEY_MEDIAPREVIOUS:
				transport("prev")
			KEY_MEDIANEXT:
				transport("next")
		match e.physical_keycode:
			KEY_SLASH:
				transport("playpause")
			KEY_BRACKETLEFT:
				transport("prev")
			KEY_BRACKETRIGHT:
				transport("next")
			KEY_T:
				_subs_next()
			KEY_Y:
				_audio_next()
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_I and held != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:  # a new cover for it, from Jellyfin's providers
		if Library.demo or Library.url.is_empty():
			hud.toast("The demo library has no covers to change")
		else:
			_covers.open(held)
		return
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
		return "" if flipped else "%s\n%s\nClick — keep it · Right-click — put it back · R — turn it over" % [named(held), "?" if held.get("wrapped", false) else held.c]
	if held != null and held.off:  # its own empty slot: within 8 cm of the middle of it, nothing solid in front
		var at: Vector3 = held.xf.origin - from
		var t := at.dot(dir)
		aim_slot = t > 0.3 and t < REACH and (at - dir * t).length() < 0.08 and hit_d > t - 0.15
		if aim_slot:
			_show_box(held)
			return "Click — put %s back" % named(held)
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
			return "%s\n%s" % [named(hovered), "?" if hovered.get("wrapped", false) else hovered.c]
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
				return "Press E to put “%s” on" % named(held)
			return "Press E to eject the tape" if playing != null else "Take a tape off the shelves to play it here"
	return ""


func _show_box(t: Dictionary) -> void:
	_box.transform = t.xf
	_box.visible = true


# ---- the VCR

func vcr_use() -> void:  # E on the screen: the tape in hand goes in, and the one that was in comes out into your hand. In the theater, a film from the top gets the works first (cinema.gd); E again skips them
	if cinema.busy:
		cinema.skip()
		return
	if held != null:
		var tape: Dictionary = held
		var old = playing.tape if playing != null else null
		video.audio.position = Vector3(aim_tv.x, aim_tv.y, aim_tv.z)
		_speaker(aim_tv.kind == "theater")
		if aim_tv.kind == "theater" and cinema.wants(tape):
			cinema.begin(tape)
		else:
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
	if Library.offline:
		hud.toast("⚠ Offline: Jellyfin's out of reach, so no film till it's back (F2)")
		return
	idx = clampi(idx, 0, tape.e.size() - 1)
	var at: float = tape.at if idx == tape.ep else 0.0
	if at == 0.0:  # (never played here: where Jellyfin has them up to, from any app)
		var ep: Array = tape.e[idx]
		at = await Library.resume_at(ep[2])
		if ep.size() > 3 and at > ep[3] - 60.0:
			at = 0.0
	if tape.has("d") and at > tape.d - 5.0:
		at = 0.0  # (wound right to the end: from the top)
	playing = { "tape": tape, "idx": idx }
	tape.ep = idx
	hud.toast("Loading: %s…" % tape.t)
	var id: String = tape.e[idx][2]
	var all: Array = await Library.streams(id)
	_tracks = { "id": id, "audio": all.filter(func(m: Dictionary) -> bool: return m.Type == "Audio" and not m.get("IsExternal", false)),
		"subs": all.filter(func(m: Dictionary) -> bool: return m.Type == "Subtitle" and m.get("IsTextSubtitleStream", false)), "sub": -1 }
	video.audio_track = _tracks.audio.map(func(m: Dictionary) -> String: return m.get("Language", "")).find(audio_lang) if audio_lang != "" else -1
	video.cues = []
	video.play_episode(tape.e[idx], at)
	_screens_show(true)
	if sub_lang != "":
		_subs_on(_tracks.subs.map(func(m: Dictionary) -> String: return m.get("Language", "")).find(sub_lang), false)


func _subs_on(i: int, say := true) -> void:  # that subtitle track on (-1: off)
	_tracks.sub = i
	video.cues = []
	if i < 0:
		if say:
			hud.toast("Subtitles off (T)")
		return
	var id: String = _tracks.id
	var m: Dictionary = _tracks.subs[i]
	if say:
		hud.toast("Subtitles: %s… (T)" % m.get("DisplayTitle", "?"))
	var cues: Array = await Library.subtitles(id, m.Index)
	if _tracks.id != id or _tracks.sub != i:
		return  # (something else on by the time they came)
	video.cues = cues
	if cues.is_empty() and say:
		hud.toast("⚠ Jellyfin couldn't give those subtitles")


func _subs_next() -> void:  # T: the next subtitle track, then off
	if _tracks.subs.is_empty():
		hud.toast("No subtitles on this one")
		return
	var i: int = _tracks.sub + 1 if _tracks.sub + 1 < _tracks.subs.size() else -1
	sub_lang = _tracks.subs[i].get("Language", "") if i >= 0 else ""
	_subs_on(i)


func _audio_next() -> void:  # Y: the next sound track (from where it's got to)
	var n: int = _tracks.audio.size()
	if n < 2:
		hud.toast("Only the one sound track on this one")
		return
	video.audio_track = (maxi(video.audio_track, 0) + 1) % n
	var m: Dictionary = _tracks.audio[video.audio_track]
	audio_lang = m.get("Language", "")
	hud.toast("Sound: %s (%d of %d · Y)" % [m.get("DisplayTitle", "?"), video.audio_track + 1, n])
	video.seek(video.position)


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
	Library.report(tape.e[playing.idx][2], video.position)  # (where it's got to, for any other Jellyfin app)
	video.stop()
	playing = null
	_resume_save()
	_screens_show(false)
	if inv_make_room():
		_take(tape)  # the tape comes back out into your hand
	else:
		set_on_shelf(tape, true)  # hands full (9 already): it goes home
		hud.toast("%s went back on its shelf" % tape.t)


func _speaker(theater: bool) -> void:  # as VaultBusterGodot plays it: from the screen, the theater's speakers louder and further
	in_theater = theater
	video.audio.unit_size = 8.0 if theater else 4.8  # (a TV heard clear across its aisle. Kept: the resume file tells them apart by it, over 5 the theater)
