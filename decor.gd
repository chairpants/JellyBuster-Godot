@tool
extends Node3D
## What a store puts up that isn't stock: a bunch of balloons at the counter's end, all year; and through October,
## Halloween: jack-o'-lanterns on the counter (a candle in each, guttering), orange and black bunting along the windows,
## cobwebs up in the sales floor's corners. By the computer's date (--season=halloween, or =none, to see it otherwise).
## All lit by the room's light like the rest (room.gd), but the pumpkins' insides, which glow through their cut faces.
## In the editor too (main.tscn has it), standing still: what's on the counter put down on the level's own triangles, there
## being nothing solid yet (main.gd makes the level solid as the game starts), and lit as it comes.

const COUNTER_Y := 1.1  # the returns counter's top, if nothing's found there (_on_top)
const BALLOONS := { "at": [-2.3, 1.4], "colors": ["#d7262e", "#ffd400", "#1c4dbb", "#d7262e", "#ffd400"], "fall": ["#f26b21", "#111111", "#6c2d91", "#f26b21", "#111111"] }  # x, z on the counter; the colours, and October's
const PUMPKINS := [[-2.0, 3.55, 0.12], [-2.0, 3.2, 0.085]]  # x, z, radius: on the counter's raised front, faces to the store
const BUNTING := { "z": 0.4, "y": 3.25, "x": [-7.5, 10.8], "span": 3.0, "sag": 0.18, "flag": Vector2(0.17, 0.22), "every": 0.24 }
const SHINE := 0.6  # the balloons' gloss (room.gd's: the ceiling's panels in them, a glint of the lamps; a tape's sleeve is 0.3)
const BALLOON := { "r": 0.14, "mid": 0.165, "lift": 1.5, "draught": 0.12, "damp": 1.6 }  # how wide (they meet at their sides), the middle up from the knot; how hard one pulls up, the draught's push, how soon a swing dies away
const KNOT := 0.022  # how far the knot hangs under a balloon
const COBWEB := 0.7  # how far out from its corner a web reaches
const FACE := [  # a jack-o'-lantern's cuts: eyes, nose, a jagged grin (in units of r, from the face's middle, up positive)
	[Vector2(-0.45, 0.25), Vector2(-0.15, 0.25), Vector2(-0.3, 0.5)], [Vector2(0.15, 0.25), Vector2(0.45, 0.25), Vector2(0.3, 0.5)],
	[Vector2(-0.08, 0.02), Vector2(0.08, 0.02), Vector2(0.0, 0.16)],
	[Vector2(-0.5, -0.15), Vector2(-0.25, -0.38), Vector2(-0.25, -0.15)], [Vector2(-0.25, -0.15), Vector2(-0.25, -0.38), Vector2(0.25, -0.38)],
	[Vector2(-0.25, -0.15), Vector2(0.25, -0.38), Vector2(0.25, -0.15)], [Vector2(0.25, -0.15), Vector2(0.25, -0.38), Vector2(0.5, -0.15)],
	[Vector2(-0.12, -0.15), Vector2(0.0, -0.15), Vector2(-0.06, -0.06)]]
const RIND := 0.87  # the inside of the shell, toward its middle: the cuts' walls this deep (~1.5 cm on the big one)

var _bob: Array = []  # [the balloon, how far its middle is from the tie, its phase, its string, where its middle is, how fast it's going, where it was]
var _shiny: Array[MeshInstance3D] = []  # the balloons' skins
var _tie := Vector3.ZERO  # where the strings come together, on the weight
var _candles: Array = []  # [the light out of its face, the glow inside, the shell (its cut edges glowing), the cuts' walls]
var _faces := {}
var _t := 0.0


