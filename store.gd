extends Node3D
## The shelves, laid out to fit the library the way VaultBuster's are (from the web game's store/shelves.js: the
## gondola, buildFace, layBlock, the store layout), in VaultBuster's own level:
##  - the outer walls: movies from data/genres.json's new_from on (the new releases), a section at a stretch,
##    reading round from the far wall's front, across the back and down the register wall
##  - kids: the front corner by the windows: the `kids` sections, on the low shelving over its own carpet
##  - the centre: low gondolas either side of the door-to-lounge walkway: the older movies west, TV east
## Each section starts on a fresh bay and runs A to Z, left to right and top to bottom; spare bays go to the most
## crowded sections, so a bay's tapes are spread over its shelves rather than bunched up top. A bigger library makes
## the store deeper (Level.dz, set by plan() before the level loads): the side walls' runs get longer, and the centre
## gets more bands.
## Different here: one copy of everything (no extra copies of the hits); no rides (a small section takes a bay of its
## own); no Staff Picks, MonsterVision or candy aisle; the hanging CLASSICS sign moves up to the front band.

const TAPE := Vector3(0.105, 0.192, 0.032)  # the tape box as tapes.gd draws it: cover across, up, thickness
const SLOT_W := 0.13
const LEAN := PI * 10.0 / 180.0  # tapes tip back against each shelf's backing board
const BAY := { "len": 1.6, "rows": 4, "per_row": 11, "depth": 0.55, "top": 0.25, "h": 2.0, "board_y": [0.18, 0.63, 1.08, 1.53] }
const SHORT := { "len": 1.6, "rows": 3, "per_row": 11, "depth": 0.55, "top": 0.25, "h": 1.5, "board_y": [0.18, 0.63, 1.08] }  # centre and kids: low enough to see across the store
const WALL_L := -7.74
const STORE_X := 11.0
const STORE_Z := 28.0
const CENTER := { "corridor": 1.5, "west": 2, "east": 4, "z0": 8.6, "gap": 2.0, "bands": 4 }
const BAND_STEP := 2 * 0.55 + 2.0  # a band and the aisle behind it: what dz comes in steps of
const KIDS := { "band_x": [4.75, 8.15], "z0": 1.1, "bays": 4 }
const COLORS := { "board": "#9aa3ad", "upright": "#1c4dbb", "backing": "#eef0f2", "strip": "#ffd400" }

var slots: Array = []  # every tape, placed: { ...item, xf (its box), a (its part of the store: wall, kids, classics, tv) }
var _parts := {}  # material -> SurfaceTool: the shelving, merged
var _unit := BoxMesh.new()
var _wedges := {}  # spec's h -> the end panels' prism
var _body := StaticBody3D.new()


static func front_at(y: float, spec: Dictionary) -> float:  # the gondola's sloped face: how far out it is at height y
	return spec.depth - (spec.depth - spec.top) * y / spec.h


static func cap(spec: Dictionary) -> int:
	return spec.rows * spec.per_row


static func bays_for(list: Array, spec: Dictionary) -> int:  # each section from a fresh bay
	var n := 0
	var counts := {}
	for t: Dictionary in list:
		counts[t.c] = counts.get(t.c, 0) + 1
	for c: String in counts:
		n += ceili(float(counts[c]) / cap(spec))
	return n


static func wall_bays(k: int) -> int:
	return 28 + 2 * floori(k * BAND_STEP / BAY.len)


