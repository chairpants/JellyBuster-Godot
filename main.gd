extends Node3D
## The level (world/world.scn) made solid: everything you can see gets a collision shape of its own triangles. Not the
## doors you walk through (push doors, the storefront's: see interact.gd), and not things too small to bump into.

const SMALL := 1.0  # things no bigger than this corner to corner throw no shadow: over half the level's meshes, each drawn again for every light with shadows, for shadows too small to see

func _enter_tree() -> void:
	var cooler_dz: float = Level.data().things.cooler.get("moved", 0.0)
	for n: Node in $World.find_children("*", "Node3D", true, false):  # the drinks cooler, moved along the wall clear of the counter gate's swing (data/interact.json has it there: cooler.moved)
		if not n is MeshInstance3D and n.get_child_count() > 100 and Vector2(n.position.x + 7.26, n.position.z - 5.25).length() < 0.02:  # (its own position: nothing's in the tree yet to have a global one)
			n.position.z += cooler_dz
	$World.get_node("out/group of 254").free()  # the level's parked car, stood in the lane the passing ones drive down (cars.gd)
	var amb: Node = preload("res://ambience.gd").new()  # the store's sound, there before anything that makes a noise
	amb.name = "Ambience"
	add_child(amb)
	for part: Array in [["Cars", preload("res://cars.gd")], ["Wheel", preload("res://wheel.gd")], ["Picture", preload("res://picture.gd")], ["Save", preload("res://save.gd")], ["MPRIS", preload("res://mpris.gd")], ["Cinema", preload("res://cinema.gd")], ["POS", preload("res://pos.gd")]]:  # the cars going by out front; the time and weather wheel (hold F); the TV's picture menu (P); the media keys; the theater's curtains and pre-show; the register's terminal, last so it has the keys first while you're at it (the balloons and the season's decorations: main.tscn's Decor, there in the editor too)
		var n: Node = part[1].new()
		n.name = part[0]
		add_child(n)


func _ready() -> void:
	var solid := 0
	# the level's collision, kept from the last start (it takes a few seconds to work out): user://, by when the level was last changed
	var stamp := "%d_%d" % [FileAccess.get_modified_time("res://world/world.scn"), roundi(Level.dz * 100.0)]  # (and by how deep it was made: level.gd)
	var cache_path := "user://collision_%s.res" % stamp
	var cache: Resource = ResourceLoader.load(cache_path) if ResourceLoader.exists(cache_path) else null
	var shapes: Dictionary = cache.get_meta("shapes", {}) if cache != null else {}
	var made := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		var size := m.get_aabb().size
		if size.x > 100.0 and m.global_position.y + m.get_aabb().position.y > 8.0:
			m.queue_free()  # the web game's clouds, caught mid-drift by an older export: sky.gd has the real ones
			continue
		if (m.global_transform * m.get_aabb()).size.length() < SMALL:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _walk_through(m) or m.has_meta("walk_through") or m.get_aabb().get_longest_axis_size() < 0.2:  # (walk_through: set in the level, e.g. the theater's seats, whose backs have colliders of their own)
			continue
		var key := str($World.get_path_to(m))
		if shapes.has(key):
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			col.shape = shapes[key]
			body.add_child(col)
			m.add_child(body)
		else:
			m.create_trimesh_collision()
			for b in m.get_children():
				if b is StaticBody3D and b.get_child_count() and b.get_child(0) is CollisionShape3D:
					shapes[key] = b.get_child(0).shape
			made += 1
		solid += 1
	if made > 0:  # (worked out afresh: kept for next time)
		var keep := Resource.new()
		keep.set_meta("shapes", shapes)
		ResourceSaver.save(keep, cache_path)
		for f in DirAccess.get_files_at("user://"):  # (and the ones from an older level go)
			if f.begins_with("collision_") and f != cache_path.get_file():
				DirAccess.remove_absolute("user://" + f)
	print("world: %d meshes solid, %d of them hiding what's behind them" % [solid, _occluders()])


func _occluders() -> int:  # what's behind a wall isn't drawn: the store's back rooms from the sales floor, the outside from them, and so on.
	# Only the solid slabs: walls, floors and ceilings that are one piece (their triangles cover the whole of their box: nothing cut out of them), opaque, and don't move
	get_viewport().use_occlusion_culling = true
	var doors := {}
	for d: Dictionary in $Interact.doors:
		doors[d.pivot] = true
	var n := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		if m.is_queued_for_deletion() or m.mesh == null or _walk_through(m):
			continue
		var up := m.get_parent()
		while up != $World and not doors.has(up):
			up = up.get_parent()
		if up != $World:
			continue  # (a door)
		var b := m.get_aabb()
		var dims := [b.size.x, b.size.y, b.size.z]
		dims.sort()
		if dims[0] > 0.35 or dims[1] < 1.0 or dims[1] * dims[2] < 2.0:
			continue  # (not a slab, or too small to hide much)
		var see_through := false
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is ShaderMaterial and mat.shader and ("blend_mix" in mat.shader.code or "ALPHA =" in mat.shader.code) or mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				see_through = true
		if see_through:
			continue
		var faces := m.mesh.get_faces()
		var area := 0.0
		for i in range(0, faces.size(), 3):
			area += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() / 2.0
		var whole: float = dims[1] * dims[2] * (1.0 if dims[0] < 0.005 else 2.0) + 2.0 * dims[0] * (dims[1] + dims[2])  # (a plane: one face; a box: all six)
		if area < whole * 0.98:
			continue  # (something cut out of it: a window, a doorway)
		var o := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = b.size.max(Vector3.ONE * 0.01)
		o.occluder = box
		o.position = b.get_center()
		m.add_child(o)
		n += 1
	return n


func _walk_through(n: Node) -> bool:
	while n and n != self:
		if n in $Interact.no_collide:
			return true
		n = n.get_parent()
	return false