static func season() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--season="):
			return a.trim_prefix("--season=")
	return "halloween" if Time.get_date_dict_from_system().month == 10 else ""


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)  # (standing still)
	else:
		await get_tree().physics_frame  # (the level's solid by then: main.gd. What stands on the counter is dropped onto it)
		await get_tree().physics_frame
	var fall := season() == "halloween"
	_balloons(BALLOONS.fall if fall else BALLOONS.colors)
	if fall:
		for p: Array in PUMPKINS:
			_pumpkin(_rest(p[0], p[1], p[2] * 0.6), p[2])
		_bunting()
		var level: Node = get_node_or_null("/root/Level")  # (the autoload: as deep as the library made the store. Not there in the editor: one as deep as VaultBuster's, as the editor's level is)
		var own := level == null
		if own:
			level = preload("res://level.gd").new()
		var f: Array = level.data().lights.boxes.floor  # x0, x1, back wall z, ceiling
		if own:
			level.free()
		for c: Array in [[f[0], 0.05, 1, 1], [f[1], 0.05, -1, 1], [f[0], f[2], 1, -1], [f[1], f[2], -1, -1]]:  # [x, z, which way's in along x, along z]
			_cobweb(Vector3(c[0], f[3], c[1]), c[2], c[3])
	var room := get_node_or_null("../Room")
	if room != null and not Engine.is_editor_hint():
		room.light(self)
		for mi in _shiny:
			var m: Material = mi.mesh.surface_get_material(0)
			if m is ShaderMaterial:
				m.set_shader_parameter("shine", SHINE)


func _process(dt: float) -> void:
	_t += dt
	_float(minf(dt, 1.0 / 30.0))
	for c: Array in _candles:  # (guttering: each its own)
		var f := 1.0 + 0.22 * sin(_t * 9.0 + c[0].global_position.z * 10.0) + 0.16 * (randf() - 0.5)
		c[0].light_energy = 0.35 * f
		c[1].albedo_color = Color(f * 1.15, f * 1.15, f * 1.15)  # (over white: the brightest of it blooms a little, room.gd's glow)
		c[3].albedo_color = Color(f, f, f)
		var m: Material = c[2].mesh.surface_get_material(0)
		if m is ShaderMaterial:  # (the room's, by now: room.gd)
			m.set_shader_parameter("emission", Vector3(1.0, 0.45, 0.1) * 0.9 * f)


func _float(dt: float) -> void:  # the bunch: each pulling up on its string, a draught off the door pushing each its own way, and pressed up against
	# each other where they meet (moved apart, the strings pulled taut again, a few times over); leaning along their strings, the strings going with them
	for b: Array in _bob:
		var push := Vector3(sin(_t * 0.7 + b[2]) + 0.5 * sin(_t * 1.9 + b[2] * 3.0), 0.0, cos(_t * 0.6 + b[2]) + 0.5 * cos(_t * 1.7 + b[2] * 2.0)) * BALLOON.draught
		b[5] = (b[5] + (Vector3.UP * BALLOON.lift + push) * dt) * exp(-dt * BALLOON.damp)
		b[6] = b[4]
		b[4] += b[5] * dt
	for k in 4:
		for b: Array in _bob:
			b[4] = _tie + (b[4] - _tie).normalized() * b[1]
		for i in _bob.size():
			for j in range(i + 1, _bob.size()):
				var d: Vector3 = _bob[j][4] - _bob[i][4]
				var gap := d.length() - 2.0 * BALLOON.r
				if gap < 0.0:
					var n := d.normalized() if d.length() > 0.0001 else Vector3.RIGHT
					_bob[i][4] += n * gap * 0.5
					_bob[j][4] -= n * gap * 0.5
	for b: Array in _bob:
		b[4] = _tie + (b[4] - _tie).normalized() * b[1]
		b[5] = (b[4] - b[6]) / maxf(dt, 0.0001)  # (what the pushing apart did, kept as its speed)
		var up: Vector3 = (b[4] - _tie).normalized()
		var lean := Basis(Quaternion(Vector3.UP, up))
		b[0].transform = Transform3D(lean, b[4] - up * BALLOON.mid)
		var knot: Vector3 = b[4] - up * (BALLOON.mid + KNOT)
		b[3].transform = Transform3D(lean.scaled_local(Vector3(1, _tie.distance_to(knot), 1)), (_tie + knot) / 2.0)


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
	if Engine.is_editor_hint():
		return Vector3(x, _top_of_level(x, z), z)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 2.5, z), Vector3(x, 0.0, z)))
	return Vector3(x, hit.position.y if hit else COUNTER_Y, z)