static func plan(items: Array, cfg: Dictionary) -> Dictionary:  # who goes where, and how much deeper the store has to be
	var kids_c := {}
	for s: Dictionary in cfg.sections:
		if s.get("kids", false):
			kids_c[s.name] = true
	var kids := items.filter(func(t: Dictionary) -> bool: return kids_c.has(t.c))
	var kids_cap: int = KIDS.band_x.size() * 2 * KIDS.bays
	while bays_for(kids, SHORT) > kids_cap:  # the corner's full: its last section goes to the middle, with the rest
		var last: String = kids.back().c
		kids = kids.filter(func(t: Dictionary) -> bool: return t.c != last)
		kids_c.erase(last)
	var rest := items.filter(func(t: Dictionary) -> bool: return not kids_c.has(t.c))
	var wall := rest.filter(func(t: Dictionary) -> bool: return t.kind == "movie" and t.year >= cfg.new_from)
	var classics := rest.filter(func(t: Dictionary) -> bool: return t.kind == "movie" and t.year < cfg.new_from)
	var tv := rest.filter(func(t: Dictionary) -> bool: return t.kind != "movie")
	var k := 0  # bands added: till the walls hold the new releases, and the middle the rest
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
	for bx: float in KIDS.band_x:  # each band's entrance side front to back, round its back end, its far side back to front
		for ry: float in [PI, 0.0]:
			kids.append({ "at": Vector3(bx, 0, KIDS.z0), "ry": ry, "dir": Vector3(0, 0, 1), "bays": KIDS.bays, "spec": SHORT })
	var west := []
	var east := []
	for b in CENTER.bands + k:  # each band's door side, round its end, its back side
		var z: float = CENTER.z0 + b * BAND_STEP + SHORT.depth  # (its back plane)
		for ry: float in [PI / 2, -PI / 2]:
			west.append({ "at": Vector3(-CENTER.corridor, 0, z), "ry": ry, "dir": Vector3(-1, 0, 0), "bays": CENTER.west, "spec": SHORT })
			east.append({ "at": Vector3(CENTER.corridor, 0, z), "ry": ry, "dir": Vector3(1, 0, 0), "bays": CENTER.east, "spec": SHORT })
	return { "wall": wall, "kids": kids, "classics": west, "tv": east }


static func lay(list: Array, block: Array) -> Array:  # layBlock: the block's bays in order, each [section, its tapes (cap long, null where empty)]
	var spec: Dictionary = block[0].spec
	var units := []
	for t: Dictionary in list:
		if units.is_empty() or units.back().c != t.c:
			units.append({ "c": t.c, "tapes": [], "bays": 0 })
		units.back().tapes.append(t)
	for u: Dictionary in units:
		u.bays = ceili(float(u.tapes.size()) / cap(spec))
	var spare: int = block.reduce(func(a: int, r: Dictionary) -> int: return a + r.bays, 0) - units.reduce(func(a: int, u: Dictionary) -> int: return a + u.bays, 0)
	while spare > 0 and not units.is_empty():  # spare bays to the most crowded
		var most: Dictionary = units.reduce(func(a: Dictionary, u: Dictionary) -> Dictionary: return u if float(u.tapes.size()) / u.bays > float(a.tapes.size()) / a.bays else a)
		most.bays += 1
		spare -= 1
	var out := []
	for u: Dictionary in units:
		var from := 0
		for i in u.bays:
			var n: int = u.tapes.size() / u.bays + (1 if i < u.tapes.size() % u.bays else 0)  # spread evenly over its bays...
			var arr := []
			arr.resize(cap(spec))
			var k := 0
			for r in spec.rows:  # ...and each bay's over its shelves, top first
				for j in n / spec.rows + (1 if r < n % spec.rows else 0):
					arr[r * spec.per_row + j] = u.tapes[from + k]
					k += 1
			from += n
			out.append([u.c, arr])
	return out


func _ready() -> void:
	var p: Dictionary = get_node("/root/Library").plan  # (by path: tools/jellyfin_check.gd loads this without the autoloads)
	if p.is_empty():
		return
	var all := runs(p.k)
	for a: String in ["wall", "kids", "classics", "tv"]:
		var bays := lay(p[a], all[a])
		var bi := 0
		for r: Dictionary in all[a]:
			bi = _run(r, bays, bi, a)
	for m: String in _parts:
		var mi := MeshInstance3D.new()
		mi.mesh = _parts[m].commit()
		add_child(mi)
	add_child(_body)
	_move_classics_sign()
	var room := get_node_or_null("../Room")
	if room != null:
		room.light(self)
	var placed := ["wall", "kids", "classics", "tv"].map(func(a: String) -> String: return "%s %d/%d" % [a, slots.filter(func(t: Dictionary) -> bool: return t.a == a).size(), p[a].size()])
	print("store: %s; %d bays on the walls, %d bands in the middle; %.1f m deeper" % [", ".join(placed), wall_bays(p.k), CENTER.bands + p.k, p.dz])


