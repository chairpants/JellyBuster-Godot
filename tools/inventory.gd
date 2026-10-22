extends SceneTree
## Every mesh in the level whose box meets a region, with its world box and texture, a line each (tab-separated):
##     godot --headless --path . -s tools/inventory.gd -- x0,z0,x1,z1 > list.tsv
## path, x0, x1, y0, y1, z0, z1, texture, material colour

func _init() -> void:
	var v := OS.get_cmdline_user_args()[0].split_floats(",")
	var w: Node3D = load("res://world/world.scn").instantiate()
	root.add_child(w)
	await process_frame
	for m: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var b := m.global_transform * m.get_aabb()
		if b.end.x < v[0] or b.position.x > v[2] or b.end.z < v[1] or b.position.z > v[3]:
			continue
		var mat := m.get_active_material(0)
		var col := ""
		if mat is BaseMaterial3D:
			col = mat.albedo_color.to_html(false)
		print("\t".join([str(w.get_path_to(m)), "%.2f" % b.position.x, "%.2f" % b.end.x, "%.2f" % b.position.y, "%.2f" % b.end.y, "%.2f" % b.position.z, "%.2f" % b.end.z, preload("res://level.gd").texture_of(m), col]))
	quit()