func _top_of_level(x: float, z: float) -> float:  # (the editor's: down onto the level's own triangles, the highest under 2.5 m. Only what's small enough to be furniture: not the building's shell, whose box covers everything)
	var world := get_node_or_null("../World") as Node3D
	var top := -INF
	if world:
		for m: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
			if m.mesh == null:
				continue
			var b := m.global_transform * m.get_aabb()
			if x < b.position.x or x > b.end.x or z < b.position.z or z > b.end.z or b.position.y > 2.5 or b.end.y < 0.3 or b.size.x > 20.0 or b.size.z > 20.0:
				continue
			var faces := m.mesh.get_faces()
			for i in range(0, faces.size(), 3):
				var p = Geometry3D.ray_intersects_triangle(Vector3(x, 2.5, z), Vector3.DOWN, m.global_transform * faces[i], m.global_transform * faces[i + 1], m.global_transform * faces[i + 2])
				if p != null and p.y < 2.5:
					top = maxf(top, p.y)
	return top if top > -INF else COUNTER_Y


func _rest(x: float, z: float, r: float) -> Vector3:  # on the highest of what's under that much round there: the counter steps up under them (a lip, then the raised front)
	var top := _on_top(x, z)
	for i in 8:
		top.y = maxf(top.y, _on_top(x + r * cos(i * TAU / 8.0), z + r * sin(i * TAU / 8.0)).y)
	return top


