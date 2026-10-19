extends Node3D
## The store, built to fit the library: build(items) lays out the shelves, then the room round them, and hands
## tapes.gd every tape's place.
##
## The sales floor is rows of double-sided shelf units running front to back, a 1.2 m bay at a time: five shelves
## of nine tapes, face out. Each section starts on a fresh bay, with its name over it, and runs A to Z across each
## shelf, then down to the next. The order snakes through the aisles: up the left one, down the next, and so on.
## The rows lengthen and multiply together as the library grows, so the floor stays roughly square. The front of
## the store is the counter by the door and a couch facing a TV.
## Front wall at z = 0, back wall at z = depth; you start just inside the front, facing in.

const TAPE := Vector3(0.105, 0.192, 0.032)  # a tape's cover across, up, and the box's thickness
const PITCH := 0.13  # tape to tape along a shelf
const PER_SHELF := 9
const SHELVES: Array[float] = [1.70, 1.36, 1.02, 0.68, 0.34]  # the boards' tops, top shelf first
const BAY := 1.2
const UNIT_L := 2 * BAY  # a shelf unit: two bays a side
const UNIT_D := 0.5  # back to back, both sides
const UNIT_H := 2.0
const ROW_GAP := 2.1  # unit centre to centre across an aisle
const FRONT := 6.5  # the door, counter and couch, before the shelves start
const BACK := 1.8
const SIDE := 1.7  # the aisle down each side wall
const CEILING := 3.0
const MIN_W := 11.0  # room for the counter and the couch
const PER_BAY := PER_SHELF * 5  # (SHELVES.size(), as a constant)

var width := MIN_W
var depth := FRONT + BACK + UNIT_L
var slots: Array = []  # the items, each now with a place: { ...item, p (its middle), n (the way its cover faces), ry }
var screens: Array = []  # what tapes.gd plays on: { x, y, z, ry, w, h, reach, kind }
var seats: Array = []  # what you can sit on: { kind, x, y, z, ry, hipY }

var _boxes := {}  # material name -> [Transform3D]: every plain box, drawn per material in one go
var _mats := {
	"wood": _mat(Color("#3b2a1e")), "board": _mat(Color("#c9c2b4")), "carpet": _mat(Color("#1c2a4a"), 1.0),
	"wall": _mat(Color("#b9ae98")), "ceiling": _mat(Color("#e8e6e0")), "trim": _mat(Color("#7a1f2b")),
	"counter": _mat(Color("#5a3d2b")), "couch": _mat(Color("#6b2430"), 1.0), "tv": _mat(Color("#141414"), 0.4),
	"panel": _glow(Color("#fff8ea")),
}


static func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _glow(c: Color) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	return m


static func layout(items: Array) -> Dictionary:  # where everything goes: { rows, per_row, bays: [{ c, items }] }
	var bays := []
	var i := 0
	while i < items.size():  # each section from a fresh bay
		var bay := { "c": items[i].c, "items": [] }
		while i < items.size() and items[i].c == bay.c and bay.items.size() < PER_BAY:
			bay.items.append(items[i])
			i += 1
		bays.append(bay)
	var units := maxi(1, ceili(bays.size() / 4.0))
	var per_row := maxi(2, ceili(sqrt(units * ROW_GAP / UNIT_L)))  # rows' length against how many: about square
	return { "rows": maxi(1, ceili(float(units) / per_row)), "per_row": per_row, "bays": bays }


static func faces(rows: int) -> Array:  # the shelf faces in browsing order: [row, side (-1: its -x face, 1: its +x), front to back?]
	var out := []
	for a in rows + 1:  # aisle a, between row a-1 and row a: in along row a, back along row a-1, each the way it reads
		if a < rows:
			out.append([a, -1, true])
		if a > 0:
			out.append([a - 1, 1, false])
	return out


func build(items: Array) -> void:
	for c in get_children():
		c.free()
	_boxes.clear()
	slots.clear()
	var plan := layout(items)
	var rows: int = plan.rows
	var per_row: int = plan.per_row
	width = maxf(MIN_W, 2.0 * SIDE + (rows - 1) * ROW_GAP + UNIT_D)
	depth = FRONT + per_row * UNIT_L + BACK
	var x0 := (width - (rows - 1) * ROW_GAP) / 2.0  # the first row's middle (the rows centred)
	for r in rows:
		for u in per_row:
			_unit(Vector3(x0 + r * ROW_GAP, 0.0, FRONT + (u + 0.5) * UNIT_L))
	var bay_i := 0
	for f: Array in faces(rows):  # the bays, in order, onto the faces
		for k in per_row * 2:
			if bay_i >= plan.bays.size():
				break
			var bay: Dictionary = plan.bays[bay_i]
			var start: float = FRONT + (k if f[2] else per_row * 2 - 1 - k) * BAY  # the bay's front end
			var row_x: float = x0 + f[0] * ROW_GAP
			var reads := 1.0 if f[2] else -1.0  # which way along z left-to-right is, facing it
			for j in bay.items.size():
				var col: int = j % PER_SHELF
				var z: float = start + BAY / 2.0 + reads * ((col - (PER_SHELF - 1) / 2.0) * PITCH)
				var y: float = SHELVES[j / PER_SHELF] + TAPE.y / 2.0
				var t: Dictionary = bay.items[j].duplicate()
				t.p = Vector3(row_x + f[1] * (UNIT_D / 2.0 - 0.04 + TAPE.z / 2.0), y, z)  # (stood at the boards' front edge, a centimetre proud)
				t.n = Vector3(f[1], 0, 0)
				t.ry = PI / 2.0 * f[1]  # (the cover's +z turned to face the aisle)
				slots.append(t)
			if bay_i == 0 or plan.bays[bay_i - 1].c != bay.c or k == 0:  # a section's sign: where it starts, and again on each face it runs on to
				_sign(bay.c, Vector3(row_x + f[1] * 0.035, UNIT_H + 0.16, start + BAY / 2.0), f[1])
			bay_i += 1
	_room()
	_front()
	_draw_boxes()
	print("store: %d tapes, %d bays, %d rows of %d units, %.1f x %.1f m" % [slots.size(), plan.bays.size(), rows, per_row, width, depth])


