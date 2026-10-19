extends Node
## Tapes: off the shelf into your hand, held up to look at, back into its slot; into the VCR and onto the screens.
## From the web game: store/tv.js (pickup, showTape, putBack, vcrUse, playEpisode, eject), store/checkout.js (what the
## crosshair's on: a tape's cover within 3.4 m, your own tape's empty slot within 8 cm of its middle; what a click
## does), store/shelves.js (setOnShelf), store/main.js (the words of the tips). Every copy's slot and episodes come
## from the web game too, in data/tapes.json (tests/export-glb.mjs --data).
##
## Click a tape: it comes off the shelf, held up to look at. Click again: it's in your hand. Right-click while you're
## still looking: back it goes. Click its empty slot: back it goes. Click with one in hand: held up again.
## E at the TV (within 4.5 m) or the theater's screen (9 m): in it goes, and plays on every screen (those two, and
## the monitors hung over the aisles); E again: out it comes.
##
## Different here:
## - The shelves are whole meshes, as in the web game, and a tape leaves one the same way (its corners pulled out of
##   sight); but which corners are a tape's is found by where they are, not by counting, since the level's meshes
##   aren't in the web game's order. The tape in your hand is those same triangles, lifted out: its own cover.
## - The inventory (the web game's, store/chores.js: up to 9 carried, one of them in hand; 1-9 or the wheel swap which)
##   holds tapes only so far, and its slots are a line of names, not pictures.
## - A tape goes on from where it was wound to, to the second (the web game can't seek, so it restarts the episode).
## - The rewinder's the web game's (E puts the tape in hand in; up to ten seconds; E takes it out), without its
##   tape showing in it, its light or its whir. Shelve one unrewound and it snaps back, with a word about it.
## - No case on the coffee table, no picture settings; the tapes in the Returns bin aren't drawn (the tip counts them).

const REACH := 3.4
const INV_MAX := 9
const CELL := 0.25
const YELLOW := Color(1, 0.831, 0)
var HAND := Transform3D(Basis.from_euler(Vector3(0.05, -0.4, 0.06)), Vector3(0.3, -0.28, -0.55))  # carried
var LOOK := Transform3D(Basis.from_euler(Vector3(0, PI / 2, 0)), Vector3(0, 0, -0.34))  # held up, cover to you

var size := Vector3(0.032, 0.192, 0.105)  # TAPE: thick, tall, wide
var tapes: Array = []
var screens: Array = []
var hovered = null  # the tape the crosshair's on
var held = null
var inspecting := false  # held up in view (true) or carried (false)
var peek = null  # the tape you've only just picked up to look at: right-click still puts it back
var aim_slot := false
var aim_tv = null  # the screen the crosshair's on
var playing = null  # { tape, idx }
var inv: Array = []  # the tapes you're carrying, the one in hand among them
var return_bin: Array = []  # tapes customers have dropped back, waiting to be put away
var aim_returns := false
var rewinder := {}  # the counter's rewinder: { at, tape, f0, t, dur, done }
var rewinders: Array = []  # (just the one: VaultBuster's second was an upgrade)
var _rw_aim := {}  # the one the crosshair's on
var aim_rewinder := false
var _returns_at := Vector3.ZERO
var _peek_bin := false  # the tape you're looking at came out of the bin: right-click puts it back there
var inv_sel := -1  # which of them is in hand (-1: empty-handed)
var batch := false  # many tapes on or off the shelf at once (a store picked up again): the meshes rebuilt once, at commit()
var _dirty := {}

