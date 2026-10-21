extends Node3D
## The shelves, laid out to fit the library the way VaultBuster's are (from the web game's store/shelves.js: the
## gondola, buildFace, layBlock, the store layout), in VaultBuster's own level:
##  - the outer walls: movies from data/genres.json's new_from on (the new releases), a section at a stretch,
##    reading round from the far wall's front, across the back and down the register wall
##  - kids: the front corner by the windows: the `kids` sections, on the low shelving over its own carpet
##  - the centre: low gondolas either side of the door-to-lounge walkway: the older movies west, TV east
## The sections run on one after another, A to Z, top to bottom, each shelf full before the next; a new section starts on
## a fresh shelf, under a strip with its name. Spare bays
## stand empty at the end of their block. The store's as deep as the library needs (Level.dz, set by plan() before the
## level loads): a band more or less in the centre, the side walls' runs longer or shorter with it.
## Different here: one copy of everything (no extra copies of the hits); no rides (a small section takes a bay of its
## own); no Staff Picks, MonsterVision or candy aisle; the hanging signs go over their shelves (_hang_signs).

const TAPE := Vector3(0.105, 0.192, 0.032)  # the tape box as tapes.gd draws it: cover across, up, thickness
const SLOT_W := 0.13
const LEAN := PI * 10.0 / 180.0  # tapes tip back against each shelf's backing board
const BAY := { "len": 1.6, "rows": 4, "per_row": 11, "depth": 0.55, "top": 0.25, "h": 2.0, "board_y": [0.18, 0.63, 1.08, 1.53] }
const SHORT := { "len": 1.6, "rows": 3, "per_row": 11, "depth": 0.55, "top": 0.25, "h": 1.5, "board_y": [0.18, 0.63, 1.08] }  # centre and kids: low enough to see across the store
const WALL_L := -7.74
const STORE_X := 11.0
const STORE_Z := 28.0
const CENTER := { "corridor": 0.9, "west": 3, "east": 4, "z0": 8.6, "gap": 2.0, "bands": 4 }
const BAND_STEP := 2 * 0.55 + 2.0  # a band and the aisle behind it: what dz comes in steps of
const STRIPE := 0.02  # how far the side walls' blue stripe stands off them (the back wall's is flat)
const KIDS := { "z": 4.2, "bays": 3 }  # one gondola out from the east wall, centred front to back on the kids' carpet (z 0.1 to 8.3)
const TAGS := [["#d7262e", "#ffffff"], ["#ffd400", "#00349c"], ["#1f9e48", "#ffffff"], ["#6c2d91", "#ffd400"], ["#f26b21", "#ffffff"], ["#00a4b4", "#ffffff"], ["#111111", "#ff3b30"], ["#d6247d", "#ffffff"]]  # endcap genre cards: background, lettering
const CANDY := ["#d7262e", "#ffd400", "#5a3418", "#6c2d91", "#1f9e48", "#f26b21", "#1c4dbb", "#e85a9b"]  # the candy boxes' colours
const CANDY_W := 0.1  # a box, and the gap beside it
const COLORS := { "board": "#9aa3ad", "upright": "#1c4dbb", "backing": "#eef0f2", "strip": "#ffd400" }

var slots: Array = []  # every tape, placed: { ...item, xf (its box), a (its part of the store: wall, kids, classics, tv) }
var _parts := {}  # material -> SurfaceTool: the shelving, merged
var _unit := BoxMesh.new()
var _wedges := {}  # spec's h -> the end panels' prism
var _body := StaticBody3D.new()
var _texts := {}  # [text, font, size, colour, outline] -> { vp, mat }: lettering drawn to a picture (_bake_texts), on quads the room's light falls on like the rest (a Label3D lights itself)
var _strip_font := SystemFont.new()
var _ends := {}  # each end panel: where, which way it faces, how wide, its genres


static func front_at(y: float, spec: Dictionary) -> float:  # the gondola's sloped face: how far out it is at height y
	return spec.depth - (spec.depth - spec.top) * y / spec.h


static func cap(spec: Dictionary) -> int:
	return spec.rows * spec.per_row


