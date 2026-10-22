extends Node3D
## What a store puts up that isn't stock: a bunch of balloons at the counter's end, all year; and through October,
## Halloween: jack-o'-lanterns on the counter (a candle in each, guttering), orange and black bunting along the windows,
## cobwebs up in the sales floor's corners. By the computer's date (--season=halloween, or =none, to see it otherwise).
## All lit by the room's light like the rest (room.gd), but the pumpkins' carved faces, which glow.

const COUNTER_Y := 1.1  # the returns counter's top, if nothing's found there (_on_top)
const BALLOONS := { "at": [-2.3, 1.4], "colors": ["#d7262e", "#ffd400", "#1c4dbb", "#d7262e", "#ffd400"], "fall": ["#f26b21", "#111111", "#6c2d91", "#f26b21", "#111111"] }  # x, z on the counter; the colours, and October's
const PUMPKINS := [[-2.05, 3.55, 0.12], [-2.05, 3.2, 0.085]]  # x, z, radius: on the counter's raised front, faces to the store
const BUNTING := { "z": 0.4, "y": 3.25, "x": [-7.5, 10.8], "span": 3.0, "sag": 0.18, "flag": Vector2(0.17, 0.22), "every": 0.24 }
const COBWEB := 0.7  # how far out from its corner a web reaches

var _bob: Array = []  # [the balloon, its rest, its phase]
var _candles: Array[OmniLight3D] = []
var _t := 0.0


static func season() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--season="):
			return a.trim_prefix("--season=")
	return "halloween" if Time.get_date_dict_from_system().month == 10 else ""


func _ready() -> void:
	await get_tree().physics_frame  # (the level's solid by then: main.gd. What stands on the counter is dropped onto it)
	await get_tree().physics_frame
	var fall := season() == "halloween"
	_balloons(BALLOONS.fall if fall else BALLOONS.colors)
	if fall:
		for p: Array in PUMPKINS:
			_pumpkin(_on_top(p[0], p[1]), p[2])
		_bunting()
		var f: Array = Level.data().lights.boxes.floor  # x0, x1, back wall z, ceiling
		for c: Array in [[f[0], 0.05, 1, 1], [f[1], 0.05, -1, 1], [f[0], f[2], 1, -1], [f[1], f[2], -1, -1]]:  # [x, z, which way's in along x, along z]
			_cobweb(Vector3(c[0], f[3], c[1]), c[2], c[3])
	var room := get_node_or_null("../Room")
	if room != null:
		room.light(self)


func _process(dt: float) -> void:
	_t += dt
	for b: Array in _bob:  # (a draught off the door: each its own sway)
		b[0].position = b[1] + Vector3(sin(_t * 0.7 + b[2]) * 0.03, sin(_t * 1.1 + b[2] * 2.0) * 0.015, cos(_t * 0.6 + b[2]) * 0.03)
	for c in _candles:
		c.light_energy = 0.5 + 0.12 * sin(_t * 9.0 + c.position.z * 10.0) + 0.08 * randf()


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _put(prim: PrimitiveMesh, m: Material, xf: Transform3D, parent: Node3D = self) -> MeshInstance3D:  # (as an ArrayMesh: the room's light swaps its material, which a primitive won't let it)
	var a := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	a.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = a
	mi.transform = xf
	parent.add_child(mi)
	return mi


func _on_top(x: float, z: float) -> Vector3:  # whatever's there, from above: the counter's top
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 2.5, z), Vector3(x, 0.0, z)))
	return Vector3(x, hit.position.y if hit else COUNTER_Y, z)


func _balloons(colors: Array) -> void:
	var tie := _on_top(BALLOONS.at[0], BALLOONS.at[1])
	_put(_box(Vector3(0.07, 0.05, 0.07)), _mat(Color("#444444")), Transform3D(Basis.IDENTITY, tie + Vector3(0, 0.025, 0)))  # the weight
	for i in colors.size():
		var ang := i * TAU / colors.size() + 0.4
		var top := tie + Vector3(cos(ang) * 0.16, 0.75 + 0.12 * (i % 3), sin(ang) * 0.16)
		var ball := Node3D.new()
		ball.position = top
		add_child(ball)
		var s := SphereMesh.new()
		s.radius = 0.14
		s.height = 0.33
		_put(s, _mat(Color(colors[i])), Transform3D(Basis.IDENTITY, Vector3(0, 0.165, 0)), ball)
		var string := CylinderMesh.new()  # (from the weight to its knot)
		var run := top - tie
		string.top_radius = 0.0015
		string.bottom_radius = 0.0015
		string.height = run.length()
		_put(string, _mat(Color("#dddddd")), Transform3D(Basis(Quaternion(Vector3.UP, run.normalized())), tie + run / 2.0))
		_bob.append([ball, top, i * 1.7])


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _pumpkin(at: Vector3, r: float) -> void:
	var p := Node3D.new()
	p.position = at
	p.rotation.y = PI / 2  # (its face, +z, to the store: +x)
	add_child(p)
	for i in 6:  # the ribs: a few squashed spheres turned about the middle
		var s := SphereMesh.new()
		s.radius = r * 0.62
		s.height = r * 1.5
		var off := Vector3(cos(i * TAU / 6.0), 0, sin(i * TAU / 6.0)) * r * 0.38
		_put(s, _mat(Color("#e8761c")), Transform3D(Basis.IDENTITY, off + Vector3(0, r * 0.72, 0)), p)
	var stem := CylinderMesh.new()
	stem.top_radius = r * 0.08
	stem.bottom_radius = r * 0.13
	stem.height = r * 0.35
	_put(stem, _mat(Color("#4b5a23")), Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0, r * 1.55, 0)), p)
	var glow := _mat(Color(1.0, 0.75, 0.25), true)  # the carved face, lit from inside
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := r * 0.99
	var y := r * 0.72
	for tri: Array in [  # eyes, nose, a jagged grin (in units of r, on the front)
		[Vector2(-0.45, 0.25), Vector2(-0.15, 0.25), Vector2(-0.3, 0.5)], [Vector2(0.15, 0.25), Vector2(0.45, 0.25), Vector2(0.3, 0.5)],
		[Vector2(-0.08, 0.02), Vector2(0.08, 0.02), Vector2(0.0, 0.16)],
		[Vector2(-0.5, -0.15), Vector2(-0.25, -0.38), Vector2(-0.25, -0.15)], [Vector2(-0.25, -0.15), Vector2(-0.25, -0.38), Vector2(0.25, -0.38)],
		[Vector2(-0.25, -0.15), Vector2(0.25, -0.38), Vector2(0.25, -0.15)], [Vector2(0.25, -0.15), Vector2(0.25, -0.38), Vector2(0.5, -0.15)],
		[Vector2(-0.12, -0.15), Vector2(0.0, -0.15), Vector2(-0.06, -0.06)]]:
		for v: Vector2 in [tri[0], tri[2], tri[1]]:  # (clockwise from the front)
			face.add_vertex(Vector3(v.x * r, y + v.y * r, z + 0.002 - (0.2 * absf(v.x) + 0.3 * v.y * v.y) * r))  # (round the pumpkin's curve)
	var fm := MeshInstance3D.new()
	fm.mesh = face.commit()
	fm.material_override = glow
	fm.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.add_child(fm)
	var candle := OmniLight3D.new()
	candle.light_color = Color(1.0, 0.6, 0.25)
	candle.omni_range = 1.4
	candle.light_specular = 0.0
	candle.position = at + Vector3(r * 1.3, r * 0.7, 0)  # (just out in front of the face: inside, the pumpkin would shadow it)
	add_child(candle)
	_candles.append(candle)


