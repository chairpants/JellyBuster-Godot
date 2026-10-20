extends Node3D
## The cars going by on the road out front: where ambience.gd has the one you can hear, there it is. Each pass a car of
## the store's day, a sedan, a hatchback, a wagon, a pickup or a minivan, in a new colour: its body drawn from its
## side, sloped glass, pillars, bumpers and hubcaps, wheels turning, headlights and tail-lights (and, after dark, the
## road lit ahead of it).

const COLOURS := ["#b3262e", "#1c4dbb", "#e8e4d8", "#222428", "#2f6b3a", "#8a8f96", "#c9a227", "#5a2a6e", "#7a4a2a", "#3e6f8f", "#a8adb2"]
# each from the side (x forward, y up, metres): the body to the beltline; the cabin's four corners (the foot of the
# windshield, the roof's front and back, the foot of the back window); where the pillars between the windows are (from
# the roof's front to its back, 0..1); the wheels' x and size; how wide; a pickup's bed
const TYPES := {
	"sedan": { "body": [[-2.3, 0.28], [2.3, 0.28], [2.33, 0.5], [2.28, 0.7], [1.05, 0.86], [-1.55, 0.88], [-2.28, 0.84], [-2.33, 0.5]],
		"cabin": [[1.05, 0.86], [0.2, 1.36], [-0.95, 1.36], [-1.55, 0.88]], "pillars": [0.45], "wx": 1.4, "wr": 0.32, "w": 0.86 },
	"hatchback": { "body": [[-1.95, 0.28], [1.95, 0.28], [1.98, 0.5], [1.92, 0.68], [0.95, 0.84], [-1.92, 0.88], [-1.98, 0.5]],
		"cabin": [[0.95, 0.84], [0.15, 1.36], [-1.45, 1.34], [-1.9, 0.88]], "pillars": [0.5], "wx": 1.25, "wr": 0.3, "w": 0.82 },
	"wagon": { "body": [[-2.4, 0.28], [2.4, 0.28], [2.43, 0.5], [2.38, 0.7], [1.15, 0.86], [-2.38, 0.9], [-2.43, 0.5]],
		"cabin": [[1.15, 0.86], [0.3, 1.38], [-2.22, 1.38], [-2.36, 0.9]], "pillars": [0.36, 0.7], "wx": 1.5, "wr": 0.32, "w": 0.88 },
	"pickup": { "body": [[-2.5, 0.34], [2.5, 0.34], [2.53, 0.56], [2.48, 0.82], [1.25, 0.98], [-2.48, 0.98], [-2.53, 0.56]],
		"cabin": [[1.25, 0.98], [0.65, 1.62], [-0.45, 1.62], [-0.52, 0.98]], "pillars": [], "wx": 1.6, "wr": 0.36, "w": 0.9,
		"bed": [-2.38, -0.62] },
	"minivan": { "body": [[-2.35, 0.3], [2.35, 0.3], [2.38, 0.52], [2.3, 0.75], [1.6, 0.92], [-2.32, 0.95], [-2.38, 0.52]],
		"cabin": [[1.6, 0.92], [0.75, 1.62], [-2.18, 1.66], [-2.3, 0.95]], "pillars": [0.3, 0.64], "wx": 1.45, "wr": 0.32, "w": 0.92 },
}

var _cars := {}  # type -> { node, wheels, beam, wr }
var _car: Dictionary  # the one going by
var _paint := StandardMaterial3D.new()
var _lit_paint: Material  # (the room's version of it, once room.gd has made it over: what gets the colour)
var _pass := {}  # the one being shown (ambience.gd's own dictionary: a new one's a new car)

@onready var amb: Node = $"../Ambience"
@onready var sky: Node = $"../Sky"