static func bays_for(list: Array, spec: Dictionary) -> int:  # each section from a fresh shelf
	var n := 0
	var counts := {}
	for t: Dictionary in list:
		counts[t.c] = counts.get(t.c, 0) + 1
	for c: String in counts:
		n += ceili(float(counts[c]) / spec.per_row)
	return ceili(float(n) / spec.rows)


static func wall_bays(k: int) -> int:
	return 28 + 2 * floori(k * BAND_STEP / BAY.len)


static func plan(items: Array, cfg: Dictionary) -> Dictionary:  # who goes where, and how much deeper the store has to be
	var kids_c := {}
	for s: Dictionary in cfg.sections:
		if s.get("kids", false):
			kids_c[s.name] = true
	var kids := items.filter(func(t: Dictionary) -> bool: return kids_c.has(t.c))
	var kids_cap: int = 2 * KIDS.bays
	while bays_for(kids, SHORT) > kids_cap:  # the corner's full: its last section goes to the middle, with the rest
		var last: String = kids.back().c
		kids = kids.filter(func(t: Dictionary) -> bool: return t.c != last)
		kids_c.erase(last)
	var rest := items.filter(func(t: Dictionary) -> bool: return not kids_c.has(t.c))
	var wall := rest.filter(func(t: Dictionary) -> bool: return t.kind == "movie" and t.year >= cfg.new_from)
	var classics := rest.filter(func(t: Dictionary) -> bool: return t.kind == "movie" and t.year < cfg.new_from)
	var tv := rest.filter(func(t: Dictionary) -> bool: return t.kind != "movie")
	var k := 1 - CENTER.bands  # bands added (fewer, below 0: the store shallower): till the walls hold the new releases, and the middle the rest
	while true:
		var west_cap: int = (CENTER.bands + k) * 2 * CENTER.west
		var west := []  # the older movies west of the walkway, a whole section at a time; what doesn't fit goes on east, ahead of the TV
		var i := 0
		while i < classics.size():
			var sec: Array = classics.filter(func(t: Dictionary) -> bool: return t.c == classics[i].c)
			if bays_for(west + sec, SHORT) > west_cap:
				break
			west.append_array(sec)
			i += sec.size()
		var east := classics.slice(i) + tv
		if bays_for(wall, BAY) <= wall_bays(k) and bays_for(east, SHORT) <= (CENTER.bands + k) * 2 * CENTER.east:
			return { "k": k, "dz": k * BAND_STEP, "kids": kids, "wall": wall, "classics": west, "tv": east }
		k += 1
	return {}


static func walkway() -> float:  # the centre walkway's middle: where the aisles between the bands' ends and the wall shelves come out the same width
	return ((WALL_L + 0.1 + BAY.depth) + (STORE_X - 0.1 - BAY.depth) + (CENTER.west - CENTER.east) * SHORT.len) / 2.0


static func runs(k: int) -> Dictionary:  # the shelf runs, each { at (its first bay's end, on its back plane), ry (the way it faces), dir (the way its bays go), bays, spec }
	var dz := k * BAND_STEP
	var extra := floori(dz / BAY.len)
	var wall := [  # reading round: the far wall front to back, the back wall right to left, the register wall back to front
		{ "at": Vector3(STORE_X - 0.1, 0, 26.8 + dz), "ry": PI, "dir": Vector3(0, 0, -1), "bays": 11 + extra, "spec": BAY },
		{ "at": Vector3(3.89, 0, STORE_Z - 0.1 + dz), "ry": PI / 2, "dir": Vector3(1, 0, 0), "bays": 3, "spec": BAY },
		{ "at": Vector3(WALL_L + 0.1 + BAY.depth, 0, STORE_Z - 0.1 + dz), "ry": PI / 2, "dir": Vector3(1, 0, 0), "bays": 2, "spec": BAY },
		{ "at": Vector3(WALL_L + 0.1, 0, 8.1), "ry": 0.0, "dir": Vector3(0, 0, 1), "bays": 12 + extra, "spec": BAY },
	]
	var kids := []
	for ry: float in [PI / 2, -PI / 2]:  # its door side, round its end, its back side (like the centre's); its far end on the wall
		kids.append({ "at": Vector3(STORE_X - 0.1 - KIDS.bays * SHORT.len, 0, KIDS.z), "ry": ry, "dir": Vector3(1, 0, 0), "bays": KIDS.bays, "spec": SHORT, "wall_end": true })
	var west := []
	var east := []
	for b in CENTER.bands + k:  # each band's door side, round its end, its back side
		var z: float = CENTER.z0 + b * BAND_STEP + SHORT.depth  # (its back plane)
		for ry: float in [PI / 2, -PI / 2]:
			west.append({ "at": Vector3(walkway() - CENTER.corridor, 0, z), "ry": ry, "dir": Vector3(-1, 0, 0), "bays": CENTER.west, "spec": SHORT })
			east.append({ "at": Vector3(walkway() + CENTER.corridor, 0, z), "ry": ry, "dir": Vector3(1, 0, 0), "bays": CENTER.east, "spec": SHORT })
	return { "wall": wall, "kids": kids, "classics": west, "tv": east }