var _grid := {}  # cell -> [tape index]
var _verts := {}  # cell -> PackedInt32Array of (mesh, surface, vertex) triples: the level's corners near any slot
var _meshes: Array[MeshInstance3D] = []
var _arrays: Array = []  # per mesh: its surfaces' arrays
var _mats: Array = []
var _hand := Node3D.new()
var _hand_mesh := MeshInstance3D.new()
var _box := MeshInstance3D.new()
var _quads: Array[MeshInstance3D] = []

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var video: Node = $"../Video"


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tapes.json"))
	size = Vector3(data.size.w, data.size.h, data.size.d)
	tapes = data.tapes
	screens = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).get("screens", [])
	var rb: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.returns.bin
	_returns_at = Vector3(rb[0], rb[1], rb[2])
	var rw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.rewinders
	if not rw.is_empty():
		for at: Array in rw.slice(0, 1):
			rewinders.append({ "at": Vector3(at[0], at[1], at[2]), "tape": null, "f0": 0.0, "t": 0.0, "dur": 1.0, "done": false })
		rewinder = rewinders[0]
	var near := {}  # every cell a slot reaches into
	var region := AABB(_pos(tapes[0]), Vector3.ZERO)
	for i in tapes.size():
		var t: Dictionary = tapes[i]
		t.merge({ "off": false, "ep": 0, "at": 0.0 })
		var p := _pos(t)
		region = region.expand(p)
		_grid.get_or_add(_cell(p), []).append(i)
		for dx in [-0.08, 0.08]:
			for dy in [-0.11, 0.11]:
				for dz in [-0.08, 0.08]:
					near[_cell(p + Vector3(dx, dy, dz))] = true
	region = region.grow(0.3)
	var kept := 0
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not region.intersects(mi.global_transform * mi.get_aabb()):
			continue
		var surfaces := []
		var mats := []
		var any := false
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			surfaces.append(arrays)
			mats.append(mi.mesh.surface_get_material(s))
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vs.size():
				var c := _cell(mi.global_transform * vs[v])
				if near.has(c):
					_verts.get_or_add(c, PackedInt32Array()).append_array([_meshes.size(), s, v])
					any = true
					kept += 1
		if any:
			_meshes.append(mi)
			_arrays.append(surfaces)
			_mats.append(mats)
	print("tapes: %d on the shelves, %d corners of %d meshes by their slots" % [tapes.size(), kept, _meshes.size()])
	_box.mesh = _wire_box()
	_box.visible = false
	add_child(_box)
	cam.add_child(_hand)
	_hand.add_child(_hand_mesh)
	_hand.visible = false
	var every: Array = screens.duplicate()
	every.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).get("minis", []))  # ...and the monitors hung over the aisles
	for sc: Dictionary in every:  # the picture, a hair in front of each screen: there while a tape's playing
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sc.w, sc.h)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = video.texture
		m.albedo_color = Color(0.85, 0.85, 0.85)  # (the web game's -15%: blown-out whites were blinding)
		quad.material = m
		q.mesh = quad
		if sc.has("q"):
			q.basis = Basis(Quaternion(sc.q[0], sc.q[1], sc.q[2], sc.q[3]))
			q.position = Vector3(sc.p[0], sc.p[1], sc.p[2]) + q.basis.z * 0.006
		else:
			q.position = Vector3(sc.x, sc.y, sc.z) + Vector3(sin(sc.ry), 0, cos(sc.ry)) * 0.006
			q.rotation.y = sc.ry
		q.visible = false
		add_child(q)
		_quads.append(q)
	_saver_build()
	video.started.connect(_on_started)
	video.ended.connect(func() -> void: step_episode(1))
	video.failed.connect(func(why: String) -> void: hud.toast("⚠ " + why))


# ---- nothing playing: the bouncing logo, on every screen (lounge.js: dvdLogoTex, DVD_TINTS, updateScreensaver).
# One little picture, drawn once a frame, shared by them all

const DVD_TINTS := ["#ffd400", "#4dd0e1", "#ff6b6b", "#8affc1", "#c792ea", "#ffab40", "#ffffff"]

var _saver := SubViewport.new()
var _logo := Panel.new()
var _dvd := { "v": Vector2(78, 61), "tint": 0 }


func _saver_build() -> void:
	_saver.size = Vector2i(320, 240)
	_saver.disable_3d = true
	_saver.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_saver)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(320, 240)
	_saver.add_child(black)
	var box := StyleBoxFlat.new()  # the square brand mark
	box.bg_color = Color("#00349c")
	box.border_color = Color("#ffd400")
	box.set_border_width_all(3)
	box.set_corner_radius_all(8)
	_logo.add_theme_stylebox_override("panel", box)
	_logo.size = Vector2(90, 90)
	_logo.position = Vector2(40, 30)
	var words := Label.new()
	words.text = "VAULT\nBUSTER"
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
	_screens_show(false)


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


var _on_screens := false  # a tape's picture is up (else: the screensaver)