func _ready() -> void:
	var m := {
		"paint": _paint, "glass": _mat(Color("#1a232c")), "black": _mat(Color("#121212")), "trim": _mat(Color("#2c2e31")),
		"chrome": _mat(Color("#b9bec4")), "head": _mat(Color("#fff6d8"), 2.0), "tail": _mat(Color("#d01818"), 1.2),
		"amber": _mat(Color("#ff9a1a"), 0.8),
	}
	for type: String in TYPES:
		_cars[type] = _build(TYPES[type], m)
	var room := get_node_or_null("../Room")
	if room != null:
		room.light(self)  # lit as everything else out there is (sun, moon)
	for mi: MeshInstance3D in find_children("paint", "MeshInstance3D", true, false):
		_lit_paint = mi.mesh.surface_get_material(0)
		break


func _process(_dt: float) -> void:
	var p: Dictionary = amb.car_pass()
	if p.is_empty():
		if not _car.is_empty():
			_car.node.visible = false
			_car = {}
		_pass = {}
		return
	if not is_same(p, _pass):  # a new one: a new car, a new colour
		_pass = p
		if not _car.is_empty():
			_car.node.visible = false
		_car = _cars[_cars.keys().pick_random()]
		var c := Color(COLOURS.pick_random())
		if _lit_paint is ShaderMaterial:
			_lit_paint.set_shader_parameter("albedo", c)
		else:
			_paint.albedo_color = c
		_car.node.visible = true
	_car.node.position = amb.car_at()
	_car.node.rotation.y = 0.0 if p.dir > 0.0 else PI  # (nose along +x, going that way)
	var turned: float = -p.v * p.t / _car.wr
	for w: Node3D in _car.wheels:
		w.rotation.z = turned
	_car.beam.visible = sky.level < 0.45  # (after dark)