static func lay(list: Array, block: Array) -> Array:  # layBlock: the block's bays in order, each [its shelves' sections (top first, "" where empty), its tapes (cap long, null where empty)]
	var spec: Dictionary = block[0].spec
	var shelves := []  # [section, tapes]: each shelf full before the next, a new section on a fresh shelf (only a section's last is part-filled)
	for t: Dictionary in list:
		if shelves.is_empty() or shelves.back()[0] != t.c or shelves.back()[1].size() == spec.per_row:
			shelves.append([t.c, []])
		shelves.back()[1].append(t)
	var out := []
	for from in range(0, shelves.size(), spec.rows):  # top to bottom, bay after bay
		var names := []
		var arr := []
		for sh: Array in shelves.slice(from, from + spec.rows):
			names.append(sh[0])
			var row: Array = sh[1].duplicate()
			row.resize(spec.per_row)
			arr.append_array(row)
		names.resize(spec.rows)
		names = names.map(func(c) -> String: return "" if c == null else c)
		arr.resize(cap(spec))
		out.append([names, arr])
	return out  # (fewer bays than the block has: the rest stand empty at its end)


func _ready() -> void:
	var p: Dictionary = get_node("/root/Library").plan  # (by path: tools/jellyfin_check.gd loads this without the autoloads)
	if p.is_empty():
		return
	_strip_font.font_names = PackedStringArray(["Arial Black", "Arial", "sans-serif"])
	_strip_font.font_weight = 900
	var all := runs(p.k)
	for a: String in ["wall", "kids", "classics", "tv"]:
		var bays := lay(p[a], all[a])
		var bi := 0
		for r: Dictionary in all[a]:
			bi = _run(r, bays, bi, a)
	_end_signs()
	for m: String in _parts:
		var mi := MeshInstance3D.new()
		mi.mesh = _parts[m].commit()
		add_child(mi)
	add_child(_body)
	_hang_signs(p.k)
	_flatten_stripes()
	var room := get_node_or_null("../Room")
	if room != null:
		room.light(self)
	_bake_texts()
	var placed := ["wall", "kids", "classics", "tv"].map(func(a: String) -> String: return "%s %d/%d" % [a, slots.filter(func(t: Dictionary) -> bool: return t.a == a).size(), p[a].size()])
	print("store: %s; %d bays on the walls, %d bands in the middle; %.1f m deeper than VaultBuster's" % [", ".join(placed), wall_bays(p.k), CENTER.bands + p.k, p.dz])