func _unit(c: Vector3) -> void:  # a double-sided unit, centred at c on the floor
	_box("wood", c + Vector3(0, UNIT_H / 2.0, 0), Vector3(0.04, UNIT_H, UNIT_L))  # the back panel
	_box("wood", c + Vector3(0, 0.06, 0), Vector3(UNIT_D, 0.12, UNIT_L))  # the plinth
	for e in [-1, 1]:  # the ends
		_box("wood", c + Vector3(0, UNIT_H / 2.0, e * (UNIT_L / 2.0 - 0.015)), Vector3(UNIT_D, UNIT_H, 0.03))
	for y: float in SHELVES:
		_box("board", c + Vector3(0, y - 0.01, 0), Vector3(UNIT_D - 0.04, 0.02, UNIT_L - 0.03))
	_box("trim", c + Vector3(0, UNIT_H + 0.16, 0), Vector3(0.06, 0.3, UNIT_L))  # the header the signs hang on
	_solid(c + Vector3(0, UNIT_H / 2.0, 0), Vector3(UNIT_D - 0.04, UNIT_H, UNIT_L))  # (to the tapes' faces: the crosshair lands on a cover)


func _sign(text: String, at: Vector3, side: float) -> void:
	var l := Label3D.new()
	l.text = text.to_upper()
	l.font_size = 40
	l.pixel_size = 0.0035
	l.outline_size = 0
	l.modulate = Color("#ffe9a8")
	l.position = at
	l.rotation.y = PI / 2.0 * side
	l.width = BAY * 2.0 / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)


func _room() -> void:
	_box("carpet", Vector3(width / 2.0, -0.05, depth / 2.0), Vector3(width, 0.1, depth), true)
	_box("ceiling", Vector3(width / 2.0, CEILING + 0.05, depth / 2.0), Vector3(width, 0.1, depth))
	for w: Array in [[width / 2.0, 0.0, width, 0.2], [width / 2.0, depth, width, 0.2], [0.0, depth / 2.0, 0.2, depth], [width, depth / 2.0, 0.2, depth]]:
		_box("wall", Vector3(w[0], CEILING / 2.0, w[1]), Vector3(w[2], CEILING, w[3]), true)
	var nx := maxi(1, roundi(width / 4.0))
	var nz := maxi(1, roundi(depth / 4.0))
	for i in nx:  # the lights: panels on a grid, a lamp under each
		for j in nz:
			var p := Vector3((i + 0.5) * width / nx, CEILING - 0.02, (j + 0.5) * depth / nz)
			_box("panel", p, Vector3(0.6, 0.03, 1.2))
			var o := OmniLight3D.new()
			o.position = p - Vector3(0, 0.3, 0)
			o.omni_range = 6.5
			o.light_energy = 0.55
			o.light_color = Color("#fff4e0")
			add_child(o)


func _front() -> void:
	_box("tv", Vector3(width / 2.0, 1.1, 0.12), Vector3(1.8, 2.2, 0.06))  # the door (the store's shut)
	_box("counter", Vector3(2.3, 0.5, 3.0), Vector3(3.0, 1.0, 0.7), true)  # the counter, left of the door
	var tv := Vector3(width - 0.45, 0.0, 3.2)  # the TV on its stand against the right wall, facing in (-x)...
	_box("wood", tv + Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 1.4), true)
	_box("tv", tv + Vector3(0, 0.98, 0), Vector3(0.35, 0.76, 1.24), true)
	screens = [{ "x": tv.x - 0.18, "y": tv.y + 0.98, "z": tv.z, "ry": -PI / 2.0, "w": 1.12, "h": 0.66, "reach": 6.0, "kind": "tv" }]
	var couch := Vector3(width - 4.0, 0.0, 3.2)  # ...and the couch facing it
	_box("couch", couch + Vector3(0, 0.22, 0), Vector3(0.9, 0.44, 2.0), true)
	_box("couch", couch + Vector3(-0.38, 0.55, 0), Vector3(0.18, 0.7, 2.0), true)
	for s in [-0.5, 0.5]:
		seats.append({ "kind": "couch", "x": couch.x + 0.05, "y": 0.0, "z": couch.z + s, "ry": PI / 2.0, "hipY": 0.5 })
	var player: Node3D = get_node_or_null("../Player")
	if player != null:
		player.spawn = Vector3(width / 2.0, 0.05, 1.2)
		player.global_position = player.spawn
		player.rotation.y = PI


func _box(mat: String, c: Vector3, size: Vector3, solid := false) -> void:
	_boxes.get_or_add(mat, []).append(Transform3D(Basis.from_scale(size), c))
	if solid:
		_solid(c, size)


func _solid(c: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.position = c
	body.add_child(shape)
	add_child(body)


func _draw_boxes() -> void:
	for mat: String in _boxes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.mesh.material = _mats[mat]
		mm.instance_count = _boxes[mat].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, _boxes[mat][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)
