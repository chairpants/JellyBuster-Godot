extends Node3D
## The cars going by on the road out front: where ambience.gd has the one you can hear, there it is. A new colour each
## time, wheels turning, headlights and tail-lights (and, after dark, the road lit ahead of it).

const COLOURS := ["#b3262e", "#1c4dbb", "#e8e4d8", "#222428", "#2f6b3a", "#8a8f96", "#c9a227", "#5a2a6e", "#7a4a2a"]
const WHEEL_R := 0.33

var _car := Node3D.new()
var _paint := StandardMaterial3D.new()
var _body: MeshInstance3D
var _wheels: Array[Node3D] = []
var _beam := SpotLight3D.new()
var _pass := {}  # the one being shown (ambience.gd's own dictionary: a new one's a new car)

@onready var amb: Node = $"../Ambience"
@onready var sky: Node = $"../Sky"


func _ready() -> void:
	var glass := _mat(Color("#1d2630"))
	var black := _mat(Color("#141414"))
	var head := _mat(Color("#fff6d8"), 2.0)
	var tail := _mat(Color("#d01818"), 1.2)
	_body = _part(Vector3(4.2, 0.62, 1.74), Vector3(0, 0.55, 0), _paint)  # the body
	_part(Vector3(2.2, 0.55, 1.56), Vector3(-0.25, 1.12, 0), glass)  # the cabin, all window
	_part(Vector3(2.0, 0.06, 1.5), Vector3(-0.25, 1.42, 0), _paint)  # its roof
	for side: float in [-0.62, 0.62]:
		_part(Vector3(0.04, 0.12, 0.3), Vector3(2.1, 0.62, side), head)
		_part(Vector3(0.04, 0.12, 0.3), Vector3(-2.1, 0.66, side), tail)
	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_R
	tyre.bottom_radius = WHEEL_R
	tyre.height = 0.24
	tyre.material = black
	for x: float in [-1.35, 1.35]:
		for z: float in [-0.8, 0.8]:
			var w := Node3D.new()  # (turns about z: its hub)
			w.position = Vector3(x, WHEEL_R, z)
			var mi := MeshInstance3D.new()
			mi.mesh = tyre
			mi.rotation.x = PI / 2.0
			w.add_child(mi)
			_car.add_child(w)
			_wheels.append(w)
	_beam.position = Vector3(2.2, 0.65, 0)
	_beam.basis = Basis.looking_at(Vector3(1, -0.12, 0).normalized())
	_beam.spot_range = 22.0
	_beam.spot_angle = 32.0
	_beam.light_color = Color("#fff3d0")
	_beam.light_energy = 3.0
	_beam.light_specular = 0.0
	_car.add_child(_beam)
	_car.visible = false
	add_child(_car)
	var room := get_node_or_null("../Room")
	if room != null:
		room.light(_car)  # lit as everything else out there is (sun, moon)


func _process(_dt: float) -> void:
	var p: Dictionary = amb.car_pass()
	if p.is_empty():
		_car.visible = false
		_pass = {}
		return
	if not is_same(p, _pass):  # a new one: a new colour
		_pass = p
		var c := Color(COLOURS[randi() % COLOURS.size()])
		var lit := _body.mesh.surface_get_material(0)  # (the room's version of the paint, once room.gd has made it over)
		if lit is ShaderMaterial:
			lit.set_shader_parameter("albedo", c)
		else:
			_paint.albedo_color = c
		_car.visible = true
	var at: Vector3 = amb.car_at()
	_car.position = at
	_car.rotation.y = 0.0 if p.dir > 0.0 else PI  # (nose along +x, going that way)
	var turned: float = -p.v * p.t / WHEEL_R
	for w in _wheels:
		w.rotation.z = turned
	_beam.visible = sky.level < 0.45  # (after dark)


func _part(size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = at
	_car.add_child(mi)
	return mi


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m