func _run(r: Dictionary, bays: Array, bi: int, area: String) -> int:  # one run of bays (buildFace, buildRun): returns the next bay's index
	var spec: Dictionary = r.spec
	var right := -Vector3(sin(r.ry), 0, cos(r.ry))  # the shopper's right, facing these shelves
	var order: Array = range(r.bays) if r.dir.dot(right) > 0.0 else range(r.bays - 1, -1, -1)  # reading left to right
	var basis := Basis(Vector3.UP, r.ry)
	var sections := []
	for i: int in order:
		var xf := Transform3D(basis, r.at + r.dir * (i + 0.5) * spec.len)  # the bay's own frame: shelves facing +x, along z
		var bay: Array = bays[bi] if bi < bays.size() else [[], []]
		bi += 1
		_bay(xf, spec, bay, area)
		for c: String in bay[0]:
			if c != "" and not c in sections:
				sections.append(c)
	for i in r.bays + 1:  # the blue wedge end panels at every bay boundary
		_part("upright", Transform3D(basis, r.at + r.dir * i * spec.len), _wedge(spec))
	if not sections.is_empty():  # both ends (not one against a wall): its genres, for the end panel's sign (_end_signs)
		var w := front_at(spec.h - 0.1, spec)  # (the wedge up top, its narrowest)
		for e: Array in [[r.at, r.dir], [r.at + r.dir * r.bays * spec.len, -r.dir]].slice(0, 1 if r.get("wall_end", false) else 2):
			var key := str((e[0] as Vector3).snapped(Vector3.ONE * 0.01))  # (a gondola's two sides share their ends: one sign across both)
			var end: Dictionary = _ends.get_or_add(key, { "at": e[0], "out": -e[1], "spec": spec, "mid": Vector3.ZERO, "n": 0, "w": 0.0, "sections": [] })
			end.mid += basis.x * w / 2.0
			end.n += 1
			end.w += w
			for c: String in sections:
				if not c in end.sections:
					end.sections.append(c)
	return bi


func _bay(xf: Transform3D, spec: Dictionary, bay: Array, area: String) -> void:
	var zl: float = spec.len - 0.05
	var h: float = spec.h
	for r in spec.rows:  # stepped shelves: each board's front edge on the sloped face, a white backing up to the next
		var y: float = spec.board_y[r]
		var d := front_at(y, spec)
		_box("board", xf, Vector3(d / 2.0, y, 0), Vector3(d, 0.04, zl))
		var rise: float = spec.board_y[r + 1] if r + 1 < spec.rows else h
		var xb := front_at(rise, spec)
		var y0 := y + 0.02
		var y1 := rise - (0.02 if r < spec.rows - 1 else 0.04)
		_box("backing", xf, Vector3(xb - 0.0075, (y0 + y1) / 2.0, 0), Vector3(0.015, y1 - y0, zl))
	_box("upright", xf, Vector3(spec.top / 2.0, h - 0.02, 0), Vector3(spec.top, 0.04, zl))  # the cap
	_box("upright", xf, Vector3(front_at(0, spec) - 0.03, spec.board_y[0] / 2.0, 0), Vector3(0.02, spec.board_y[0], zl))  # the toe kick
	_box("upright", xf, Vector3(0.005, h / 2.0, 0), Vector3(0.02, h, spec.len))  # the solid back
	var shape := CollisionShape3D.new()  # (to halfway down the slope: the crosshair lands among the covers, which tapes.gd then picks between)
	var mid: float = (spec.depth + spec.top) / 2.0
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(mid, h, zl)
	shape.transform = xf * Transform3D(Basis.IDENTITY, Vector3(mid / 2.0, h / 2.0, 0))
	_body.add_child(shape)
	if area == "wall" and bay[0].is_empty():  # (the walls fill in reading order, so their empty bays are at the register wall's front end, by the cooler)
		_candy(xf, spec)
		return
	var names: Array = bay[0]
	for r in names.size():  # the header strip, blue on yellow: the top shelf's section up top; one starting lower down, a smaller strip just over its shelf
		if names[r] == "" or (r > 0 and names[r] == names[r - 1]):
			continue
		var y: float = h - 0.15 if r == 0 else spec.board_y[spec.rows - r] - 0.06
		var x: float = spec.top + 0.004 if r == 0 else front_at(spec.board_y[spec.rows - r], spec) + 0.004
		var sh := 0.16 if r == 0 else 0.08
		_box("strip", xf, Vector3(x, y, 0), Vector3(0.004, sh, spec.len - 0.1))
		_text(names[r].to_upper(), _strip_font, 64, Color("#00349c"), 0, minf(0.0018 * sh / 0.16, 1.4 / maxf(1.0, names[r].length() * 0.62 * 64)), xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x + 0.004, y, 0)))
	var tapes: Array = bay[1]
	var tilt := Basis(Vector3.BACK, LEAN) * Basis(Vector3.UP, PI / 2)  # the box's cover (+z) to the shelf's front (+x), tipped back
	var n := Vector3(cos(LEAN), sin(LEAN), 0)
	for k in tapes.size():
		if tapes[k] == null:
			continue
		var row: int = spec.rows - 1 - k / spec.per_row  # (row 0 is the bottom board)
		var slot: int = k % spec.per_row
		var c := _lean_at(row, spec)
		var cover := Vector3(c.x, c.y, spec.len / 2.0 - 0.08 - (slot + 0.5) * SLOT_W)  # slot 0 on the shopper's left
		var t: Dictionary = tapes[k].duplicate()
		t.xf = xf * Transform3D(tilt, cover - n * (TAPE.z / 2.0 + 0.001))
		t.a = area
		slots.append(t)