func _balloons(colors: Array) -> void:
	var tie := _on_top(BALLOONS.at[0], BALLOONS.at[1])
	_tie = tie + Vector3(0, 0.05, 0)
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
		var skin := _mat(Color(colors[i]))
		_shiny.append(_put(s, skin, Transform3D(Basis.IDENTITY, Vector3(0, 0.165, 0)), ball))
		var neck := CylinderMesh.new()  # the knot: the neck pinched in, then the tied-off lip, a little fatter
		neck.top_radius = 0.016
		neck.bottom_radius = 0.006
		neck.height = 0.014
		neck.radial_segments = 12
		_shiny.append(_put(neck, skin, Transform3D(Basis.IDENTITY, Vector3(0, -0.005, 0)), ball))
		var lip := SphereMesh.new()
		lip.radius = 0.009
		lip.height = 0.012
		lip.radial_segments = 12
		lip.rings = 6
		_shiny.append(_put(lip, skin, Transform3D(Basis.IDENTITY, Vector3(0, -0.015, 0)), ball))
		var string := CylinderMesh.new()  # (from the weight to its knot: 1 long, stretched to fit each frame)
		string.top_radius = 0.0015
		string.bottom_radius = 0.0015
		string.height = 1.0
		string.radial_segments = 6
		var mid := top + Vector3(0, BALLOON.mid, 0)
		_bob.append([ball, _tie.distance_to(mid), i * 1.7, _put(string, _mat(Color("#dddddd")), Transform3D.IDENTITY), mid, Vector3.ZERO, mid])
	for k in 300:  # (already settled into a bunch when the store opens)
		_float(1.0 / 60.0)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _pumpkin(at: Vector3, r: float) -> void:  # a hollow one: a ribbed shell, its face cut right through; the candle's glow inside, seen only through the cuts, and on their edges; its light only out the front
	var p := Node3D.new()
	p.position = at
	p.rotation.y = PI / 2  # (its face, +z, to the store: +x)
	add_child(p)
	var pts := _pumpkin_shape(r)
	var lo := INF  # (sat on its lowest point: not sunk into the counter)
	for row: Array in pts:
		for v: Vector3 in row:
			lo = minf(lo, v.y)
	var lift := Vector3(0, -lo, 0)
	var front := SurfaceTool.new()  # what's round the face, textured with the cuts; the rest of it plain
	var rest := SurfaceTool.new()
	var inside := SurfaceTool.new()
	var walls := SurfaceTool.new()
	for st in [front, rest, inside, walls]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := Vector3(0, r * 0.75, 0)  # (the face's middle, the cuts measured from it)
	var flame := Vector3(0, r * 0.35, 0)  # (the candle, low inside)
	var rows := pts.size()
	var cols: int = pts[0].size()
	for i in rows - 1:
		for j in cols:
			var q := [[i, j], [i + 1, j], [i + 1, (j + 1) % cols], [i, j], [i + 1, (j + 1) % cols], [i, (j + 1) % cols]]
			var on_face := q.all(func(k: Array) -> bool: return pts[k[0]][k[1]].z > r * 0.25)
			for k: Array in [q[0], q[2], q[1], q[3], q[5], q[4]]:  # (clockwise from outside)
				var v: Vector3 = pts[k[0]][k[1]]
				var st := front if on_face else rest
				st.set_normal(_pumpkin_normal(pts, k[0], k[1]))
				if on_face:
					st.set_uv(Vector2(0.5 + 0.5 * v.x / r, 0.5 - 0.5 * (v.y - mid.y) / r))
				st.add_vertex(v + lift)
			for k: Array in q:  # the inside: the same, a little smaller, facing in; brightest near the flame
				var v: Vector3 = pts[k[0]][k[1]]
				var w := mid + (v - mid) * RIND
				var near := exp(-w.distance_to(flame) / (r * 0.9))
				inside.set_color(Color(1.0, 0.42 + 0.3 * near, 0.06 + 0.14 * near) * (0.3 + 0.7 * near))
				inside.add_vertex(w + lift)
	for e: Array in _face_edges():  # the cuts' walls: the flesh, lit by the candle, brighter further in
		var n := ceili(e[0].distance_to(e[1]) / 0.06)
		for t in n:
			var o0 := _pumpkin_front(r, e[0].lerp(e[1], float(t) / n) * r + Vector2(0, mid.y))
			var o1 := _pumpkin_front(r, e[0].lerp(e[1], float(t + 1) / n) * r + Vector2(0, mid.y))
			var i0 := mid + (o0 - mid) * RIND
			var i1 := mid + (o1 - mid) * RIND
			for v: Array in [[o0, false], [o1, false], [i1, true], [o0, false], [i1, true], [i0, true]]:
				walls.set_color(Color(1.0, 0.62, 0.22) * 0.75 if v[1] else Color(0.85, 0.42, 0.12) * 0.45)
				walls.add_vertex(v[0] + lift)
	var shell := _mat(Color("#e8761c"))
	var cut := _mat(Color("#e8761c"))
	cut.albedo_texture = _face_texture()
	cut.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cut.emission_enabled = true
	cut.emission = Color(1.0, 0.55, 0.15)
	cut.emission_texture = _face_texture(true)
	var a := front.commit()
	a.surface_set_material(0, cut)
	rest.commit(a)
	a.surface_set_material(1, shell)
	var sm := MeshInstance3D.new()
	sm.mesh = a
	p.add_child(sm)
	var glow := _mat(Color.WHITE, true)
	glow.vertex_color_use_as_albedo = true  # (facing in: through a cut, its far side)
	var flesh := _mat(Color.WHITE, true)
	flesh.vertex_color_use_as_albedo = true
	flesh.cull_mode = BaseMaterial3D.CULL_DISABLED  # (the cuts' walls, from either way)
	var im := MeshInstance3D.new()
	im.mesh = inside.commit()
	walls.commit(im.mesh)
	im.mesh.surface_set_material(0, glow)
	im.mesh.surface_set_material(1, flesh)
	p.add_child(im)
	var top: Vector3 = pts[0][0] + lift
	var stem := CylinderMesh.new()
	stem.top_radius = r * 0.08
	stem.bottom_radius = r * 0.13
	stem.height = r * 0.35
	_put(stem, _mat(Color("#4b5a23")), Transform3D(Basis(Vector3.BACK, 0.2), top + Vector3(0, r * 0.12, 0)), p)
	var candle := SpotLight3D.new()  # (out of the face only: none through the shell)
	candle.light_color = Color(1.0, 0.6, 0.25)
	candle.spot_range = 1.2
	candle.spot_angle = 55.0
	candle.spot_attenuation = 1.2
	candle.light_specular = 0.0
	candle.position = mid + lift + Vector3(0, 0, r * 1.02)
	candle.rotation.y = PI  # (looking out along +z)
	p.add_child(candle)
	_candles.append([candle, glow, sm, flesh])


func _pumpkin_shape(r: float) -> Array:  # rows from the top to the bottom, round from the front: squat, eight ribs, dimpled where the stem goes in and underneath
	var pts := []
	var rows := 18
	var cols := 48
	for i in rows + 1:
		var th := PI * i / rows
		var row := []
		for j in cols:
			var ph := TAU * j / cols
			row.append(_pumpkin_at(r, th, ph))
		pts.append(row)
	return pts