func _run(r: Dictionary, bays: Array, bi: int, area: String) -> int:  # one run of bays (buildFace, buildRun): returns the next bay's index
	var spec: Dictionary = r.spec
	var right := -Vector3(sin(r.ry), 0, cos(r.ry))  # the shopper's right, facing these shelves
	var order: Array = range(r.bays) if r.dir.dot(right) > 0.0 else range(r.bays - 1, -1, -1)  # reading left to right
	var basis := Basis(Vector3.UP, r.ry)
	var sections := []
	for i: int in order:
		var xf := Transform3D(basis, r.at + r.dir * (i + 0.5) * spec.len)  # the bay's own frame: shelves facing +x, along z
		var bay: Array = bays[bi] if bi < bays.size() else ["", []]
		bi += 1
		_bay(xf, spec, bay, area)
		if bay[0] != "" and not bay[0] in sections:
			sections.append(bay[0])
	for i in r.bays + 1:  # the blue wedge end panels at every bay boundary
		_part("upright", Transform3D(basis, r.at + r.dir * i * spec.len), _wedge(spec))
	if not sections.is_empty():  # both ends: what's on this run
		for e: Array in [[r.at, r.dir], [r.at + r.dir * r.bays * spec.len, -r.dir]]:
			var w := front_at(1.1 + sections.size() * 0.08, spec) - 0.04  # (as wide as the wedge is where the list's top comes: tagPlane)
			var longest: int = sections.reduce(func(a: int, s: String) -> int: return maxi(a, s.length()), 1)
			var l := _label("\n".join(sections.map(func(s: String) -> String: return s.to_upper())), Color.WHITE, 26, minf(0.0035, w / (longest * 0.66 * 26)))
			l.outline_size = 8
			l.double_sided = false  # (from behind, the panel's in the way: not the words backwards)
			l.outline_modulate = Color(0, 0, 0, 0.5)
			l.position = e[0] - e[1] * 0.033 + basis.x * front_at(1.1, spec) / 2.0 + Vector3(0, 1.1, 0)
			l.basis = Basis.looking_at(e[1], Vector3.UP)  # (a label reads from its +z: turned to face out of the run's end)
			add_child(l)
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
	if bay[0] == "":
		return
	_box("strip", xf, Vector3(spec.top + 0.004, h - 0.15, 0), Vector3(0.004, 0.16, spec.len - 0.1))  # the header strip: the section, blue on yellow
	var strip := _label(bay[0].to_upper(), Color("#00349c"), 64, minf(0.0018, 1.4 / maxf(1.0, bay[0].length() * 0.62 * 64)))
	strip.transform = xf * Transform3D(Basis(Vector3.UP, PI / 2), Vector3(spec.top + 0.008, h - 0.15, 0))
	add_child(strip)
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
		m.albedo_color = Color(COLORS[mat])
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
	for f: Array in [[0, 1, 2, 0.025], [0, 2, 3, 0.025], [0, 2, 1, -0.025], [0, 3, 2, -0.025]]:  # the two faces
		for i in 3:
			st.add_vertex(v.call(f[i], f[3]))
	for i in 4:  # round the edge
		var a: int = i
		var b: int = (i + 1) % 4
		for q: Array in [[a, 0.025], [b, 0.025], [b, -0.025], [a, 0.025], [b, -0.025], [a, -0.025]]:
			st.add_vertex(v.call(q[0], q[1]))
	st.generate_normals()
	_wedges[spec.h] = st.commit()
	return _wedges[spec.h]


func _label(text: String, color: Color, size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial Black", "Arial", "sans-serif"])
	f.font_weight = 900
	l.font = f
	return l


func _move_classics_sign() -> void:  # CLASSICS hangs over the front band, where the older movies start now
	var store := get_node_or_null("../World/store")
	if store == null:
		return
	for m: MeshInstance3D in store.find_children("*", "MeshInstance3D", true, false):
		var p := m.global_position
		var classics: bool = preload("res://level.gd").texture_of(m) == "vaultbuster_120.jpg"
		var cable: bool = String(m.name).begins_with("cylinder") and absf(p.z - 14.3) < 0.1 and p.x < 0.0 and p.y > 3.0
		if classics or cable:
			m.global_position.z = CENTER.z0 - 0.5