func _candy(xf: Transform3D, spec: Dictionary) -> void:  # a bay of boxed candy, every shelf full, under a CANDY strip
	_box("strip", xf, Vector3(spec.top + 0.004, spec.h - 0.15, 0), Vector3(0.004, 0.16, spec.len - 0.1))
	_text("CANDY", _strip_font, 64, Color("#00349c"), 0, 0.0018, xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(spec.top + 0.008, spec.h - 0.15, 0)))
	var n := int((spec.len - 0.1) / CANDY_W)
	for r in spec.rows:
		var y: float = spec.board_y[r] + 0.02
		var rise: float = spec.board_y[r + 1] if r + 1 < spec.rows else spec.h
		var x := (front_at(rise, spec) + front_at(y, spec)) / 2.0  # (stood up on the step, between its backing and its front edge)
		for i in n:
			var z := (i - (n - 1) / 2.0) * CANDY_W
			_box(CANDY[(r * 7 + i * 3 + (i * i) % 5) % CANDY.size()], xf, Vector3(x, y + 0.065, z), Vector3(0.03, 0.13, CANDY_W - 0.015))
			_box("ffffff", xf, Vector3(x + 0.016, y + 0.085, z), Vector3(0.002, 0.03, CANDY_W - 0.03))  # (its label)


static func _lean_at(r: int, spec: Dictionary) -> Vector2:  # the middle of a cover on row r, leaning back with its top on that row's backing (leanAt)
	var y0: float = spec.board_y[r] + 0.02
	var back := front_at(spec.board_y[r + 1] if r + 1 < spec.rows else spec.h, spec)
	var sn := sin(LEAN)
	var cs := cos(LEAN)
	var xb0 := back + TAPE.y * sn + 0.002
	return Vector2(xb0 - TAPE.y / 2.0 * sn + (TAPE.z + 0.001) * cs, y0 + TAPE.y / 2.0 * cs + (TAPE.z + 0.001) * sn)


func _box(mat: String, xf: Transform3D, at: Vector3, size: Vector3) -> void:
	_part(mat, xf * Transform3D(Basis.from_scale(size), at), _unit)


func _part(mat: String, xf: Transform3D, mesh: Mesh) -> void:
	if not _parts.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(COLORS.get(mat, mat))  # (or a colour of its own: the endcap cards)
		st.set_material(m)
		_parts[mat] = st
	_parts[mat].append_from(mesh, 0, xf)