func _pumpkin_at(r: float, th: float, ph: float) -> Vector3:  # down from the top th, round from the front ph
	var k := r * (1.0 - 0.07 * pow(absf(sin(4.0 * ph)), 6.0))  # (the grooves, narrow; a rib down the middle of the face)
	var y := r * 0.75 + r * 0.72 * cos(th) - r * 0.18 * exp(-pow(th / 0.45, 2.0)) + r * 0.1 * exp(-pow((PI - th) / 0.5, 2.0))
	return Vector3(k * sin(th) * sin(ph), y, k * sin(th) * cos(ph))


func _pumpkin_front(r: float, at: Vector2) -> Vector3:  # the point on the front with that x and y (found by a few steps in)
	var th := acos(clampf((at.y - r * 0.75) / (r * 0.72), -1.0, 1.0))
	var ph := 0.0
	for i in 6:
		var p := _pumpkin_at(r, th, ph)
		th = clampf(th + (p.y - at.y) / (r * 0.72 * maxf(sin(th), 0.2)), 0.05, PI - 0.05)
		ph = clampf(ph - (p.x - at.x) / (r * sin(th) * maxf(cos(ph), 0.2)), -1.2, 1.2)
	return _pumpkin_at(r, th, ph)


func _face_edges() -> Array:  # the cuts' outlines: every edge of FACE's triangles, split where another's corner sits on it, but those two triangles share
	var corners := []
	for t: Array in FACE:
		corners.append_array(t)
	var count := {}  # [one end, the other, how many triangles have it], by where it is
	for t: Array in FACE:
		for k in 3:
			var a: Vector2 = t[k]
			var b: Vector2 = t[(k + 1) % 3]
			var cuts := [0.0, 1.0]
			for c: Vector2 in corners:
				var u := (c - a).dot(b - a) / (b - a).length_squared()
				if u > 0.001 and u < 0.999 and c.distance_to(a.lerp(b, u)) < 0.0005:
					cuts.append(u)
			cuts.sort()
			for i in cuts.size() - 1:
				var p := a.lerp(b, cuts[i])
				var q := a.lerp(b, cuts[i + 1])
				var key := str([p.snappedf(0.001), q.snappedf(0.001)] if p < q else [q.snappedf(0.001), p.snappedf(0.001)])
				if not count.has(key):
					count[key] = [p, q, 0]
				count[key][2] += 1
	return count.values().filter(func(e: Array) -> bool: return e[2] == 1)


func _pumpkin_normal(pts: Array, i: int, j: int) -> Vector3:  # across the neighbours, round and down
	var cols: int = pts[0].size()
	var a: Vector3 = pts[maxi(i - 1, 0)][j]
	var b: Vector3 = pts[mini(i + 1, pts.size() - 1)][j]
	var c: Vector3 = pts[i][(j + cols - 1) % cols]
	var d: Vector3 = pts[i][(j + 1) % cols]
	if i == 0:
		return Vector3.UP
	if i == pts.size() - 1:
		return Vector3.DOWN
	return (d - c).cross(a - b).normalized()


func _face_texture(rim := false) -> ImageTexture:  # the cuts, as seen from the front (2r across): clear in the holes; the rim: their edges, glowing
	var key := "rim" if rim else "cut"
	if _faces.has(key):
		return _faces[key]
	const N := 96
	var tris := FACE
	var hole := PackedByteArray()
	hole.resize(N * N)
	for y in N:
		for x in N:
			var pt := Vector2((x + 0.5) / N * 2.0 - 1.0, 1.0 - (y + 0.5) / N * 2.0)
			hole[y * N + x] = 1 if tris.any(func(t: Array) -> bool: return Geometry2D.point_is_inside_triangle(pt, t[0], t[1], t[2])) else 0
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	const EDGE := 3  # (px: the cut edge's thickness, lit)
	for y in N:
		for x in N:
			if not rim:
				img.set_pixel(x, y, Color(1, 1, 1, 0.0 if hole[y * N + x] else 1.0))
				continue
			var d := 99.0
			for dy in range(-EDGE, EDGE + 1):
				for dx in range(-EDGE, EDGE + 1):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < N and yy < N and hole[yy * N + xx]:
						d = minf(d, sqrt(dx * dx + dy * dy))
			var g := 0.0 if d > EDGE else 1.0 - d / (EDGE + 1.0)
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	_faces[key] = ImageTexture.create_from_image(img)
	return _faces[key]


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