func _bunting() -> void:  # pennants on a sagging string along the storefront, inside the glass
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0: float = BUNTING.x[0]
	var x1: float = BUNTING.x[1]
	var flag: Vector2 = BUNTING.flag
	var i := 0
	var x := x0
	while x < x1:
		var y: float = _sag(x)
		st.set_color(Color("#f26b21") if i % 2 == 0 else Color("#111111"))
		for v: Vector3 in [Vector3(x - flag.x / 2.0, y, 0), Vector3(x + flag.x / 2.0, y, 0), Vector3(x, y - flag.y, 0)]:
			st.add_vertex(v + Vector3(0, 0, BUNTING.z))
		x += BUNTING.every
		i += 1
	var m := _mat(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)
	var steps := int((x1 - x0) / 0.1)  # the string: short straight pieces along the sag
	for k in steps:
		var a := Vector3(x0 + k * 0.1, _sag(x0 + k * 0.1), BUNTING.z)
		var b := Vector3(x0 + (k + 1) * 0.1, _sag(x0 + (k + 1) * 0.1), BUNTING.z)
		_put(_box(Vector3(0.1, 0.004, 0.004)), _mat(Color("#cccccc")), Transform3D(Basis(Vector3.BACK, atan2(b.y - a.y, b.x - a.x)), (a + b) / 2.0))


func _sag(x: float) -> float:  # pinned up every span, hanging between
	var t := fposmod(x - BUNTING.x[0], BUNTING.span) / BUNTING.span
	return BUNTING.y - BUNTING.sag * 4.0 * t * (1.0 - t)


func _cobweb(corner: Vector3, ix: float, iz: float) -> void:  # a triangle across the corner where two walls meet the ceiling, a web drawn on it
	var a := corner + Vector3(ix * COBWEB, -0.01, 0.01 * iz)  # along the ceiling, out from one wall
	var b := corner + Vector3(0.01 * ix, -0.01, iz * COBWEB)  # along the ceiling, out from the other
	var c := corner + Vector3(0.01 * ix, -COBWEB * 0.8, 0.01 * iz)  # down the corner
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Array in [[a, Vector2(1, 0)], [b, Vector2(0, 1)], [c, Vector2(0, 0)]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])
	var m := _mat(Color(1, 1, 1, 0.7))
	m.albedo_texture = _web_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


var _web: ImageTexture


func _web_texture() -> ImageTexture:  # spokes out from the corner, and the spiral across them (in the triangle's UVs: the corner at 0, 0)
	if _web:
		return _web
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var line := func(p: Vector2, q: Vector2) -> void:
		var steps := int(p.distance_to(q) * n) + 1
		for k in steps + 1:
			var at := p.lerp(q, float(k) / steps) * (n - 3)
			img.fill_rect(Rect2i(int(at.x), int(at.y), 3, 3), Color(1, 1, 1, 1))  # (3 px: a thread thinner goes in the mipmaps, seen from the floor)
	var spokes: Array[Vector2] = []
	for k in 8:
		var t := (k + 0.5) / 8.0
		spokes.append(Vector2(1.0 - t, t))  # (out to the far edge)
	spokes.push_front(Vector2(1, 0))
	spokes.append(Vector2(0, 1))
	for s in spokes:
		line.call(Vector2.ZERO, s * 0.98)
	for ring in range(1, 9):  # the spiral, a ring at a time, sagging a little between spokes
		var f := ring / 9.0 + 0.02
		for k in spokes.size() - 1:
			var p := spokes[k] * f
			var q := spokes[k + 1] * (f + 0.012)
			line.call(p, (p + q) / 2.0 * 0.96)
			line.call((p + q) / 2.0 * 0.96, q)
	img.generate_mipmaps()
	_web = ImageTexture.create_from_image(img)
	return _web