func _screens_show(tape: bool) -> void:  # every screen: the tape's picture, or back to the bouncing logo
	_on_screens = tape
	for q in _quads:
		q.visible = true
		var m: StandardMaterial3D = q.mesh.material
		m.albedo_texture = video.texture if tape else _saver.get_texture()
		m.albedo_color = Color(0.85, 0.85, 0.85) if tape else Color.WHITE


func _pos(t: Dictionary) -> Vector3:
	return Vector3(t.p[0], t.p[1], t.p[2])


func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


func _local(t: Dictionary, world: Vector3) -> Vector3:  # in the tape's own frame: x through it, y up it, z across it
	return Basis(Vector3.UP, -t.ry) * (world - _pos(t))


func _wire_box() -> ArrayMesh:  # the highlight: the tape's edges, in yellow (turned per tape to match its shelf)
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


# ---- a tape's corners in the shelves' meshes

func _corners(t: Dictionary) -> Array:  # [[mesh, surface, vertex], ...], found once
	if t.has("v"):
		return t.v
	var out := []
	var seen := {}
	var p := _pos(t)
	for dx in [-0.08, 0.08]:
		for dy in [-0.11, 0.11]:
			for dz in [-0.08, 0.08]:
				var c := _cell(p + Vector3(dx, dy, dz))
				if seen.has(c) or not _verts.has(c):
					continue
				seen[c] = true
				var list: PackedInt32Array = _verts[c]
				for k in range(0, list.size(), 3):
					var vs: PackedVector3Array = _arrays[list[k]][list[k + 1]][Mesh.ARRAY_VERTEX]
					var l := _local(t, _meshes[list[k]].global_transform * vs[list[k + 2]])
					# (deeper than the tape behind it: they tip back 10 degrees against the backing board, so the top's 3 cm further in)
					if l.x > -size.x / 2.0 - 0.045 and l.x < size.x / 2.0 + 0.012 and absf(l.y) < size.y / 2.0 + 0.012 and absf(l.z) < size.z / 2.0 + 0.008:
						out.append([list[k], list[k + 1], list[k + 2]])
	t.v = out
	return out


func set_on_shelf(t: Dictionary, on: bool) -> void:  # show / hide one copy in the shelves' meshes (setOnShelf)
	if t.off == not on:
		return
	var corners := _corners(t)
	if not on and not t.has("mesh"):
		t.mesh = _lift(t, corners)
	var touched := {}
	if not on:
		t.saved = []
	for i in corners.size():
		var c: Array = corners[i]
		var vs: PackedVector3Array = _arrays[c[0]][c[1]][Mesh.ARRAY_VERTEX]
		if on:
			vs[c[2]] = t.saved[i]
		else:
			t.saved.append(vs[c[2]])
			vs[c[2]] = _meshes[c[0]].global_transform.affine_inverse() * Vector3(0, -10, 0)  # collapsed, under the floor
		_arrays[c[0]][c[1]][Mesh.ARRAY_VERTEX] = vs
		touched[c[0]] = true
	t.off = not on
	_dirty.merge(touched)
	if not batch:
		commit()


func commit() -> void:  # the shelves' meshes, rebuilt with what's been taken out of them (or put back)
	for m: int in _dirty:
		var mesh := ArrayMesh.new()
		for s in _arrays[m].size():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays[m][s])
			mesh.surface_set_material(s, _mats[m][s])
		_meshes[m].mesh = mesh
	_dirty.clear()