func _wedge(spec: Dictionary) -> ArrayMesh:  # an end panel: the gondola's side, 5 cm thick, centred on the boundary
	if _wedges.has(spec.h):
		return _wedges[spec.h]
	var p := [Vector2(0, 0), Vector2(spec.depth, 0), Vector2(spec.top, spec.h), Vector2(0, spec.h)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var v := func(i: int, z: float) -> Vector3: return Vector3(p[i].x, p[i].y, z)
	for f: Array in [[0, 2, 1, 0.025], [0, 3, 2, 0.025], [0, 1, 2, -0.025], [0, 2, 3, -0.025]]:  # the two faces (clockwise from outside, Godot's front: else the far face shows through, fighting the shelves' ends)
		for i in 3:
			st.add_vertex(v.call(f[i], f[3]))
	for i in 4:  # round the edge
		var a: int = i
		var b: int = (i + 1) % 4
		for q: Array in [[a, 0.025], [b, 0.025], [b, -0.025], [a, 0.025], [b, -0.025], [a, -0.025]]:  # (clockwise from outside too: else they're culled, and you see into the panel)
			st.add_vertex(v.call(q[0], q[1]))
	st.generate_normals()
	st.index()  # (merged into the shelving with the boxes, which are indexed: unindexed, its triangles were dropped)
	_wedges[spec.h] = st.commit()
	return _wedges[spec.h]


func _end_signs() -> void:  # on each end panel, top down: a printed card per genre, its own colour, white-edged, in poster lettering
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Haettenschweiler", "Arial Narrow", "Arial Black"])
	for end: Dictionary in _ends.values():
		var w: float = end.w - 0.05
		var b := Basis.looking_at(-end.out, Vector3.UP)  # (+z out of the panel: a label reads from its +z)
		var y: float = end.spec.h - 0.06
		for c: String in end.sections:
			var lines: PackedStringArray = c.to_upper().split(" & ")  # ("X &" over "Y": bigger letters)
			if lines.size() > 1:
				lines[0] += " &"
			var longest: int = Array(lines).reduce(func(a: int, l: String) -> int: return maxi(a, l.length()), 1)
			var px := minf(0.0021, (w - 0.04) / (longest * 0.5 * 48))  # (Impact's narrow: half its height a letter)
			var h := lines.size() * 48 * px * 1.05 + 0.03
			var at: Vector3 = end.at + end.mid / end.n + Vector3(0, y - h / 2.0, 0)
			var pair: Array = TAGS[absi(c.hash()) % TAGS.size()]
			_card(Transform3D(b, at + end.out * 0.028), Vector3(w, h, 0.004), Color.WHITE)
			_card(Transform3D(b, at + end.out * 0.031), Vector3(w - 0.016, h - 0.016, 0.004), Color(pair[0]))
			_text("\n".join(lines), font, 48, Color(pair[1]), 6 if pair[1] == "#ffffff" else 0, px, Transform3D(b, at + end.out * 0.034))
			y -= h + 0.015


func _card(xf: Transform3D, size: Vector3, colour: Color) -> void:  # (into the shelving's merged mesh: lit like it)
	_part(colour.to_html(false), xf.scaled_local(size), _unit)


func _text(text: String, font: Font, size: int, colour: Color, outline: int, px: float, xf: Transform3D) -> void:  # px: metres a font pixel, as Label3D's pixel_size
	var key := [text, font, size, colour, outline]
	if not _texts.has(key):
		var vp := SubViewport.new()  # (drawn at twice the size: crisp up close)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.label_settings = LabelSettings.new()
		l.label_settings.font = font
		l.label_settings.font_size = size * 2
		l.label_settings.font_color = colour
		l.label_settings.outline_size = outline * 2
		l.label_settings.outline_color = Color(0, 0, 0, 0.6)
		vp.add_child(l)
		add_child(vp)
		vp.size = Vector2i(l.get_minimum_size().ceil())
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_texts[key] = { "vp": vp, "mat": m }
	var t: Dictionary = _texts[key]
	var quad := QuadMesh.new()
	quad.size = Vector2(t.vp.size) * px / 2.0
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad.get_mesh_arrays())
	mesh.surface_set_material(0, t.mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)


func _bake_texts() -> void:  # each lettering's picture, once its viewport's been drawn (the room's material holds the same texture)
	await RenderingServer.frame_post_draw
	for t: Dictionary in _texts.values():
		var img: Image = t.vp.get_texture().get_image()
		img.generate_mipmaps()
		t.mat.albedo_texture.set_image(img)
		t.vp.queue_free()


