extends Node
## The level (`Level`), made as deep as the library needs. Everything past SEAM (the line between the last of the
## centre's shelf bands and the lounge) slides back by dz: whole things move, and what crosses the line (the side walls,
## the floor and ceiling, the roof, the stripes) stretches, its texture carried on rather than pulled long. Every spot
## the scripts know about goes through here too: data() is data/interact.json with its z's past SEAM moved, and z()
## moves one of their own. store.gd sets dz (layout()) before the store's scene loads.
##
## And out of the level comes what VaultBuster's own shelf layout put in it (store.gd lays out its own): the shelving
## and its tapes, the header strips and endcap tags, the candy rack, the Staff Picks topper.

const SEAM := 20.3
const LAYOUT_TEX := [105, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]  # textures only VaultBuster's layout used (vaultbuster_N): the Staff Picks topper, strips, tags
const SHELF_COLORS := ["ffffff", "eef0f2", "9aa3ad", "1c4dbb"]  # the merged tape bodies, backings, boards, uprights

var dz := 0.0
var _data := {}


func z(v: float) -> float:
	return v + dz if v > SEAM else v


func data() -> Dictionary:  # data/interact.json, moved to fit
	if _data.is_empty():
		_data = _moved(JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")), "")
	return _data


func _moved(v, key: String):
	if v is Dictionary:
		var out := {}
		for k: String in v:
			out[k] = z(v[k]) if k in ["z", "z0", "z1"] and (v[k] is float or v[k] is int) else _moved(v[k], k)
		return out
	if v is Array:
		var nums: bool = v.all(func(e) -> bool: return e is float or e is int)
		if nums and v.size() == 3 and key != "size":  # [x, y, z]
			return [v[0], v[1], z(v[2])]
		if nums and v.size() == 4 and key in ["floor"]:  # [x0, x1, back wall z, ceiling]
			return [v[0], v[1], z(v[2]), v[3]]
		if nums and v.size() == 4 and key in ["boh", "lobby", "theater", "colliders", ""]:  # [x0, x1, z0, z1]
			return [v[0], v[1], z(v[2]), z(v[3])]
		return v.map(func(e) -> Variant: return _moved(e, "" if key == "colliders" else key))
	return v


func strip(world: Node) -> void:  # VaultBuster's layout out of the level
	var store := world.get_node("store")
	var gone := 0
	for m: MeshInstance3D in store.find_children("*", "MeshInstance3D", true, false):
		var b := m.global_transform * m.get_aabb()
		var tex := texture_of(m)
		var n := tex.get_basename().get_slice("_", 1).to_int() if tex.begins_with("vaultbuster_") else -1
		var shelving := b.size.x > 15.0 and b.size.z > 20.0 and b.size.y > 0.5  # (the merged shelves, all over the room; not the floor or ceiling)
		if shelving or n in LAYOUT_TEX or (n >= 133 and n <= 150):
			m.free()
			gone += 1
	for g in store.get_children():
		if g.name.begins_with("group of 3712"):  # the candy rack
			g.free()
			gone += 1
		elif g is MeshInstance3D and String(g.name).begins_with("box 2_50 x 0_50 x 0_06"):  # the Staff Picks topper's board
			g.free()
			gone += 1
	print("level: %d pieces of VaultBuster's layout out" % gone)


static func texture_of(m: MeshInstance3D) -> String:  # its first surface's picture's file name ("" if none): whether or not room.gd has made it over yet
	var mat := m.mesh.surface_get_material(0) if m.mesh and m.mesh.get_surface_count() else null
	var tex: Texture2D = mat.albedo_texture if mat is BaseMaterial3D else mat.get_shader_parameter("tex") if mat is ShaderMaterial else null
	return tex.resource_path.get_file() if tex != null else ""


func stretch(world: Node3D) -> void:  # everything past SEAM back by dz (in the tree: global positions)
	if dz > 0.0:
		for c in world.get_children():
			if c is Node3D:
				_shift(c)
		_tile_ceiling(world.get_node("store"))


func _tile_ceiling(store: Node3D) -> void:  # the light panels over the new floor: the band of them just before SEAM, again and again
	var period := 3.6  # (the panels' rows: data/interact.json's troffers)
	for m: MeshInstance3D in store.find_children("*", "MeshInstance3D", true, false):
		var b := m.global_transform * m.get_aabb()
		if b.position.y < 3.0 or b.size.y > 0.1 or b.end.z <= SEAM - period or b.position.z >= SEAM or b.size.x > 17.0:
			continue  # (up at the ceiling, flat, near the line; not the ceiling itself)
		var xf := m.global_transform
		var band := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var tri: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			var keep := PackedInt32Array()
			for k in range(0, tri.size() - 2, 3):  # whole triangles inside the band
				if [0, 1, 2].all(func(j: int) -> bool: var z := (xf * vs[tri[k + j]]).z; return z >= SEAM - period and z < SEAM):
					keep.append_array([tri[k], tri[k + 1], tri[k + 2]])
			if keep.is_empty():
				continue
			a[Mesh.ARRAY_INDEX] = keep
			band.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			band.surface_set_material(band.get_surface_count() - 1, m.mesh.surface_get_material(s))
		if band.get_surface_count() == 0:
			continue
		for i in floori(dz / period):  # (whole rows: the last before the lounge's may come a little early)
			var copy := MeshInstance3D.new()
			copy.mesh = band
			m.get_parent().add_child(copy)
			copy.global_transform = xf.translated(Vector3(0, 0, (i + 1) * period))


func _shift(n: Node3D) -> void:
	var box := _bounds(n)
	if box.size == Vector3.ZERO and box.position == Vector3.ZERO:  # nothing to see: by where it is
		if n.global_position.z > SEAM:
			n.global_position.z += dz
		return
	if box.position.z > SEAM:
		n.global_position.z += dz
		return
	if box.end.z <= SEAM:
		return
	if n is MeshInstance3D:  # across the line: its far end goes back
		_stretch_mesh(n)
	for c in n.get_children():
		if c is Node3D:
			_shift(c)


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m: MeshInstance3D in ([n] if n is MeshInstance3D else []) + n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _stretch_mesh(m: MeshInstance3D) -> void:
	var xf := m.global_transform
	var inv := xf.affine_inverse()
	var mesh := ArrayMesh.new()
	for s in m.mesh.get_surface_count():
		var a := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		var idx = a[Mesh.ARRAY_INDEX]
		var grad := PackedVector2Array()  # how its texture runs along z at each vertex, from a triangle it's in
		grad.resize(vs.size())
		if uvs != null:
			var tri: PackedInt32Array = idx if idx != null else PackedInt32Array(range(vs.size()))
			var done := {}
			for k in range(0, tri.size() - 2, 3):
				var g := _uv_per_z(xf * vs[tri[k]], xf * vs[tri[k + 1]], xf * vs[tri[k + 2]], uvs[tri[k]], uvs[tri[k + 1]], uvs[tri[k + 2]])
				for j in 3:
					if not done.has(tri[k + j]):
						done[tri[k + j]] = true
						grad[tri[k + j]] = g
		for i in vs.size():
			var w := xf * vs[i]
			if w.z > SEAM:
				vs[i] = inv * (w + Vector3(0, 0, dz))
				if uvs != null:
					uvs[i] += grad[i] * dz
		a[Mesh.ARRAY_VERTEX] = vs
		if uvs != null:
			a[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(s, m.mesh.surface_get_material(s))
	for s in m.get_surface_override_material_count():
		mesh.surface_set_material(s, m.get_surface_override_material(s) if m.get_surface_override_material(s) else mesh.surface_get_material(s))
	m.mesh = mesh


static func _uv_per_z(p0: Vector3, p1: Vector3, p2: Vector3, t0: Vector2, t1: Vector2, t2: Vector2) -> Vector2:  # d(uv)/dz across the triangle's face
	var e1 := p1 - p0
	var e2 := p2 - p0
	var n := e1.cross(e2)
	if n.length_squared() < 1e-12:
		return Vector2.ZERO
	var c := Basis(e1, e2, n).inverse() * Vector3(0, 0, 1)  # z, in the triangle's edges (and its normal, which the texture doesn't follow)
	return (t1 - t0) * c.x + (t2 - t0) * c.y
