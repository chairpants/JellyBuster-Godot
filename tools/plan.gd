extends SceneTree
## A plan of the level from straight above, roof and ceilings off, unlit: plan.png
##     godot --path . --resolution 1600x1600 -s tools/plan.gd -- [--cut=y] [--area=x0,z0,x1,z1] [--out]
## (--cut: nothing whose bottom's above this height, default 2.5: the ceilings, the roof, the signs up top)

func _init() -> void:
	var cut := 2.5
	var area := Rect2(-12, -2, 26, 46)  # x, z, width, depth: the building and a bit round it
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cut="):
			cut = a.trim_prefix("--cut=").to_float()
		elif a.begins_with("--area="):
			var v := a.trim_prefix("--area=").split_floats(",")
			area = Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1])
	var w: Node3D = load("res://world/world.scn").instantiate()
	root.add_child(w)
	await process_frame
	if not "--out" in OS.get_cmdline_user_args():
		w.get_node("out").visible = false
	for m: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		if (m.global_transform * m.get_aabb()).position.y > cut:
			m.visible = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(area.size.x, area.size.y)
	cam.far = 200.0
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, 1)), Vector3(area.get_center().x, 50, area.get_center().y))
	cam.current = true
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://plan.png")
	quit()