func _build(t: Dictionary, m: Dictionary) -> Dictionary:
	var car := Node3D.new()
	car.visible = false
	add_child(car)
	var w: float = t.w
	var wc := w - 0.1  # (the cabin's a little narrower than the body)
	var body := _poly(t.body)
	var cab := _poly(t.cabin)
	var front := -INF
	var back := INF
	for p in body:
		front = maxf(front, p.x)
		back = minf(back, p.x)
	_part(car, "paint", _extrude(body, -w, w), m.paint)
	_part(car, "paint", _extrude(cab, -wc, wc), m.paint)
	var sides := Geometry2D.offset_polygon(cab, -0.07)  # the side windows: the cabin's shape, in from its edges, out through both sides
	if sides.size():
		var glass: PackedVector2Array = sides[0]
		for i in glass.size():
			glass[i].y = maxf(glass[i].y, cab[0].y + 0.06)
		_part(car, "glass", _extrude(glass, -wc - 0.006, wc + 0.006), m.glass)
	for k in [[cab[0], cab[1]], [cab[2], cab[3]]]:  # the windshield and the back window, just proud of the slopes
		var a: Vector2 = k[0].lerp(k[1], 0.05)
		var b: Vector2 = k[0].lerp(k[1], 0.95)
		var n := (b - a).orthogonal().normalized()
		if n.y < 0.0:
			n = -n
		_part(car, "glass", _extrude(PackedVector2Array([a, b, b + n * 0.012, a + n * 0.012]), -wc + 0.07, wc - 0.07), m.glass)
	for f: float in t.pillars:  # between the side windows
		var x := lerpf(cab[1].x, cab[2].x, f)
		_part(car, "paint", _extrude(_rect(x - 0.05, cab[0].y, x + 0.05, cab[1].y), -wc - 0.012, wc + 0.012), m.paint)
	if t.has("bed"):  # a pickup's: open, its floor down in it
		_part(car, "black", _extrude(_rect(t.bed[0], t.body[4][1] - 0.18, t.bed[1], t.body[4][1] + 0.004), -w + 0.06, w - 0.06), m.black)
	var wheels: Array[Node3D] = []
	var wr: float = t.wr
	for x: float in [-t.wx, t.wx]:
		var arch := PackedVector2Array()  # the wheel arch, dark over the tyre
		for k in 13:
			arch.append(Vector2(x, wr) + Vector2.from_angle(k * PI / 12.0) * (wr + 0.07))
		_part(car, "black", _extrude(arch, -w - 0.004, w + 0.004), m.black)
		for z: float in [-w + 0.1, w - 0.1]:  # (the tyres flush with the body's sides, under their arches)
			var hub := Node3D.new()  # (turns about z: its axle)
			hub.position = Vector3(x, wr, z)
			car.add_child(hub)
			_part(hub, "tyre", _disc(wr, 0.22), m.black)
			_part(hub, "cap", _disc(wr * 0.55, 0.23), m.chrome)
			wheels.append(hub)
	for end: Array in [[front, 1.0], [back, -1.0]]:  # bumpers, lights, the grille
		var x: float = end[0]
		var s: float = end[1]
		_box(car, m.trim, Vector3(x + s * 0.02, 0.38, 0), Vector3(0.14, 0.18, w * 2.0 + 0.04))
		for z: float in [-1.0, 1.0]:
			_box(car, m.head if s > 0.0 else m.tail, Vector3(x - s * 0.02, 0.62, z * (w - 0.22)), Vector3(0.06, 0.13 if s > 0.0 else 0.16, 0.3))
			_box(car, m.amber, Vector3(x - s * 0.03, 0.62, z * (w - 0.04)), Vector3(0.06, 0.1, 0.07))
		if s > 0.0:
			_box(car, m.black, Vector3(x - 0.01, 0.6, 0), Vector3(0.05, 0.14, w * 2.0 - 0.9))
	for z: float in [-1.0, 1.0]:  # the mirrors
		_box(car, m.paint, Vector3(cab[0].x - 0.12, cab[0].y + 0.1, z * (w + 0.06)), Vector3(0.1, 0.1, 0.12))
	var beam := SpotLight3D.new()
	beam.position = Vector3(front + 0.1, 0.65, 0)
	beam.basis = Basis.looking_at(Vector3(1, -0.12, 0).normalized())
	beam.spot_range = 22.0
	beam.spot_angle = 32.0
	beam.light_color = Color("#fff3d0")
	beam.light_energy = 3.0
	beam.light_specular = 0.0
	car.add_child(beam)
	return { "node": car, "wheels": wheels, "beam": beam, "wr": wr }


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in pts:
		out.append(Vector2(p[0], p[1]))
	return out


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _extrude(poly: PackedVector2Array, z0: float, z1: float) -> ArrayMesh:  # a side profile, made solid from z0 to z1 (flat-shaded)
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	if area < 0.0:
		poly.reverse()  # (counter-clockwise from +z: then an edge's outside is to its right)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_tri(st, Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1), Vector3.BACK)
		_tri(st, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(c.x, c.y, z0), Vector3.FORWARD)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		var n := Vector3(d.y, -d.x, 0).normalized()
		_tri(st, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), n)
		_tri(st, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), n)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:  # wound to face n (the engine's front faces go clockwise)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var s := b
		b = c
		c = s
	for v in [a, b, c]:
		st.add_vertex(v)


func _disc(r: float, h: float) -> CylinderMesh:  # (on its side: across the car)
	var d := CylinderMesh.new()
	d.top_radius = r
	d.bottom_radius = r
	d.height = h
	d.radial_segments = 20
	d.rings = 1
	return d


func _part(to: Node3D, nm: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	if mesh is ArrayMesh:
		mesh.surface_set_material(0, mat)
	else:
		mesh.material = mat
	mi.mesh = mesh
	if mesh is CylinderMesh:
		mi.rotation.x = PI / 2.0
	to.add_child(mi, true)
	return mi


func _box(to: Node3D, mat: Material, at: Vector3, size: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	_part(to, "box", b, mat).position = at


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m
