extends RefCounted
## The store as the game built it, saved as a scene to open in the editor and look round: baked/snapshot.scn.
##     godot --path . -- --demo --snapshot [--hour=h]
## Everything the scripts made, the level as stretched, the shelves stocked, the lights where they are, the
## environment as it's set, at that hour. A picture to look at, not a scene to work in: no scripts (nothing in it
## runs, but tools/snapshot_globals.gd putting the room shader's globals back), no collision, no on-screen UI; the
## screens as they were, stills. Edits to it don't go back into the game. Made again whenever it's wanted.

const OUT := "res://baked/snapshot.scn"


static func save(main: Node) -> int:
	main.get_node("World").scene_file_path = ""  # (the level's own nodes in the snapshot, as they are now: moved, stretched, pruned)
	var copy := main.duplicate(Node.DUPLICATE_GROUPS)  # (no scripts: nothing in it runs, and none of theirs starts up making things)
	var kept := _keep(copy, copy)
	copy.set_script(preload("res://tools/snapshot_globals.gd"))
	copy.globals = preload("res://room.gd").globals.duplicate()
	var packed := PackedScene.new()
	var err := packed.pack(copy)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		err = ResourceSaver.save(packed, OUT, ResourceSaver.FLAG_COMPRESS)
	print("snapshot: %d nodes into %s (%s)" % [kept, OUT, error_string(err)])
	copy.free()
	return err


static func _keep(n: Node, root: Node) -> int:  # n and what's under it, owned by root (what's left unowned isn't saved)
	var kept := 0
	for c in n.get_children():
		if c is CollisionObject3D or c is CollisionShape3D or c is CanvasLayer or c is Viewport:
			continue  # (collision; the HUD and menus; the screensaver's viewport)
		c.owner = root
		if c is GeometryInstance3D:
			_still(c)
		kept += 1 + _keep(c, root)
	return kept


static func _still(g: GeometryInstance3D) -> void:  # a screen's picture from a viewport (left out): what it showed, as an image
	var mats: Array[Material] = [g.material_override]
	if g is MeshInstance3D and g.mesh != null:
		for i in g.mesh.get_surface_count():
			mats.append(g.get_surface_override_material(i))
			mats.append(g.mesh.surface_get_material(i))
	for m in mats:
		if m is ShaderMaterial:
			for u in m.shader.get_shader_uniform_list():
				var t = m.get_shader_parameter(u.name)
				if t is ViewportTexture:
					m.set_shader_parameter(u.name, ImageTexture.create_from_image(t.get_image()))
		elif m is BaseMaterial3D and m.albedo_texture is ViewportTexture:
			m.albedo_texture = ImageTexture.create_from_image(m.albedo_texture.get_image())
