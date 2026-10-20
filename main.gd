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
	for part: Array in [["Cars", preload("res://cars.gd")], ["Wheel", preload("res://wheel.gd")], ["Picture", preload("res://picture.gd")]]:  # the cars going by out front; the time and weather wheel (hold F); the TV's picture menu (P)
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
	print("world: %d meshes solid" % solid)


func _walk_through(n: Node) -> bool:
	while n and n != self:
		if n in $Interact.no_collide:
			return true
		n = n.get_parent()
	return false