func _hang_signs(k: int) -> void:  # KIDS over the kids' gondola; TV SHOWS over the aisle between the TV side's bands, CLASSICS (a copy of it: the level's own went with the strip a smaller store cuts out) over the classics side's
	var store := get_node_or_null("../World/store")
	if store == null:
		return
	var aisle: float = CENTER.z0 + 2.0 * SHORT.depth + CENTER.gap / 2.0 if CENTER.bands + k >= 2 else CENTER.z0 - 0.5  # (one band: in front of it)
	var tv := _sign(store, "vaultbuster_121.jpg")
	var classics := []
	for m: MeshInstance3D in tv:
		var c: MeshInstance3D = m.duplicate()
		m.get_parent().add_child(c)
		c.global_transform = m.global_transform
		if preload("res://level.gd").texture_of(m) == "vaultbuster_121.jpg":
			var mat: Material = m.mesh.surface_get_material(0).duplicate()
			mat.set_shader_parameter("tex", load("res://world/vaultbuster_120.jpg"))
			c.set_surface_override_material(0, mat)
		classics.append(c)
	_move(_sign(store, "vaultbuster_117.jpg"), Vector3(STORE_X - 0.1 - KIDS.bays * SHORT.len / 2.0, 0, KIDS.z))
	_move(tv, Vector3(walkway() + CENTER.corridor + CENTER.east * SHORT.len / 2.0, 0, aisle))
	_move(classics, Vector3(walkway() - CENTER.corridor - CENTER.west * SHORT.len / 2.0, 0, aisle))


func _flatten_stripes() -> void:  # the blue stripe along the side walls: 20 cm deep in the level, standing well off them; down to the back wall's few, still against the wall
	var store := get_node_or_null("../World/store")
	if store == null:
		return
	for m: MeshInstance3D in store.find_children("box 0_20 x 0_22 x 28_00*", "MeshInstance3D", false, false):
		var b := m.global_transform * m.get_aabb()
		var wall_x: float = b.position.x if b.get_center().x < 0.0 else b.end.x  # (the face against the wall stays put)
		var k := STRIPE / b.size.x
		var xf := m.global_transform
		m.global_transform = Transform3D(Basis.from_scale(Vector3(k, 1, 1)) * xf.basis, Vector3(wall_x + (xf.origin.x - wall_x) * k, xf.origin.y, xf.origin.z))
	var back := store.find_children("box 18_74 x 0_22 x 0_00*", "MeshInstance3D", false, false)
	var walls := { "w": -7.63, "e": 10.89, "b": (back[0].global_transform * back[0].get_aabb()).position.z if back.size() else INF }  # (the side walls' faces: where their stripes sit)
	var poster := RegEx.create_from_string("vaultbuster_(164|16[6-9]|17\\d|18[0-7])\\.")
	for m: MeshInstance3D in store.find_children("*", "MeshInstance3D", true, false):  # the posters, frame and bulbs with them: spaced off the side walls for the old stripe, and a little off the back; back against them
		if not poster.search(preload("res://level.gd").texture_of(m)):
			continue
		var g: Node3D = m.get_parent()
		var b := _bounds_of(g)
		if b.size.x < 0.3:  # (on a side wall)
			g.global_position.x += (walls.w + STRIPE + 0.005 - b.position.x) if b.get_center().x < 0.0 else (walls.e - STRIPE - 0.005 - b.end.x)
		elif b.size.z < 0.3 and absf(b.end.z - walls.b) < 0.5:  # (on the back wall: its stripe's flat)
			g.global_position.z += walls.b - 0.005 - b.end.z


static func _bounds_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _sign(store: Node, tex: String) -> Array:  # a hanging sign: its faces, and the two cables it hangs from
	var faces := store.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return preload("res://level.gd").texture_of(m) == tex)
	if faces.is_empty():
		return []
	var at: Vector3 = faces[0].global_position
	return faces + store.find_children("cylinder*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
		var p := m.global_position
		return absf(p.z - at.z) < 0.05 and absf(p.x - at.x) < 1.5 and p.y > at.y + 0.2 and p.y < at.y + 0.8)


func _move(parts: Array, to: Vector3) -> void:  # (along the floor: the height it hangs at stays)
	if parts.is_empty():
		return
	var by := Vector3(to.x - parts[0].global_position.x, 0, to.z - parts[0].global_position.z)
	for m: MeshInstance3D in parts:
		m.global_position += by