func _lift(t: Dictionary, corners: Array) -> ArrayMesh:  # the tape's own triangles, out of the shelves' meshes, about its middle
	var mesh := ArrayMesh.new()
	var by := {}  # [mesh, surface] -> { vertex: true }
	for c: Array in corners:
		by.get_or_add([c[0], c[1]], {})[c[2]] = true
	var cover_x := 0.0  # the foot of the cover: which face of the tape it's on
	var lean := 0.0
	for key: Array in by:
		var mine: Dictionary = by[key]
		var src: Array = _arrays[key[0]][key[1]]
		var xf := _meshes[key[0]].global_transform
		var rot := Basis(Vector3.UP, -t.ry) * xf.basis.orthonormalized()
		var index := {}
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var has_n: bool = src[Mesh.ARRAY_NORMAL] != null
		var has_uv: bool = src[Mesh.ARRAY_TEX_UV] != null
		var has_c: bool = src[Mesh.ARRAY_COLOR] != null
		for v: int in mine:
			index[v] = vs.size()
			vs.append(_local(t, xf * sv[v]))
			if has_n:
				ns.append(rot * src[Mesh.ARRAY_NORMAL][v])
			if has_uv:
				uvs.append(src[Mesh.ARRAY_TEX_UV][v])
			if has_c:
				cols.append(src[Mesh.ARRAY_COLOR][v])
		var tris := PackedInt32Array()
		if src[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				if mine.has(idx[k]) and mine.has(idx[k + 1]) and mine.has(idx[k + 2]):
					tris.append_array([index[idx[k]], index[idx[k + 1]], index[idx[k + 2]]])
		else:
			for k in range(0, sv.size(), 3):
				if mine.has(k) and mine.has(k + 1) and mine.has(k + 2):
					tris.append_array([index[k], index[k + 1], index[k + 2]])
		if tris.is_empty():
			continue
		out[Mesh.ARRAY_VERTEX] = vs
		out[Mesh.ARRAY_INDEX] = tris
		if has_n:
			out[Mesh.ARRAY_NORMAL] = ns
		if has_uv:
			out[Mesh.ARRAY_TEX_UV] = uvs
		if has_c:
			out[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var mat: Material = _mats[key[0]][key[1]]
		if has_c and mat is BaseMaterial3D and not mat.vertex_color_use_as_albedo:  # the case: its cover's colour, painted on its corners
			mat = mat.duplicate()
			mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		if has_uv and vs.size() <= 8:  # the cover: which face it's on, and how far it tips
			var top := Vector3.ZERO
			var bottom := Vector3.ZERO
			for v in vs:
				if v.y > 0.0:
					top += v
				else:
					bottom += v
			cover_x = bottom.x
			lean = atan2((top.x - bottom.x) * 2.0 / vs.size(), size.y)
	t.flip = cover_x > 0.0  # (in the hand the cover's turned to the -x face, as the web game's is)
	t.lean = lean
	return mesh


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


func _slot(e: Dictionary) -> Dictionary:  # how a slot shows on the bar: { name, used (0..1 wound on) }
	return { "name": e.t, "used": wind_frac(e) }


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


func show_tape(t: Dictionary) -> void:  # the tape in your hand (fresh off the shelf, or back out of the VCR)
	held = t
	inspecting = false
	_hand_mesh.mesh = t.get("mesh")
	_hand_mesh.rotation = Vector3(0, PI if t.get("flip", false) else 0.0, 0)
	_hand_mesh.rotate_object_local(Vector3.BACK, t.get("lean", 0.0))  # upright, not tipped the way it sat
	_hand.transform = HAND
	_hand.visible = true


func release() -> void:  # clears the hand without touching the shelf (into the VCR)
	held = null
	inspecting = false
	peek = null
	_hand.visible = false
	_gone()


func is_rewound(t: Dictionary) -> bool:
	return t.ep == 0 and t.at < 1.0


func wind_frac(t: Dictionary) -> float:  # how far through the whole tape it's wound, 0..1: episodes played + the part of the current one
	if is_rewound(t):
		return 0.0
	var n: int = t.e.size()
	var d: float = t.get("d", 1500.0 if n > 1 else 6000.0)  # (its length, if it's been played; a movie-ish guess if not)
	return minf(1.0, (t.ep + minf(1.0, t.at / d)) / n)


func set_wind_frac(t: Dictionary, f: float) -> void:  # the inverse
	var n: int = t.e.size()
	var d: float = t.get("d", 1500.0 if n > 1 else 6000.0)
	var x := clampf(f, 0.0, 1.0) * n
	t.ep = mini(n - 1, int(x)) if f > 0.0 else 0
	t.at = (x - t.ep) * d if f > 0.0 else 0.0


func rewinder_use() -> void:  # E on it: the tape in hand goes in; E again takes it out (early: only partly rewound)
	var rw := rewinder if _rw_aim.is_empty() else _rw_aim
	if rw.tape == null:
		if held == null:
			return
		rw.tape = held
		rw.f0 = wind_frac(held)
		rw.t = 0.0
		rw.dur = maxf(1.0, rw.f0 * 10.0)  # up to ten seconds, by how far it's wound
		rw.done = rw.f0 <= 0.0
		release()
	elif inv_make_room():
		var t: Dictionary = rw.tape
		rw.tape = null
		_take(t)


func put_back() -> void:  # back into its own shelf slot
	if held != null:
		if not is_rewound(held):  # shelved unrewound: it snaps back to the start, with a word about it
			hud.toast("Not rewound: %s · be kind, rewind!" % held.t)
			held.ep = 0
			held.at = 0.0
		set_on_shelf(held, true)
	release()


func _process(dt: float) -> void:
	_saver_tick(dt)
	if held != null:
		_hand.transform = _hand.transform.interpolate_with(LOOK if inspecting else HAND, minf(1.0, dt * 14.0))
	hud.inventory(inv.map(func(e: Dictionary) -> Dictionary: return _slot(e)), inv_sel)
	for rw: Dictionary in rewinders:
		if rw.tape != null and not rw.done:  # winding back
			rw.t += dt
			var p: float = minf(1.0, rw.t / rw.dur)
			set_wind_frac(rw.tape, rw.f0 * (1.0 - p))
			rw.done = p >= 1.0
	hud.now_playing("%s%s\n%s%s%s   [ ] wind · , . episode" % ["❚❚ " if video.paused else "▶ ", playing.tape.t, "%d of %d · " % [playing.idx + 1, playing.tape.e.size()] if playing.tape.e.size() > 1 else "", _clock(video.position), " / " + _clock(video.duration) if video.duration > 0.0 else ""] if playing != null and not video.url.is_empty() else "")
	if playing != null and not video.url.is_empty():  # the tape winds forward as it plays
		playing.tape.ep = playing.idx
		playing.tape.at = video.position
		if video.duration > 0.0:
			playing.tape.d = video.duration


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
			if _peek_bin:  # (out of Returns: back into Returns)
				return_bin.append(held)
				release()
			else:
				put_back()
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if held != null and inspecting:  # tuck the held-up tape back in hand (it's yours now)
			inspecting = false
			peek = null
		elif aim_slot:  # slotted back into its own spot on the shelf
			put_back()
		elif aim_returns and not return_bin.is_empty():  # Returns works like a shelf: click to look, click again to take, right-click to put it back
			if inv_make_room():
				var t: Dictionary = return_bin.pop_back()
				_take(t)
				inspecting = true
				peek = t
				_peek_bin = true
		elif hovered != null:  # another one: whatever's in hand goes into the inventory
			var t: Dictionary = hovered
			pickup(t)
			if held == t:
				peek = t
				_peek_bin = false
		elif held != null:  # hold it up to look at it
			inspecting = true


# ---- what the crosshair's on (called from interact.gd, after the doors); returns the tip, "" if it's nothing of ours

func drop_in_returns() -> void:  # E at Returns with a tape in hand
	if held != null:
		return_bin.append(held)
		release()


func clear_aim() -> void:
	aim_returns = false
	aim_rewinder = false
	_rw_aim = {}
	hovered = null
	aim_slot = false
	aim_tv = null
	_box.visible = false


func aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	clear_aim()
	if held != null and inspecting:
		return "%s\n%s\nClick — keep it · Right-click — put it back" % [held.t, held.c]
	if held != null and held.off:  # its own empty slot: within 8 cm of the middle of it, nothing solid in front
		var at := _pos(held) - from
		var t := at.dot(dir)
		aim_slot = t > 0.3 and t < REACH and (at - dir * t).length() < 0.08 and hit_d > t - 0.15
		if aim_slot:
			_show_box(held)
			return "Click — put %s back" % held.t
	for rw: Dictionary in rewinders:  # the rewinder
		if not (hit and hit_d < 2.4 and hit.position.distance_to(rw.at) < 0.3 and (held != null or rw.tape != null)):
			continue
		_rw_aim = rw
		aim_rewinder = true
		if rw.tape == null:
			return "E — rewind %s%s" % [held.t, " (already rewound)" if is_rewound(held) else ""]
		return "E — take out %s · rewound" % rw.tape.t if rw.done else "Rewinding… %d%% · E — take it out early" % roundi(100.0 * rw.t / rw.dur)
	if hit and hit_d < 2.4 and hit.position.distance_to(_returns_at) < 0.55 and (held != null or not return_bin.is_empty()):  # Returns: the bin behind the slot
		aim_returns = true
		var lines := PackedStringArray()
		if held != null:
			lines.append("E — drop tape in Returns")
		if not return_bin.is_empty():
			lines.append("Click — take a tape (%d in the bin)" % return_bin.size())
		return "\n".join(lines)
	if hit and hit_d < REACH:  # a tape: the one whose slot the crosshair lands in (and that's really there)
		var best := INF
		var c := _cell(hit.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for i: int in _grid.get(c + Vector3i(dx, dy, dz), []):
						var t: Dictionary = tapes[i]
						var l := _local(t, hit.position)
						if not t.off and absf(l.x) < 0.06 and absf(l.y) < size.y / 2.0 + 0.01 and absf(l.z) < size.z / 2.0 + 0.012 and l.length() < best:
							best = l.length()
							hovered = t
		if hovered != null and _corners(hovered).is_empty():
			hovered = null  # (out on rental when the level was made: an empty slot)
		if hovered != null:
			_show_box(hovered)
			return "%s\n%s" % [hovered.t, hovered.c]
	for sc: Dictionary in screens:  # a screen: you have to actually be looking at it
		var n := Vector3(sin(sc.ry), 0, cos(sc.ry))
		var facing := dir.dot(n)
		if facing > -0.01:
			continue
		var t: float = (Vector3(sc.x, sc.y, sc.z) - from).dot(n) / facing
		var on := from + dir * t - Vector3(sc.x, sc.y, sc.z)
		if t > 0.0 and t < sc.reach and t < hit_d + 0.2 and absf(on.dot(Vector3(cos(sc.ry), 0, -sin(sc.ry)))) < sc.w / 2.0 and absf(on.y) < sc.h / 2.0:
			aim_tv = sc
			if held != null:
				return "Press E to insert “%s” into the TV" % held.t
			return "Press E to eject the tape" if playing != null else "Pick up a tape from the shelves to play it here"
	return ""


func _show_box(t: Dictionary) -> void:
	_box.position = _pos(t)
	_box.rotation.y = t.ry
	_box.visible = true


# ---- the VCR

func vcr_use() -> void:  # E on the TV or the theater's screen: one tape, every screen
	if held != null:
		var tape: Dictionary = held
		var old = playing.tape if playing != null else null
		if aim_tv != null:  # the sound comes from the screen it went into: the lounge TV's set, or the theater's speakers (louder, further)
			video.audio.position = Vector3(aim_tv.x, aim_tv.y, aim_tv.z)
			video.audio.unit_size = 8.0 if aim_tv.kind == "theater" else 3.0
		play_episode(tape.ep, tape)  # it plays from wherever it's wound to
		release()  # the tape leaves your hand...
		if old != null:  # ...and the one that was in there comes out into your inventory
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
	if tape.has("d") and tape.e.size() == 1 and at > tape.d - 5.0:
		at = 0.0  # (wound right to the end: it wants rewinding, but it'll play)
	playing = { "tape": tape, "idx": idx }
	tape.ep = idx
	hud.toast("Loading: %s…" % tape.t)
	video.play_episode(tape.e[idx], at)
	_screens_show(true)


func _on_started() -> void:
	if playing == null:
		return
	if video.duration > 0.0:
		playing.tape.d = video.duration
		if video.position > video.duration - 5.0:  # (wound further than it turns out to be long: its length was a guess till now)
			video.seek(maxf(0.0, video.duration - 60.0))
	var bits: PackedStringArray = playing.tape.e[playing.idx][1].split(" - ")
	var has_code := bits.size() > 1 and RegEx.create_from_string("(?i)S\\d+E\\d+").search(bits[1]) != null
	var code := bits[1] + " · " if has_code else ""
	var ep_name := " - ".join(bits.slice(2 if has_code else 1))
	hud.toast("Now Playing: %s — %s%s" % [playing.tape.t, code, ep_name if ep_name != "" else playing.tape.e[playing.idx][1]])


func step_episode(d: int) -> void:  # the next one on the tape, when one runs out
	if playing == null:
		return
	if playing.idx + d >= playing.tape.e.size():
		playing.tape.at = 0.0  # run out: it sits in the machine, wound to the end
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
		_take(tape)  # the tape comes back out into your hand, not the shelf (whatever you were holding slides into the inventory)
	else:
		set_on_shelf(tape, true)  # hands full (9 already): it goes home (the web game: to Returns)
		hud.toast("%s went back on its shelf" % tape.t)
