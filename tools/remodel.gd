extends SceneTree
## The back of the building reworked, a section at a time, on world/world.scn and data/interact.json in place (git has
## what they were):
##     godot --headless --path . -s tools/remodel.gd -- <section>
##     godot --headless --path . -s tools/remodel.gd -- check    (the data file written back unchanged: the writer's test)
## Each one first keeps the level and its data as they were, in user://remodel/ (dated, by section).
##
## boh: the janitor's closet in off its bump, inside the building's line, at the end of a shorter hall; the hall's way
##   in from the store moved along the back wall toward the middle; the restroom and break room 2 m deeper, the
##   wall between them and the restroom's door moved over to fit. The lobby goes 2 m deeper with them (room for the
##   booth's stairs, later), and the theater back the same.
## theater: the auditorium as wide as the lobby, flush with the store's side wall, a seat more each end of every row;
##   its ceiling up from 3.6 m to 6, the screen and its curtains a fifth bigger, its back wall its own colour all the way
##   down. Over the lobby's back, a projection booth (floor 3 m, ceiling 6; staff only, so grey, on its own light
##   switch), a window in it to watch from and a spinning stool at it; up a walled-in stairwell in the lobby's corner,
##   round a landing, through a door marked for staff; the beam from its port. Outside, the booth and the auditorium
##   one taller block, roofed at 6.4 m, with an iron stair up to it
##   from the store's roof; the back ladder moved off its side to the back of the back of house.
## strip: VaultBuster's shelf layout out of the level for good, as level.gd's strip() takes it out every time the game
##   starts (store.gd lays out its own): in the editor, its wall runs no longer stand across the hall's moved doorway.
## railings: a black iron railing on the step behind each pair of the front row's wheelchair spaces, for the row behind
##   (posts, a mid rail, a round top rail; solid as everything is, main.gd)
## hall: the back hall less bare. A rubber base along its walls; the break room's and the restroom's doors panelled, kick
##   plates both sides, hinges; the ceiling lights framed; an extinguisher on its bracket and its sign; a lit EXIT over the
##   way back to the store; the staff's corkboard between the doors, notices pinned to it
## roof: the store's roof less bare. On the tall block's wall over it: the booth's exhaust louvre, two scuppers off its roof
##   and their downspouts to splash blocks, a wall pack, a disconnect and its conduit; a satellite dish on a ballasted
##   mount; next door's rooftop unit, a plain box, given its louvres, its fan, its rails and its disconnect
## closet: the janitor's closet's mop bucket (a box of boxes) a rolling one, its tub oval and yellow, dirty water in it,
##   the wringer on its end and the press's lever up, on casters; the safety sheets' station on the wall by the shelves
## stairwell: the stairs up to the booth less bare: its walls block, coursed and pointed (laid over them, clear of the door
##   and the way out); the rails on brackets; a grip strip on every tread; BOOTH and the way, stencilled on the landing's wall
## restroom: the floors either side of the wall between the restroom and the break room meeting under it, square (boh
##   moved that wall over, but only the floors' far corners with it: a wedge of the break room's floor in the restroom).
##
## Things are moved the way level.gd moves them past SEAM: a small thing whole, by where its middle is; anything big
## that crosses the edge of what's moving is stretched, its far vertices moved and its texture carried on rather
## than pulled long. What's in data/interact.json goes the same way, by the same regions.

const WHOLE := 2.5  # shorter than this along the way it's moving: a thing, moved whole
const DATA := "res://data/interact.json"
const WORLD := "res://world/world.scn"

var w: Node3D
var data: Dictionary


func _init() -> void:
	var section: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else ""
	var text := FileAccess.get_file_as_string(DATA)
	data = JSON.parse_string(text)
	if section == "check":
		print("data written back unchanged: ", _json(data) == text)
		var f := FileAccess.open("user://remodel_check.json", FileAccess.WRITE)
		f.store_string(_json(data))
		f.close()
		quit()
		return
	w = (load(WORLD) as PackedScene).instantiate()
	root.add_child(w)
	await process_frame
	var done: Array = w.get_meta("remodel", [])
	if section in done:
		push_error("remodel: %s's already been done to this level" % section)
		quit(1)
		return
	match section:
		"boh":
			_boh()
		"theater":
			if not "boh" in done:
				push_error("remodel: theater goes after boh")
				quit(1)
				return
			_theater()
		"hall":
			if not "boh" in done:
				push_error("remodel: hall goes after boh")
				quit(1)
				return
			_hall()
		"roof":
			if not "theater" in done:
				push_error("remodel: roof goes after theater")
				quit(1)
				return
			_roof_v2()
		"closet":
			if not "boh" in done:
				push_error("remodel: closet goes after boh")
				quit(1)
				return
			_closet()
		"stairwell":
			if not "theater" in done:
				push_error("remodel: stairwell goes after theater")
				quit(1)
				return
			_stairwell()
		"railings":
			if not "theater" in done:
				push_error("remodel: railings go after theater")
				quit(1)
				return
			_railings()
		"restroom":
			if not "boh" in done:
				push_error("remodel: restroom goes after boh")
				quit(1)
				return
			_restroom()
		"strip":
			var level: Node = preload("res://level.gd").new()
			level.strip(w)
			level.free()
		_:
			push_error("remodel: no section called '%s'" % section)
			quit(1)
			return
	done.append(section)
	w.set_meta("remodel", done)
	var keep := "user://remodel/%s_%s" % [Time.get_datetime_string_from_system().replace(":", "-"), section]  # (the level and its data as they were, before this: user://remodel/)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://remodel"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(WORLD), ProjectSettings.globalize_path(keep + "_world.scn"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(DATA), ProjectSettings.globalize_path(keep + "_interact.json"))
	print("remodel: what was there kept in %s" % ProjectSettings.globalize_path(keep + "_*"))
	root.remove_child(w)
	var packed := PackedScene.new()
	var err := packed.pack(w)
	if err == OK:
		err = ResourceSaver.save(packed, WORLD, ResourceSaver.FLAG_COMPRESS)  # (as it came: compressed)
	if not section in ["strip", "restroom", "railings", "hall", "roof", "closet", "stairwell"]:  # (the level only: the data's as it was)
		var f := FileAccess.open(DATA, FileAccess.WRITE)
		f.store_string(_json(data))
		f.close()
	print("remodel: %s done, %s" % [section, error_string(err)])
	w.free()
	quit(0 if err == OK else 1)


# ---- the sections

const ROOFS := { "wall": 29.45, "low": 4.0, "high": 6.4, "alu": Color("c9ccd0"), "galv": Color("9da3a8"), "block": Color("8d8f91"), "dark": Color("2b2d30"), "unit": Color("b9bcb5") }


func _roof_v2() -> void:
	var zw: float = ROOFS.wall  # (the tall block's face, over the store's roof)
	var lo: float = ROOFS.low
	var hi: float = ROOFS.high
	var par := "out/roof"
	# the booth's exhaust: an aluminium louvre high on the wall, its blades angled down
	var lv := [0.0, 5.15, 0.9, 0.62]  # middle x, middle y, wide, tall
	block(par, "louvre frame", Vector3(lv[0] - lv[2] / 2.0, lv[1] - lv[3] / 2.0, zw - 0.06), Vector3(lv[0] + lv[2] / 2.0, lv[1] + lv[3] / 2.0, zw), ROOFS.alu)
	block(par, "louvre dark", Vector3(lv[0] - lv[2] / 2.0 + 0.04, lv[1] - lv[3] / 2.0 + 0.04, zw - 0.061), Vector3(lv[0] + lv[2] / 2.0 - 0.04, lv[1] + lv[3] / 2.0 - 0.04, zw - 0.06), ROOFS.dark)
	for k in 7:
		var y: float = lv[1] - lv[3] / 2.0 + 0.08 + k * 0.075
		bar(par, "louvre blade", Vector3(lv[0] - lv[2] / 2.0 + 0.04, y + 0.02, zw - 0.065), Vector3(lv[0] + lv[2] / 2.0 - 0.04, y + 0.02, zw - 0.065), Vector2(0.06, 0.006), ROOFS.alu)
	# the tall roof's drainage: a scupper through the parapet, a collector head, a downspout to a splash block
	for x: float in [-2.6, 1.55]:
		block(par, "scupper", Vector3(x - 0.12, hi - 0.06, zw - 0.18), Vector3(x + 0.12, hi + 0.04, zw), ROOFS.galv)
		block(par, "collector head", Vector3(x - 0.14, hi - 0.4, zw - 0.2), Vector3(x + 0.14, hi - 0.1, zw - 0.02), ROOFS.galv)
		block(par, "downspout", Vector3(x - 0.05, lo + 0.12, zw - 0.14), Vector3(x + 0.05, hi - 0.4, zw - 0.06), ROOFS.galv)
		for y: float in [lo + 0.8, (lo + hi) / 2.0, hi - 0.6]:
			block(par, "downspout strap", Vector3(x - 0.065, y, zw - 0.15), Vector3(x + 0.065, y + 0.03, zw), ROOFS.galv)
		bar(par, "downspout elbow", Vector3(x, lo + 0.17, zw - 0.1), Vector3(x, lo + 0.06, zw - 0.32), Vector2(0.1, 0.1), ROOFS.galv)
		block(par, "splash block", Vector3(x - 0.17, lo, zw - 0.85), Vector3(x + 0.17, lo + 0.05, zw - 0.3), ROOFS.block)
	# a wall pack over the way down the iron stair, and the disconnect for the unit, its conduit down to the roof
	block(par, "wall pack", Vector3(-1.0, 5.85, zw - 0.16), Vector3(-0.72, 6.07, zw), Color("5a4b3a"))
	block(par, "wall pack lens", Vector3(-0.98, 5.84, zw - 0.15), Vector3(-0.74, 5.86, zw - 0.02), Color("f1e3b5"))
	block(par, "disconnect", Vector3(0.75, 4.75, zw - 0.14), Vector3(1.05, 5.15, zw), ROOFS.unit)
	block(par, "disconnect handle", Vector3(1.05, 4.88, zw - 0.1), Vector3(1.08, 5.02, zw - 0.06), Color("c8102e"))
	block(par, "conduit", Vector3(0.88, lo + 0.05, zw - 0.05), Vector3(0.92, 4.75, zw - 0.01), ROOFS.galv)
	block(par, "conduit", Vector3(0.88, lo + 0.05, zw - 1.6), Vector3(0.92, lo + 0.09, zw - 0.01), ROOFS.galv)
	for z: float in [zw - 0.5, zw - 1.1]:
		block(par, "conduit support", Vector3(0.82, lo, z - 0.06), Vector3(0.98, lo + 0.05, z + 0.06), ROOFS.dark)
	# a satellite dish on a ballasted mount: a frame of tube on four blocks, a mast, the dish looking south and up, its feed arm
	var d := Vector3(-6.3, lo, 15.0)  # (by the west parapet: clear of the units, and of the roof's screen)
	for c: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
		block(par, "ballast block", d + Vector3(c.x - 0.2, 0.0, c.y - 0.1), d + Vector3(c.x + 0.2, 0.2, c.y + 0.1), ROOFS.block)
	for e: Array in [[Vector3(-0.5, 0.21, -0.45), Vector3(0.5, 0.21, -0.45)], [Vector3(-0.5, 0.21, 0.45), Vector3(0.5, 0.21, 0.45)], [Vector3(-0.45, 0.21, -0.5), Vector3(-0.45, 0.21, 0.5)], [Vector3(0.45, 0.21, -0.5), Vector3(0.45, 0.21, 0.5)], [Vector3(-0.45, 0.21, -0.45), Vector3(0.45, 0.21, 0.45)], [Vector3(-0.45, 0.21, 0.45), Vector3(0.45, 0.21, -0.45)]]:
		bar(par, "mount frame", d + e[0], d + e[1], Vector2(0.04, 0.04), ROOFS.galv)
	cylinder(par, "dish mast", d + Vector3(0, 0.75, 0), 0.03, 1.1, Vector3.UP, ROOFS.galv)
	var dish := SphereMesh.new()
	dish.radius = 0.42
	dish.height = 0.32
	dish.is_hemisphere = true
	dish.radial_segments = 28
	dish.rings = 8
	var dm := _add(par, "dish", dish)
	var toward := Vector3(0.3, 0.55, -0.78).normalized()  # (the dish's hollow faces where it's aimed: south, and up)
	dm.global_transform = Transform3D(Basis(Quaternion(Vector3.DOWN, toward)), d + Vector3(0, 1.38, 0) - toward * 0.05)
	dm.mesh.surface_set_material(0, _mat(Color("e9eaea")))
	(dm.mesh.surface_get_material(0) as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	bar(par, "dish arm", d + Vector3(0, 1.22, 0), d + Vector3(0, 1.38, 0) + toward * 0.55, Vector2(0.025, 0.025), ROOFS.galv)
	block(par, "lnb", d + Vector3(-0.04, 1.38, -0.04) + toward * 0.55, d + Vector3(0.04, 1.46, 0.04) + toward * 0.55, ROOFS.dark)
	bar(par, "dish cable", d + Vector3(0.03, 0.25, 0.0), d + Vector3(1.6, 0.03, 1.2), Vector2(0.012, 0.012), Color("1d1f22"))
	# next door's unit (a plain box): louvres down its long sides, a fan on top in its guard, rails under it, a disconnect
	var u := _bounds(_node("out/group of 323/box 1_60 x 0_90 x 1_10"))
	for side in [-1, 1]:
		var zf: float = (u.position.z if side < 0 else u.end.z) + side * 0.004
		for k in 9:
			var y: float = u.position.y + 0.12 + k * 0.075
			block("out", "unit louvre", Vector3(u.position.x + 0.1, y, minf(zf, zf + side * 0.012)), Vector3(u.end.x - 0.45, y + 0.035, maxf(zf, zf + side * 0.012)), Color("8f938c"))
		block("out", "unit panel seam", Vector3(u.end.x - 0.42, u.position.y + 0.06, minf(zf, zf + side * 0.006)), Vector3(u.end.x - 0.4, u.end.y - 0.06, maxf(zf, zf + side * 0.006)), Color("8f938c"))
	var top := Vector3(u.get_center().x - 0.25, u.end.y, u.get_center().z)
	cylinder("out", "unit fan shroud", top + Vector3(0, 0.05, 0), 0.38, 0.1, Vector3.UP, Color("8f938c"))
	cylinder("out", "unit fan", top + Vector3(0, 0.07, 0), 0.34, 0.02, Vector3.UP, ROOFS.dark)
	for k in 4:
		var a := k * PI / 4.0
		bar("out", "unit fan guard", top + Vector3(cos(a) * 0.36, 0.11, sin(a) * 0.36), top + Vector3(-cos(a) * 0.36, 0.11, -sin(a) * 0.36), Vector2(0.01, 0.01), ROOFS.galv)
	for zr: float in [u.position.z + 0.1, u.end.z - 0.1]:
		block("out", "unit rail", Vector3(u.position.x - 0.1, u.position.y - 0.08, zr - 0.04), Vector3(u.end.x + 0.1, u.position.y, zr + 0.04), ROOFS.dark)
	block("out", "unit disconnect", Vector3(u.end.x + 0.01, u.position.y + 0.3, u.get_center().z - 0.12), Vector3(u.end.x + 0.12, u.position.y + 0.62, u.get_center().z + 0.12), ROOFS.unit)


func _closet() -> void:
	# the old bucket out (what's wholly in its corner, low down: the mops stood in it stay), the new one in its place
	var gone := _all(R(10.3, 10.99, 29.05, 29.75, -0.1, 0.62), ["out"])
	for m: Node in gone:
		m.free()
	var at := Vector3(10.64, 0.0, 29.4)
	var tub := CylinderMesh.new()
	tub.top_radius = 0.17
	tub.bottom_radius = 0.14
	tub.height = 0.3
	tub.radial_segments = 28
	tub.material = _mat(Color("f2c200"))
	var tm := _add("out", "mop bucket", tub)
	tm.global_transform = Transform3D(Basis.from_scale(Vector3(0.82, 1.0, 1.25)), at + Vector3(0, 0.21, 0))
	var water := CylinderMesh.new()
	water.top_radius = 0.155
	water.bottom_radius = 0.155
	water.height = 0.004
	water.radial_segments = 28
	water.material = _mat(Color("6d6a4f"))
	var wm := _add("out", "mop bucket water", water)
	wm.global_transform = Transform3D(Basis.from_scale(Vector3(0.82, 1.0, 1.25)), at + Vector3(0, 0.3, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.16
	rim.outer_radius = 0.185
	rim.rings = 28
	rim.ring_segments = 6
	rim.material = _mat(Color("e0b000"))
	var rm := _add("out", "mop bucket rim", rim)
	rm.global_transform = Transform3D(Basis.from_scale(Vector3(0.82, 0.6, 1.25)), at + Vector3(0, 0.36, 0))
	for c: Vector2 in [Vector2(-0.12, -0.17), Vector2(0.12, -0.17), Vector2(-0.12, 0.17), Vector2(0.12, 0.17)]:
		block("out", "caster fork", at + Vector3(c.x - 0.015, 0.035, c.y - 0.015), at + Vector3(c.x + 0.015, 0.065, c.y + 0.015), C.iron)
		cylinder("out", "caster", at + Vector3(c.x, 0.028, c.y), 0.028, 0.022, Vector3.RIGHT, Color("1d1f22"))
	var wz := at.z - 0.1  # the wringer, across the tub's front end: its box, the press's lever up
	block("out", "wringer", Vector3(at.x - 0.13, 0.34, wz - 0.1), Vector3(at.x + 0.13, 0.5, wz + 0.06), Color("5b5f64"))
	block("out", "wringer jaws", Vector3(at.x - 0.11, 0.5, wz - 0.06), Vector3(at.x + 0.11, 0.53, wz + 0.02), Color("3a3d41"))
	bar("out", "wringer lever", Vector3(at.x + 0.12, 0.47, wz), Vector3(at.x + 0.12, 1.02, wz + 0.16), Vector2(0.025, 0.025), Color("5b5f64"))
	block("out", "wringer grip", Vector3(at.x + 0.1, 0.98, wz + 0.12), Vector3(at.x + 0.14, 1.08, wz + 0.2), Color("1d1f22"))
	# the safety sheets: a yellow station on the east wall by the shelves, its header, the binder in it
	var x1 := 10.9  # (the east wall's face: where the shelves' backs are)
	var st := [28.45, 28.85, 1.15, 1.6]  # z from, to; y from, to
	block("out", "msds station", Vector3(x1 - 0.1, st[2], st[0]), Vector3(x1, st[3], st[1]), Color("f2c200"))
	block("out", "msds binder", Vector3(x1 - 0.118, st[2] + 0.04, st[0] + 0.07), Vector3(x1 - 0.06, st[3] - 0.11, st[1] - 0.07), Color("1c4dbb"))  # (its spine out of the station's front)
	block("out", "msds binder label", Vector3(x1 - 0.1195, st[2] + 0.12, st[0] + 0.1), Vector3(x1 - 0.118, st[2] + 0.22, st[1] - 0.1), Color("f4f1e8"))
	var head := QuadMesh.new()
	head.size = Vector2(st[1] - st[0], 0.09)
	var lab := StandardMaterial3D.new()
	lab.albedo_texture = ImageTexture.create_from_image(_lettering("MSDS", Color("f6f6f2"), Color("c8102e")))
	head.material = lab
	var hm := _add("out", "msds header", head)
	hm.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(x1 - 0.101, st[3] - 0.05, (st[0] + st[1]) / 2.0))


func _stairwell() -> void:
	var x0: float = SHAFT.x0 + 0.15  # (as _theater has them: the far flight's side; between the flights)
	var mid: float = SHAFT.split
	var cmu := StandardMaterial3D.new()  # the walls: block, two wide and two courses to the picture, tiled over each face
	cmu.albedo_texture = ImageTexture.create_from_image(_blockwork())
	cmu.albedo_color = Color(0.74, 0.75, 0.77)  # (painted grey, as a staff stair is)
	for f: Array in [  # [the face's corner, its other, which way it looks]
			[Vector3(x0, 0, 29.8), Vector3(x0, BOOTH, 34.88), Vector3.RIGHT], [Vector3(x0, BOOTH, SHAFT.top), Vector3(x0, CEIL - 0.1, 34.88), Vector3.RIGHT],
			[Vector3(x0, 0, 34.88), Vector3(1.88, CEIL - 0.1, 34.88), Vector3.BACK * -1.0], [Vector3(1.88, 0, 29.8), Vector3(1.88, CEIL - 0.1, 34.88), Vector3.LEFT], [Vector3(x0, 2.7, 29.8), Vector3(1.88, CEIL - 0.1, 29.8), Vector3.BACK],
			[Vector3(x0, 0, 29.8), Vector3(0.69, 2.7, 29.8), Vector3.BACK], [Vector3(0.69, 2.19, 29.8), Vector3(1.88, 2.7, 29.8), Vector3.BACK],
			[Vector3(mid, 0, 29.8), Vector3(mid, BOOTH + 1.1, SHAFT.turn), Vector3.LEFT], [Vector3(mid + 0.1, 0, 29.8), Vector3(mid + 0.1, BOOTH + 1.1, SHAFT.turn), Vector3.RIGHT]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var n: Vector3 = f[2]
		var along := absf(b.z - a.z) if absf(n.x) > 0.5 else absf(b.x - a.x)
		var tall := b.y - a.y
		var q := QuadMesh.new()
		q.size = Vector2(along, tall)
		var m: StandardMaterial3D = cmu.duplicate()
		m.uv1_scale = Vector3(along / 0.8, tall / 0.4, 1.0)
		q.material = m
		var mi := _add("lobby", "stairwell blockwork", q)
		mi.global_transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), (a + b) / 2.0 + n * 0.003)  # (the quad's face, +z, turned to look out of the wall)
	# the rails, on brackets off the walls
	var rise := BOOTH / 18.0
	var r1 := 1.84
	for rail: Array in [[Vector3(r1, rise + 0.9, SHAFT.top), Vector3(r1, BOOTH / 2.0 + 0.9, SHAFT.turn), Vector3(1.88, 0, 0)],
			[Vector3(x0 + 0.04, BOOTH / 2.0 + rise + 0.9, SHAFT.turn), Vector3(x0 + 0.04, BOOTH + 0.9, SHAFT.top), Vector3(x0, 0, 0)],
			[Vector3(1.86, BOOTH / 2.0 + 0.9, 34.84), Vector3(x0 + 0.02, BOOTH / 2.0 + 0.9, 34.84), Vector3(0, 0, 34.88)]]:
		for t: float in [0.12, 0.5, 0.88]:
			var p: Vector3 = (rail[0] as Vector3).lerp(rail[1], t) - Vector3(0, 0.05, 0)
			var wall: Vector3 = p
			if rail[2].x != 0.0:
				wall.x = rail[2].x
			else:
				wall.z = rail[2].z
			bar("lobby", "rail bracket", wall - Vector3(0, 0.04, 0), p, Vector2(0.015, 0.015), C.iron)
	# a grip strip on every tread, a hand's width back from the nosing
	var run := (SHAFT.turn - SHAFT.top) / 8.0
	for i in 8:
		var z: float = SHAFT.top + i * run
		var y := (i + 1) * rise
		block("lobby", "tread grip", Vector3(mid + 0.15, y, z + 0.05), Vector3(1.83, y + 0.002, z + 0.1), C.nose)
	for j in 8:
		var z: float = SHAFT.turn - (j + 1) * run
		var y := BOOTH / 2.0 + (j + 1) * rise
		block("lobby", "tread grip", Vector3(x0 + 0.05, y, z + run - 0.1), Vector3(mid - 0.05, y + 0.002, z + run - 0.05), C.nose)
	# BOOTH, and the way, stencilled on the landing's wall
	var sign := QuadMesh.new()
	sign.size = Vector2(0.75, 0.16)
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = ImageTexture.create_from_image(_lettering("BOOTH >", Color("f2c200"), Color("3a3d42")))
	sign.material = paint
	var sm := _add("lobby", "stairwell sign", sign)
	sm.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.55, BOOTH / 2.0 + 1.0, 34.875))


static func _blockwork() -> Image:  # concrete block, 40 by 20, half-bond: two blocks across and two courses up the picture, the joints recessed and darker
	const W := 256
	const H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in H:
		for x in W:
			var course := y / 64
			var xs := (x + (64 if course % 2 == 1 else 0)) % W
			var joint := y % 64 < 3 or xs % 128 < 3
			var g := 0.6 + rng.randf_range(-0.04, 0.04) + 0.02 * sin(x * 0.31 + y * 0.17)
			if joint:
				g = 0.46 + rng.randf_range(-0.02, 0.02)
			img.set_pixel(x, y, Color(g * 0.98, g, g * 1.04))
	img.generate_mipmaps()
	return img


const HALL := { "x": [2.0, 9.4], "z": [28.1, 29.7], "base": Color("2e2f31"), "door": Color("d4d6d8"), "trim": Color("bfc3c7"), "steel": Color("b8bcc0"), "cork": Color("b0875a"), "red": Color("c8102e") }


func _hall() -> void:
	var z0: float = HALL.z[0]  # (the south wall's face, the store side; the north wall's, the rooms')
	var z1: float = HALL.z[1]
	# the base: dark rubber, 10 cm, along each wall but its doorways
	for r: Array in [[2.0, 3.64, z0, 1], [5.56, 9.3, z0, 1], [2.0, 4.39, z1, -1], [5.61, 7.94, z1, -1], [9.16, 9.3, z1, -1]]:
		block("boh", "hall base", Vector3(r[0], 0.0, minf(r[2], r[2] + r[3] * 0.012)), Vector3(r[1], 0.1, maxf(r[2], r[2] + r[3] * 0.012)), HALL.base)
	for r: Array in [[2.03, 28.0, 28.44, 1], [2.03, 29.37, 29.8, 1], [9.3, 28.1, 28.44, -1], [9.3, 29.36, 29.7, -1]]:
		block("boh", "hall base", Vector3(minf(r[0], r[0] + r[3] * 0.012), 0.0, r[1]), Vector3(maxf(r[0], r[0] + r[3] * 0.012), 0.1, r[2]), HALL.base)
	# the two doors off it: moulded panels each face, a kick plate each side, three hinges (on the door, so they swing with it)
	for d: Array in [["boh/group of 66", 5.0, 1.0], ["boh/group of 69", 8.55, 1.0]]:  # [the door's group, its middle, which way its hinges are]
		var x: float = d[1]
		for face in [-1, 1]:
			var zf: float = 29.8 + face * 0.02
			var out := Vector3(0, 0, face * 0.008)
			for pnl: Array in [[0.36, 0.95], [1.14, 1.92]]:  # (each panel: a moulding round it)
				for e: Array in [[x - 0.4, pnl[0], x + 0.4, pnl[0] + 0.025], [x - 0.4, pnl[1] - 0.025, x + 0.4, pnl[1]], [x - 0.4, pnl[0], x - 0.375, pnl[1]], [x + 0.375, pnl[0], x + 0.4, pnl[1]]]:
					var a := Vector3(e[0], e[1], zf)
					var b := Vector3(e[2], e[3], zf) + out
					block(d[0], "door moulding", a.min(b), a.max(b), HALL.trim)
			var ka := Vector3(x - 0.5, 0.02, zf)
			var kb := Vector3(x + 0.5, 0.27, zf + face * 0.002)
			block(d[0], "kick plate", ka.min(kb), ka.max(kb), HALL.steel)
		for y in [0.25, 1.05, 1.85]:
			cylinder(d[0], "hinge", Vector3(x + d[2] * 0.535, y, 29.8 - 0.024), 0.011, 0.1, Vector3.UP, HALL.steel)
	# the ceiling lights: an aluminium frame round each
	for c: float in [4.5, 8.1]:
		for e: Array in [[c - 0.92, 28.44, c + 0.92, 28.47], [c - 0.92, 29.33, c + 0.92, 29.36], [c - 0.92, 28.44, c - 0.89, 29.36], [c + 0.89, 28.44, c + 0.92, 29.36]]:
			block("boh", "light frame", Vector3(e[0], 2.66, e[1]), Vector3(e[2], 2.7, e[3]), Color("dfe1e3"))
	# an extinguisher on its bracket, by the closet; its sign over it
	var ex := Vector3(8.75, 0.0, z0 + 0.09)
	block("boh", "extinguisher bracket", Vector3(ex.x - 0.04, 0.95, z0), Vector3(ex.x + 0.04, 1.3, z0 + 0.012), C.iron)
	cylinder("boh", "extinguisher", Vector3(ex.x, 1.12, ex.z), 0.075, 0.42, Vector3.UP, HALL.red)
	cylinder("boh", "extinguisher neck", Vector3(ex.x, 1.36, ex.z), 0.028, 0.06, Vector3.UP, Color("1d1f22"))
	block("boh", "extinguisher handle", Vector3(ex.x - 0.07, 1.39, ex.z - 0.012), Vector3(ex.x + 0.05, 1.405, ex.z + 0.012), C.iron)
	bar("boh", "extinguisher hose", Vector3(ex.x + 0.03, 1.37, ex.z + 0.02), Vector3(ex.x + 0.085, 0.98, ex.z + 0.03), Vector2(0.018, 0.018), Color("1d1f22"))
	block("boh", "extinguisher sign", Vector3(ex.x - 0.1, 1.55, z0), Vector3(ex.x + 0.1, 1.8, z0 + 0.006), HALL.red)
	block("boh", "extinguisher sign arrow", Vector3(ex.x - 0.03, 1.58, z0 + 0.006), Vector3(ex.x + 0.03, 1.66, z0 + 0.008), Color.WHITE)
	# EXIT, lit, over the way back to the store
	block("boh", "exit sign", Vector3(4.44, 2.34, z0), Vector3(4.76, 2.5, z0 + 0.05), Color("f2f2ee"))
	var face := QuadMesh.new()
	face.size = Vector2(0.3, 0.14)
	var tex := ImageTexture.create_from_image(_lettering("EXIT", Color("d0101a"), Color("f6f6f2")))
	var lit := StandardMaterial3D.new()
	lit.albedo_texture = tex
	lit.emission_enabled = true
	lit.emission_texture = tex
	lit.emission = Color(1.0, 0.25, 0.2)
	lit.emission_energy_multiplier = 0.6
	face.material = lit
	var fm := _add("boh", "exit sign face", face)
	fm.global_position = Vector3(4.6, 2.42, z0 + 0.0505)
	# the staff's corkboard between the doors: a wooden frame, notices pinned up
	var cb := [6.05, 7.45, 1.0, 1.72]
	block("boh", "corkboard", Vector3(cb[0], cb[2], z1 - 0.02), Vector3(cb[1], cb[3], z1), HALL.cork)
	for e: Array in [[cb[0] - 0.03, cb[2] - 0.03, cb[1] + 0.03, cb[2]], [cb[0] - 0.03, cb[3], cb[1] + 0.03, cb[3] + 0.03], [cb[0] - 0.03, cb[2], cb[0], cb[3]], [cb[1], cb[2], cb[1] + 0.03, cb[3]]]:
		block("boh", "corkboard frame", Vector3(e[0], e[1], z1 - 0.03), Vector3(e[2], e[3], z1), C.wood)
	var notes := [[6.15, 1.38, 0.21, 0.28, Color("f4f1e8")], [6.45, 1.12, 0.21, 0.28, Color("fdf3a7")], [6.75, 1.4, 0.18, 0.22, Color("f7c9d4")], [7.0, 1.08, 0.3, 0.2, Color("f4f1e8")], [7.05, 1.38, 0.24, 0.3, Color("cfe6f7")]]
	for n: Array in notes:  # [left, bottom, wide, tall, colour]
		block("boh", "notice", Vector3(n[0], n[1], z1 - 0.023), Vector3(n[0] + n[2], n[1] + n[3], z1 - 0.02), n[4])
		cylinder("boh", "pin", Vector3(n[0] + n[2] / 2.0, n[1] + n[3] - 0.03, z1 - 0.027), 0.007, 0.012, Vector3.BACK, Color("d7262e"))
		for k in 3:  # (a few lines of writing on it)
			block("boh", "notice writing", Vector3(n[0] + 0.03, n[1] + n[3] - 0.08 - k * 0.04, z1 - 0.0235), Vector3(n[0] + n[2] - 0.04 - k * 0.02, n[1] + n[3] - 0.07 - k * 0.04, z1 - 0.0234), Color("4a4e57"))


static func _lettering(text: String, ink: Color, paper: Color) -> Image:  # capitals, five by seven, drawn big on a sign's face (for what's lit: the room's light won't be on them)
	const GLYPHS := { "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
		"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"], "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
		"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"], "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		">": ["01000", "00100", "00010", "00001", "00010", "00100", "01000"] }
	const PX := 8
	var w := text.length() * 6 * PX + 2 * PX
	var img := Image.create(w, 11 * PX, false, Image.FORMAT_RGB8)
	img.fill(paper)
	for i in text.length():
		var g: Array = GLYPHS.get(text[i], [])
		for row in g.size():
			for col in 5:
				if g[row][col] == "1":
					img.fill_rect(Rect2i(PX + i * 6 * PX + col * PX, 2 * PX + row * PX, PX, PX), ink)
	img.generate_mipmaps()
	return img


func _railings() -> void:  # along the front of the step the row behind sits on (its top, and its edge: felt for along it, before)
	const TOP := -1.3
	const AT := 43.08
	const BLACK := Color("151617")
	for xs: Array in [[-6.0, -4.15], [-0.35, 1.85]]:  # (the wheelchair spaces' ends: _theater's)
		var n := ceili((xs[1] - xs[0]) / 1.0)
		for i in n + 1:
			var x: float = lerpf(xs[0], xs[1], float(i) / n)
			block("theater", "railing post", Vector3(x - 0.02, TOP, AT - 0.02), Vector3(x + 0.02, TOP + 0.8, AT + 0.02), BLACK)
			block("theater", "railing foot", Vector3(x - 0.05, TOP, AT - 0.05), Vector3(x + 0.05, TOP + 0.008, AT + 0.05), BLACK)
		block("theater", "railing mid rail", Vector3(xs[0], TOP + 0.3875, AT - 0.0125), Vector3(xs[1], TOP + 0.4125, AT + 0.0125), BLACK)
		cylinder("theater", "railing top rail", Vector3((xs[0] + xs[1]) / 2.0, TOP + 0.8, AT), 0.022, xs[1] - xs[0] + 0.04, Vector3.RIGHT, BLACK)


func _restroom() -> void:  # each floor's corner by the hall, still where the wall was, over to where it is (its texture carried on)
	var wall := _bounds(_node("boh/box 0_20 x 2_70 x 3_20"))
	var x := wall.get_center().x
	for path in ["boh/plane 6_30 x 3_20 x 0_00", "boh/plane 2_70 x 3_20 x 0_00"]:
		var m: MeshInstance3D = _node(path)
		var a := m.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var to_local := m.global_transform.affine_inverse()
		for i in vs.size():
			var g := m.global_transform * vs[i]
			if absf(g.x - x) < 0.01 or absf(g.x - x) > 0.7 or g.z > wall.get_center().z:
				continue  # (already under it; the far wall; the far end, moved already)
			var j := -1  # its neighbour along x on the same edge, to carry the texture on from
			for k in vs.size():
				if k != i and absf((m.global_transform * vs[k]).z - g.z) < 0.01:
					j = k
			var gj := m.global_transform * vs[j]
			var per := (uvs[i] - uvs[j]) / (g.x - gj.x)
			uvs[i] += per * (x - g.x)
			vs[i] = to_local * Vector3(x, g.y, g.z)
		a[Mesh.ARRAY_VERTEX] = vs
		a[Mesh.ARRAY_TEX_UV] = uvs
		var mat := m.mesh.surface_get_material(0)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(0, mat)
		m.mesh = mesh


func _boh() -> void:
	# The closet's bump, outside: its walls and roof edge go (the building's own carry on over where it was), and the
	# closet's own front and back walls, which would only sit in the store's back wall and the hall's once it's in.
	for n in _all(R(10.9, 13.0, 27.6, 30.2), ["out/group of 68/", "out/roof/box "]):
		n.free()
	for p in ["out/box 1_70 x 2_70 x 0_20", "out/box 1_70 x 2_70 x 0_202", "out/box 0_20 x 2_70 x 1_80"]:
		_node(p).free()

	# Everything past the line behind the break room's table and in front of its counters goes back 2 m: the rooms,
	# the lobby and the theater all deeper by that, and the lot behind with them.
	move(R(-12.5, 17.5, 32.17, 60.0), Vector3(0, 0, 2))

	# The hall's way in from the store, along the back wall to beside the lounge (before the closet's in: it'd be in the way).
	move(R(8.7, 10.7, 27.8, 28.2), Vector3(-5.1, 0, 0), false)
	extend("between_rooms/box 16_64 x 3_60 x 0_20", Vector3.AXIS_X, 1, 3.7)
	extend("between_rooms/box 0_50 x 3_60 x 0_20", Vector3.AXIS_X, -1, 5.5)
	_node("store/group of 518").global_position.x += 1.95  # the poster frames over the back wall's shelves, over where they are now
	_node("store/group of 519").global_position.x += 2.25

	# The wall between the break room and the restroom, 0.5 m over (the restroom's door has to fit beside the closet).
	_node("boh/plane 0_66 x 1_05 x 0_00").free()  # (the restroom's tiling, between its door and that wall: under the door now)
	_node("boh/box 0_66 x 0_06 x 0_01").free()
	move(R(7.5, 9.0, 29.89, 36.0), Vector3(-0.5, 0, 0))

	# The restroom's door 1.1 m along, the hall wall closing up behind it.
	move(R(9.0, 10.3, 29.6, 30.0), Vector3(-1.1, 0, 0), false)
	extend("boh/box 3_55 x 2_70 x 0_20", Vector3.AXIS_X, 1, 8.0)
	extend("boh/box 0_80 x 2_70 x 0_20", Vector3.AXIS_X, -1, 9.1)
	extend("boh/plane 0_66 x 1_05 x 0_002", Vector3.AXIS_X, -1, 9.16)
	extend("boh/box 0_66 x 0_06 x 0_012", Vector3.AXIS_X, -1, 9.16)
	# Its light switch, off the hall wall (the door's where it was) onto that side wall, just inside, facing the room.
	var sw := _node("boh/group of 3189")
	var was := _bounds(sw)
	sw.rotate_y(PI / 2.0)
	sw.global_position += Vector3(7.9 + was.size.z / 2.0, was.get_center().y, 30.35) - _bounds(sw).get_center()
	for s: Dictionary in data.lights.switches:
		if s.zone == "restroom":
			s.p = [7.909, s.p[1], 30.35]

	# The closet in: its door, and the bit of wall beside it, from the building's side wall to a new one across the
	# hall's end; and the closet itself, all it holds, its hatch and ladder up to the roof.
	move(R(10.87, 11.3, 28.05, 30.2, -1.0, 3.0), Vector3(-1.6, 0, 0), false)
	move(R(11.3, 13.2, 27.6, 30.2), Vector3(-1.6, 0, 0))  # (the roof and the ground, cut round the bump, close up)
	for p in ["boh/plane 9_00 x 1_80 x 0_00", "boh/plane 9_00 x 1_80 x 0_002"]:  # the hall's floor and ceiling stop at the closet's
		extend(p, Vector3.AXIS_X, 1, 9.4)
	var filler := _node("between_rooms/box 0_20 x 2_70 x 0_50").duplicate()  # the new wall, the other side of its door
	_node("between_rooms").add_child(filler)
	filler.owner = w
	filler.global_position = _node("between_rooms/box 0_20 x 2_70 x 0_50").global_position + Vector3(0, 0, 1.3)
	extend("between_rooms/box 0_20 x 2_70 x 3_80", Vector3.AXIS_Z, -1, 28.0)  # the side wall, on along where the closet's door was
	extend("out/group of 68/box 3_50 x 4_91 x 0_15", Vector3.AXIS_Z, -1, 28.05)  # outside: the cladding, the plinth, the parapet and its cap
	extend("out/group of 68/box 3_56 x 0_50 x 0_16", Vector3.AXIS_Z, -1, 28.08)
	extend("out/roof/box 3_20 x 0_91 x 0_20", Vector3.AXIS_Z, -1, 27.9)
	extend("out/roof/box 3_52 x 0_05 x 0_40", Vector3.AXIS_Z, -1, 28.06)

	# The rooms' ceiling lights, over the middle of them again.
	move(R(3.0, 11.0, 30.5, 31.6, 2.6, 2.8), Vector3(0, 0, 1.35))

	var b: Dictionary = data.lights.boxes
	b.boh = [2, 11.05, 29.8, 35.05]  # (it took in the closet's bump: 12.65)
	b.bohSplit = [7.8, 2.7, 9.4]  # break room | restroom x, ceiling, closet | hall x
	data.nav.x1 = 11.1


const UP := 2.4  # the tall block's roof over the store's: 4 m to 6.4
const CEIL := 6.0  # the auditorium's ceiling, and the booth's
const BOOTH := 3.0  # the booth's floor
const SCREEN_K := 1.2  # the screen, its frame and the opening round it, this much bigger
const DOOR_X0 := -7.4  # the theater's door, from here 1.1 m along the wall: at the far end, by the store's side (it was in the middle, from -3.42)
const PORT_Y := 4.2  # the projector's port, in the wall between booth and auditorium (was 2.25)
const SHAFT := { "x0": -0.65, "z0": 29.65, "split": 0.65, "top": 30.9, "turn": 33.14 }  # the stairwell: its side wall's outside, its front wall's; between the flights; where they start (from the door's landing) and turn (the landing at the back)
const IRON := { "x0": -5.6, "z0": 28.6, "z1": 29.4, "n": 11, "run": 0.27, "land": -6.6 }  # outside, up the tall block's front from the store's roof: from its top tread, toward +x; the landing back to land
const C := { "iron": Color("2a2c2f"), "metal": Color("a9aeb3"), "proj": Color("3c4048"), "wood": Color("6e4c2a"),
	"block": Color("5a5f66"), "paint": Color("e8ecf2"), "port": Color("17181b"), "floor": Color("34373b"), "ceil": Color("26282b"), "tread": Color("55595e"), "nose": Color("1d1f22") }  # (staff only, back here: not the lobby's colours)

func _theater() -> void:
	var shell := ["theater", "out/group of 68", "out/roof", "between_rooms/box 8_20 x 0_90 x 0_20"]
	# The old roof's surface (a new one's laid at the end, at two heights), the jog where the lobby was wider than the
	# theater, and the ground the theater's about to stand on.
	var gravel := []
	for p in ["out/roof/shape 20_54 x 46_70 x 0_00", "out/roof/shape 20_54 x 46_70 x 0_002"]:
		var m: MeshInstance3D = _node(p)
		gravel.append([m.mesh.surface_get_material(0), (m.global_transform * m.get_aabb()).position.y - 4.0, _faces_up(m)])
		m.free()
	for p in ["out/group of 68/box 1_07 x 4_91 x 0_15", "out/group of 68/box 1_13 x 0_50 x 0_16", "out/roof/box 0_77 x 0_91 x 0_20", "out/roof/box 1_09 x 0_05 x 0_40", "out/plane 0_77 x 13_50 x 0_00", "out/plane 0_77 x 13_50 x 0_002"]:
		_node(p).free()

	# Wider, by 0.77 m each side: the walls out to the lobby's line, flush with the store's outside; what's between stretched.
	move(R(-7.5, -5.45, 34.85, 49.0), Vector3(-0.77, 0, 0), true, shell)
	move(R(-0.3, 2.6, 34.85, 49.0), Vector3(0.77, 0, 0), true, shell)
	for p in ["out/plane 9_77 x 13_50 x 0_00", "out/plane 9_77 x 4_00 x 0_00", "out/plane 4_00 x 13_50 x 0_00"]:  # the ground beside it, up to its new side
		extend(p, Vector3.AXIS_X, -1, 2.25)
	extend("out/group of 68/box 10_07 x 4_91 x 0_15", Vector3.AXIS_X, -1, 2.25)  # the back of house's back wall, outside, meets it
	extend("out/group of 68/box 10_13 x 0_50 x 0_16", Vector3.AXIS_X, -1, 2.25)
	# A seat more at each end of every row: the end seats again, the rows' steps and their lights out to them, the aisles
	# as wide as they were.
	for p in ["theater/mesh 6_74 x 1_90 x 6_71", "theater/mesh 6_94 x 2_40 x 7_21", "theater/mesh 6_95 x 1_34 x 6_90"]:
		_copy_column(_node(p), -5.40, -4.72, -0.62)
		_copy_column(_node(p), -1.02, -0.34, 0.62)
	for n: MeshInstance3D in _all(R(-5.42, -0.32, 36.0, 47.0), ["theater/box 3_32 "]):
		_extend(n, Vector3.AXIS_X, -1, -6.03)
		_extend(n, Vector3.AXIS_X, 1, 0.29)
	for n: MeshInstance3D in _all(R(-5.42, -5.32, 36.0, 47.0), ["theater/box 0_08 x 0_02"]):
		n.global_position.x -= 0.62
	for n: MeshInstance3D in _all(R(-0.42, -0.32, 36.0, 47.0), ["theater/box 0_08 x 0_02"]):
		n.global_position.x += 0.62
	for c: CollisionShape3D in _node("theater/seat backs").get_children():
		var sh: BoxShape3D = c.shape.duplicate()
		sh.size.x += 1.24
		c.shape = sh
	for p in ["theater/box 1_56 x 0_04 x 7_95", "theater/extrude 1_56 x 1_57 x 7_80"]:
		fit(_node(p), Vector3(-7.64, -INF, -INF), Vector3(-6.03, INF, INF))
	var rows := {}
	for s: Dictionary in data.seats:
		if s.kind == "theater":
			rows[s.z] = s
	for z in rows:
		for x in [-5.66, -0.08]:
			var s: Dictionary = rows[z].duplicate()
			s.x = x
			data.seats.append(s)
	# The seats on to the far wall on the left (looking at the screen): two more a row where that aisle was; the one
	# aisle left on the right, where the door now comes in.
	for p in ["theater/@MeshInstance3D@4", "theater/@MeshInstance3D@5"]:
		_node(p).free()
	for p in ["theater/mesh 6_74 x 1_90 x 6_71", "theater/mesh 6_94 x 2_40 x 7_21", "theater/mesh 6_95 x 1_34 x 6_90"]:
		_copy_column(_node(p), -1.02, -0.34, 1.24)
		_copy_column(_node(p), -1.02, -0.34, 1.86)
	for n: MeshInstance3D in _all(R(-6.05, 0.31, 36.0, 47.0), ["theater/box 3_32 "]):
		_extend(n, Vector3.AXIS_X, 1, 1.9)
	for n: MeshInstance3D in _all(R(0.2, 0.4, 36.0, 47.0), ["theater/box 0_08 x 0_02"]):  # (that aisle's step edges)
		n.free()
	for c: CollisionShape3D in _node("theater/seat backs").get_children():
		c.shape.size.x += 1.61
		c.position.x += 0.805
	for z in rows:
		for x in [0.54, 1.16]:
			var s: Dictionary = rows[z].duplicate()
			s.x = x
			data.seats.append(s)

	# Taller: the ceiling up 2.4 m, the walls up to it; outside, the walls, parapets and what's on the roof up as much.
	# (First the store's side wall outside stops where the tall block starts, so it isn't caught up in it.)
	extend("out/group of 68/box 33_50 x 4_91 x 0_15", Vector3.AXIS_Z, 1, 29.45)
	extend("out/group of 68/box 33_56 x 0_50 x 0_16", Vector3.AXIS_Z, 1, 29.45)
	extend("out/roof/box 33_20 x 0_91 x 0_20", Vector3.AXIS_Z, 1, 29.6)
	extend("out/roof/box 33_52 x 0_05 x 0_40", Vector3.AXIS_Z, 1, 29.45)
	move(R(-8.1, 2.4, 34.85, 49.0, 3.3, 5.0), Vector3(0, UP, 0), true, shell, ["out/group of 68/box 10_07 x 4_91 x 0_15"])
	move(R(-7.84, 2.1, 29.6, 34.85, 3.95, 5.0), Vector3(0, UP, 0), false, ["out/roof"])  # what was on the roof over the lobby's back: up onto the new one
	move(R(-8.1, -7.5, 29.5, 34.85, 4.9, 5.0), Vector3(0, UP, 0), true, ["out/group of 68"])  # (and the joints in the parapet's cap along there)
	for p in ["out/group of 68/box 13_80 x 4_91 x 0_152", "out/group of 68/box 13_86 x 0_50 x 0_162", "out/group of 68/box 13_86 x 0_50 x 0_16",
			"out/roof/box 13_82 x 0_05 x 0_402", "out/roof/box 13_82 x 0_05 x 0_40"]:  # its sides on forward over the booth
		extend(p, Vector3.AXIS_Z, -1, 29.45)
	for p in ["out/roof/box 13_50 x 0_91 x 0_202", "out/roof/box 13_50 x 0_91 x 0_20"]:
		extend(p, Vector3.AXIS_Z, -1, 29.6)
	var side := _node("out/group of 68/box 13_80 x 4_91 x 0_15")  # the side over the back of house's roof: from that roof up
	fit(_dup(side, "box tall side over boh"), Vector3(2.1, 3.95, 29.45), Vector3(2.25, 4.0 + UP + 0.91, 34.95))
	var gap := [IRON.land, IRON.x0]  # the front, the parapet open where the iron stair comes up
	fit(_dup(side, "box tall front"), Vector3(-7.99, 3.95, 29.45), Vector3(2.25, 4.0 + UP, 29.6))
	fit(_dup(side, "box tall front left"), Vector3(-7.99, 4.0 + UP, 29.45), Vector3(gap[0], 4.0 + UP + 0.91, 29.6))
	fit(_dup(side, "box tall front right"), Vector3(gap[1], 4.0 + UP, 29.45), Vector3(2.25, 4.0 + UP + 0.91, 29.6))
	var parapet := _node("out/roof/box 13_50 x 0_91 x 0_20")
	var cap := _node("out/roof/box 13_82 x 0_05 x 0_40")
	fit(_dup(parapet, "box tall front parapet left"), Vector3(-7.84, 4.0 + UP, 29.6), Vector3(gap[0], 4.0 + UP + 0.91, 29.8))
	fit(_dup(parapet, "box tall front parapet right"), Vector3(gap[1], 4.0 + UP, 29.6), Vector3(2.1, 4.0 + UP + 0.91, 29.8))
	fit(_dup(cap, "box tall front cap left"), Vector3(-8.0, 4.0 + UP + 0.91, 29.44), Vector3(gap[0], 4.0 + UP + 0.96, 29.84))
	fit(_dup(cap, "box tall front cap right"), Vector3(gap[1], 4.0 + UP + 0.91, 29.44), Vector3(2.26, 4.0 + UP + 0.96, 29.84))

	# The screen end: the screen a fifth bigger, its frame, the curtains either side out to the walls and the pelmet over it.
	var scr := _node("theater/plane 5_70 x 3_80 x 0_00")
	var sb := _bounds(scr)
	scr.global_transform.basis = scr.global_transform.basis.scaled(Vector3.ONE * SCREEN_K)
	scr.global_position += Vector3(sb.get_center().x, sb.position.y + sb.size.y * SCREEN_K / 2.0, sb.get_center().z) - _bounds(scr).get_center()
	var fb := _bounds(_node("theater/box 5_94 x 4_04 x 0_08"))
	fit(_node("theater/box 5_94 x 4_04 x 0_08"), Vector3(-2.87 - fb.size.x * SCREEN_K / 2.0, fb.position.y, fb.position.z), Vector3(-2.87 + fb.size.x * SCREEN_K / 2.0, fb.position.y + fb.size.y * SCREEN_K, fb.end.z))
	var top := fb.position.y + fb.size.y * SCREEN_K - 0.04  # (the pelmet's underside, just over the frame's top, as it was)
	fit(_node("theater/box 0_90 x 4_55 x 0_22"), Vector3(-7.64, -0.95, 47.64), Vector3(-6.57, top + 0.67, 47.86))
	fit(_node("theater/box 0_90 x 4_55 x 0_222"), Vector3(0.83, -0.95, 47.64), Vector3(1.9, top + 0.67, 47.86))
	fit(_node("theater/box 8_00 x 0_55 x 0_26"), Vector3(-7.64, top, 47.57), Vector3(1.9, top + 0.67, 47.83))
	for sc: Dictionary in data.screens:
		if sc.kind == "theater":
			sc.y = snappedf(sb.position.y + sb.size.y * SCREEN_K / 2.0, 0.01)
			sc.w = snappedf(sc.w * SCREEN_K, 0.01)
			sc.h = snappedf(sc.h * SCREEN_K, 0.01)

	# The booth, over the lobby's back: staff only, so not the lobby's paint: grey block walls, a concrete floor, a dark
	# ceiling. Its own lights, on a switch of their own. The wall it shares with the auditorium has the projector's port
	# up at its height and a window beside it to watch from; the beam re-aimed from the port.
	var under := 4.0 + UP - 0.05  # (the walls inside stop just under the roof, not through it)
	block("lobby", "booth front wall", Vector3(-7.84, 2.72, 29.6), Vector3(2.1, under, 29.8), C.block)  # (from just over the lobby's ceiling, not level with it)
	block("lobby", "booth wall by the store", Vector3(-7.84, 2.72, 29.8), Vector3(-7.64, under, 34.9), C.block)
	block("lobby", "booth wall by the back of house", Vector3(1.9, 2.72, 29.8), Vector3(2.1, under, 34.9), C.block)
	var pw := _node("between_rooms/box 8_20 x 0_90 x 0_20")  # the wall between booth and auditorium: round the window
	var win := [-5.4, -3.4, BOOTH + 0.85, BOOTH + 1.6]  # x0, x1, sill, head
	fit(pw, Vector3(-7.74, 2.7, 34.9), Vector3(2.0, win[2], 35.1))
	fit(_dup(pw, "port wall over the window"), Vector3(-7.74, win[3], 34.9), Vector3(2.0, under, 35.1))
	fit(_dup(pw, "port wall left of the window"), Vector3(-7.74, win[2], 34.9), Vector3(win[0], win[3], 35.1))
	fit(_dup(pw, "port wall right of the window"), Vector3(win[1], win[2], 34.9), Vector3(2.0, win[3], 35.1))
	for b: Array in [[-7.64, SHAFT.x0, BOOTH, win[2]], [-7.64, SHAFT.x0, win[3], CEIL], [-7.64, win[0], win[2], win[3]], [win[1], SHAFT.x0, win[2], win[3]]]:
		block("lobby", "booth side of the port wall", Vector3(b[0], b[2], 34.86), Vector3(b[1], b[3], 34.9), C.port)  # (black, as a booth's port wall is: nothing to throw light back at the glass)
	var glass := BoxMesh.new()
	glass.size = Vector3(win[1] - win[0], win[3] - win[2], 0.012)
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.55, 0.62, 0.7, 0.16)
	gm.roughness = 0.05
	glass.material = gm
	_add("lobby", "booth window", glass).global_position = Vector3((win[0] + win[1]) / 2.0, (win[2] + win[3]) / 2.0, 35.0)
	for b: Array in [[win[0] - 0.05, win[0], win[2] - 0.05, win[3] + 0.05], [win[1], win[1] + 0.05, win[2] - 0.05, win[3] + 0.05], [win[0], win[1], win[3], win[3] + 0.05]]:
		block("lobby", "booth window frame", Vector3(b[0], b[2], 34.82), Vector3(b[1], b[3], 34.86), C.iron)
	block("lobby", "booth window sill", Vector3(win[0] - 0.1, win[2] - 0.05, 34.62), Vector3(win[1] + 0.1, win[2], 34.86), C.iron)
	block("lobby", "booth floor", Vector3(-7.64, BOOTH - 0.02, 29.8), Vector3(SHAFT.x0, BOOTH, 34.86), C.floor)
	block("lobby", "booth ceiling", Vector3(-7.64, CEIL, 29.8), Vector3(1.9, CEIL + 0.02, 34.9), C.ceil)
	_node("lobby/mesh 1_78 x 0_00 x 0_887").global_position.x -= 0.8  # (the lobby's ceiling light, clear of the stairwell's wall)
	# No tubes back here: lamps low on the booth's walls, shining down, and bulbs hanging in the stairwell (_lamps).
	for p in ["theater/box 1_40 x 0_55 x 0_06", "theater/plane 0_28 x 0_22 x 0_00", "theater/plane 0_28 x 0_22 x 0_002", "theater/circle 0_15 x 0_15 x 0_00"]:
		_node(p).global_position.y += PORT_Y - 2.25
	var port := _dup(_node("theater/box 1_40 x 0_55 x 0_06"), "booth side of the port")
	port.global_position.z -= 0.31
	_extend(port, Vector3.AXIS_X, 1, SHAFT.x0 - 0.05)  # (stopping short of the stairwell's wall, not through it)
	_booth_kit()
	var stool := _node("between_rooms/group of 138")  # the register's spinning stool, another of it at the window
	var seat: Node3D = stool.duplicate()
	seat.name = "booth stool"
	stool.get_parent().add_child(seat, true)
	_own(seat)
	seat.global_position = Vector3(-4.4, BOOTH, 34.0)
	data.things.stool.more = [[-4.4, BOOTH, 34.0]]
	var beam := _node("between_rooms/mesh 2_50 x 2_50 x 8_50")
	var a0 := Vector3(-1.42, 2.25, 35.17)
	var a1 := Vector3(-1.42, PORT_Y, 35.17)
	var t0 := Vector3(-2.87, 1.05, 47.85)
	var t1 := Vector3(-2.87, sb.position.y + sb.size.y * SCREEN_K / 2.0, 47.85)
	var turn := Basis(Quaternion((t0 - a0).normalized(), (t1 - a1).normalized()))
	beam.global_transform = Transform3D(turn, a1 - turn * a0) * beam.global_transform

	# The stairs up to it: walled in, in the lobby's back corner by the back of house, through a door marked for staff.
	# Up one flight toward the back, round on a landing, up the other toward the front, and out into the booth.
	var ceil_src := _node("lobby/plane 9_74 x 5_00 x 0_002")  # the lobby's ceiling stops at the stairwell
	fit(_dup(ceil_src, "lobby ceiling by the hall door"), Vector3(SHAFT.x0, 2.7, 28.0), Vector3(2.0, 2.7, SHAFT.z0))
	_extend(ceil_src, Vector3.AXIS_X, 1, SHAFT.x0)
	move(R(-2.0, -0.4, 34.1, 34.6, -1.0, 1.0), Vector3(-0.4, 0, 0), false, ["lobby"])  # (the rope by the theater's door, clear of its wall)
	var x0: float = SHAFT.x0 + 0.15  # inside: the far flight's side
	var mid: float = SHAFT.split  # between the flights
	block("lobby", "stairwell side wall", Vector3(SHAFT.x0, 0, SHAFT.top), Vector3(x0, under, 34.9), C.block)
	block("lobby", "stairwell side wall under the way out", Vector3(SHAFT.x0, 0, 29.8), Vector3(x0, BOOTH, SHAFT.top), C.block)
	block("lobby", "stairwell side wall over the way out", Vector3(SHAFT.x0, BOOTH + 2.1, 29.8), Vector3(x0, under, SHAFT.top), C.block)
	block("lobby", "stairwell front wall", Vector3(SHAFT.x0, 0, SHAFT.z0), Vector3(0.69, 2.72, 29.8), C.block)
	block("lobby", "stairwell front wall over the door", Vector3(0.69, 2.19, SHAFT.z0), Vector3(1.9, 2.72, 29.8), C.block)
	block("lobby", "stairwell wall by the back of house", Vector3(1.88, 0, 29.8), Vector3(1.9, 2.72, 34.9), C.block)  # (over the lobby's paint, in here)
	for b: Array in [[SHAFT.x0 - 0.01, SHAFT.x0, 0.0, 2.7, SHAFT.z0, 34.9], [SHAFT.x0, 0.69, 0.0, 2.7, SHAFT.z0 - 0.01, SHAFT.z0], [0.69, 1.91, 2.19, 2.7, SHAFT.z0 - 0.01, SHAFT.z0]]:
		block("lobby", "stairwell wall, the lobby's side", Vector3(b[0], b[2], b[4]), Vector3(b[1], b[3], b[5]), C.paint)  # (out there it's the lobby's: its paint)
	block("lobby", "stairwell back wall", Vector3(x0, 0, 34.88), Vector3(1.88, CEIL, 34.9), C.block)
	block("lobby", "stairwell floor", Vector3(mid + 0.1, 0, 29.8), Vector3(1.88, 0.01, SHAFT.top), C.floor)
	block("lobby", "stairwell divider", Vector3(mid, 0, 29.8), Vector3(mid + 0.1, BOOTH + 1.1, SHAFT.turn), C.block)
	var rise := BOOTH / 18.0
	var run := (SHAFT.turn - SHAFT.top) / 8.0
	for i in 8:  # up toward the back, by the back of house's wall
		var z: float = SHAFT.top + i * run
		block("lobby", "stair", Vector3(mid + 0.1, 0, z), Vector3(1.88, (i + 1) * rise, z + run), C.tread)
		block("lobby", "stair nosing", Vector3(mid + 0.1, (i + 1) * rise - 0.015, z - 0.005), Vector3(1.88, (i + 1) * rise + 0.003, z + 0.04), C.nose)
	block("lobby", "stair landing", Vector3(x0, 0, SHAFT.turn), Vector3(1.88, BOOTH / 2.0, 34.88), C.tread)
	block("lobby", "stair nosing", Vector3(mid + 0.1, BOOTH / 2.0 - 0.015, SHAFT.turn - 0.005), Vector3(1.88, BOOTH / 2.0 + 0.003, SHAFT.turn + 0.04), C.nose)
	for j in 8:  # and round, up toward the front
		var z: float = SHAFT.turn - (j + 1) * run
		var y := BOOTH / 2.0 + (j + 1) * rise
		block("lobby", "stair", Vector3(x0, 0, z), Vector3(mid, y, z + run), C.tread)
		block("lobby", "stair nosing", Vector3(x0, y - 0.015, z + run - 0.04), Vector3(mid, y + 0.003, z + run + 0.005), C.nose)
	block("lobby", "stair top", Vector3(x0, 0, 29.8), Vector3(mid, BOOTH, SHAFT.top), C.tread)
	block("lobby", "stair nosing", Vector3(x0, BOOTH - 0.015, SHAFT.top - 0.04), Vector3(mid, BOOTH + 0.003, SHAFT.top + 0.005), C.nose)
	var r1 := 1.84  # the handrails, on the walls
	bar("lobby", "stair rail", Vector3(r1, rise + 0.9, SHAFT.top), Vector3(r1, BOOTH / 2.0 + 0.9, SHAFT.turn), Vector2(0.05, 0.05), C.iron)
	bar("lobby", "stair rail", Vector3(x0 + 0.04, BOOTH / 2.0 + rise + 0.9, SHAFT.turn), Vector3(x0 + 0.04, BOOTH + 0.9, SHAFT.top), Vector2(0.05, 0.05), C.iron)
	bar("lobby", "stair rail", Vector3(1.86, BOOTH / 2.0 + 0.9, 34.84), Vector3(x0 + 0.02, BOOTH / 2.0 + 0.9, 34.84), Vector2(0.05, 0.05), C.iron)
	# Its door: the break room's, again, marked for staff; and a light switch inside it, and one up in the booth.
	var hinge := Vector3(1.85, 0, (SHAFT.z0 + 29.8) / 2.0)
	var by := hinge - Vector3(5.55, 0, 29.8)
	var leaf: Node3D = _node("boh/group of 66").duplicate()
	leaf.name = "stairwell door"
	_node("lobby").add_child(leaf, true)
	_own(leaf)
	leaf.global_position = hinge
	for m: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		if preload("res://level.gd").texture_of(m) == "vaultbuster_189.jpg":  # its BREAK ROOM sign
			var plate := m.global_transform * m.get_aabb()
			var lab := Label3D.new()
			lab.name = "employees only"
			lab.text = "EMPLOYEES ONLY"
			lab.font_size = 40
			lab.outline_size = 0
			lab.pixel_size = 0.0011
			lab.modulate = Color(0.92, 0.92, 0.9)
			lab.shaded = false
			lab.double_sided = false
			leaf.add_child(lab)
			lab.owner = w
			lab.global_transform = Transform3D(Basis(Vector3.UP, PI), plate.get_center() + Vector3(0.02, 0, -0.004))
			var back := block("lobby", "employees only sign", plate.position + Vector3(-0.06, -0.02, -0.003), plate.end + Vector3(0.1, 0.02, 0.0), Color("15171a"))
			back.reparent(leaf)
			m.free()
	for p in ["boh/box 0_06 x 2_19 x 0_24", "boh/box 1_22 x 0_06 x 0_24", "boh/box 0_06 x 2_19 x 0_242"]:  # its frame
		_dup(_node(p), "stairwell door frame").global_position += by
	var door: Dictionary = data.doors[0].duplicate(true)  # (the break room's: hinged at its right, swinging in)
	_shift_all(door, by)
	door.at += by.z
	door.c += by.x
	data.doors.append(door)
	_switch(Vector3(SHAFT.split + 0.1, 1.2275, 30.35), Vector3.RIGHT, "stairwell")  # at the stairs' foot, on the wall across from the door (not behind it, open)
	_plate(Vector3(SHAFT.x0, BOOTH + 1.2275, 31.5), Vector3.LEFT, ["stairwell", "booth"], Vector3(SHAFT.x0, BOOTH, 30.35))  # up in the booth, by the stairs' top: the stairs (the rocker nearer them), the room
	data.lights.zones.booth = true
	data.lights.zones.stairwell = true
	data.lights.names.booth = "projection booth"
	data.lights.names.stairwell = "booth stairs"
	data.lights.plates.booth = ["booth", "stairwell"]
	data.lights.plates.stairwell = ["booth", "stairwell"]
	_lamps()

	# The theater's door, from the middle of its wall to the far end, by the store's side: in on the right, down the aisle
	# there. Its frame, its signs and the lobby's switches by it go with it; the wall closes up where it was.
	var dx := DOOR_X0 - (-3.42)
	for p in ["between_rooms/group of 154", "between_rooms/box 0_06 x 2_19 x 0_247", "between_rooms/box 1_22 x 0_06 x 0_243", "between_rooms/box 0_06 x 2_19 x 0_248",
			"between_rooms/box 1_10 x 0_57 x 0_203", "theater/plane 0_46 x 0_18 x 0_00", "lobby/group of 535"]:
		_node(p).global_position.x += dx
	for p in ["lobby/box 2_20 x 0_36 x 0_14", "lobby/plane 2_08 x 0_28 x 0_00"]:  # (its sign over it, as far over as the corner lets it)
		_node(p).global_position.x += -7.6 - (-3.97)
	_extend(_node("between_rooms/box 4_32 x 2_70 x 0_20"), Vector3.AXIS_X, 1, DOOR_X0)
	_extend(_node("between_rooms/box 4_32 x 2_70 x 0_202"), Vector3.AXIS_X, -1, DOOR_X0 + 1.1)
	for d: Dictionary in data.doors:
		if d.alongX and absf(d.at - 35.0) < 0.01:
			_shift_all(d, Vector3(dx, 0, 0))
			d.c += dx
	for sw: Dictionary in data.lights.switches:
		if sw.zone in ["lobby", "theater"]:
			sw.p[0] += dx
	# The velvet ropes, not in use: put by, out of the way, a pair close together sagging low and a pair as they were
	_ropes([[Vector3(-1.05, 0, 33.3), Vector3(-1.13, 0, 33.92), 0.52], [Vector3(-4.95, 0, 34.52), Vector3(-3.78, 0, 34.34), 0.24]])
	# The auditorium's back wall, its own colour all the way down (under the booth, it was the lobby's paint).
	var th_wall := _node("theater/box 0_20 x 5_16 x 13_50")
	var j := [DOOR_X0 - 0.06, DOOR_X0 + 1.16]  # the door's frame
	for b: Array in [[-7.64, j[0], 0.0, 2.7], [j[1], 1.9, 0.0, 2.7], [j[0], j[1], 2.19, 2.7]]:
		fit(_dup(th_wall, "auditorium back wall"), Vector3(b[0], b[2], 35.1), Vector3(b[1], b[3], 35.112))
	# A row more, across the back, on the level floor by the door: the first row again, up and back
	var back := Vector3(0, 0.26, -1.25)
	for m: MeshInstance3D in _node("theater").get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.has_meta("walk_through")):
		_copy_rows(m, 36.4, 37.7, back, "back row")
	var row1: CollisionShape3D = _node("theater/seat backs").get_child(0)
	var row0: CollisionShape3D = row1.duplicate()
	row0.name = "row 0"
	row1.get_parent().add_child(row0)
	row0.owner = w
	row0.position += back
	for s: Dictionary in data.seats.duplicate():
		if s.kind == "theater" and absf(s.z - 37.0) < 0.01:
			var b0: Dictionary = s.duplicate()
			b0.y = snappedf(s.y + back.y, 0.01)
			b0.z = s.z + back.z
			data.seats.append(b0)
	# The front row: room for wheelchairs at each end, two spaces where three seats were, their sides marked quietly on the floor
	var front := 43.5
	var ends := [[-6.05, -4.1], [-0.4, 1.9]]  # (x: by the aisle; by the far wall)
	for m: MeshInstance3D in _node("theater").get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.has_meta("walk_through")):
		for e: Array in ends:
			_cut_box(m, Vector3(e[0], -INF, front - 0.55), Vector3(e[1], INF, front + 0.8))
	data.seats = data.seats.filter(func(s: Dictionary) -> bool: return not (s.kind == "theater" and absf(s.z - front) < 0.01 and ends.any(func(e: Array) -> bool: return s.x > e[0] and s.x < e[1])))
	var row6: CollisionShape3D = _node("theater/seat backs").get_child(5)  # (its seat backs: just the seats left in the middle)
	var sh: BoxShape3D = row6.shape.duplicate()
	sh.size.x = ends[1][0] - ends[0][1]
	row6.shape = sh
	row6.global_position.x = (ends[0][1] + ends[1][0]) / 2.0
	var floor_y := -1.56
	for x in [-5.97, -5.04, -4.11, -0.39, 0.54, 1.47]:
		block("theater", "wheelchair space line", Vector3(x - 0.02, floor_y, front - 0.5), Vector3(x + 0.02, floor_y + 0.003, front + 0.6), Color("4d4650"))

	# The roof: the store's and the back of house's at 4 m (round the closet's hatch), the tall block's at 6.4.
	var hatch := [10.28, 10.88, 28.12, 28.87]
	_roof(gravel, [[-7.84, hatch[0], -0.1, 29.6], [hatch[1], 11.1, -0.1, 29.6], [hatch[0], hatch[1], -0.1, hatch[2]], [hatch[0], hatch[1], hatch[3], 29.6], [2.1, 11.1, 29.6, 35.1]], 4.0, "roof")
	_roof(gravel.slice(0, 1), [[-7.84, 2.1, 29.6, 48.6]], 4.0 + UP, "roof over the theater")  # (just the gravel: the layer over it has the old building's outline in it)

	# The iron stair up to it, against the tall block's front, from the store's roof.
	var lo := 4.0
	var r: float = UP / IRON.n
	for i in IRON.n:
		var x1: float = IRON.x0 + (IRON.n - i) * IRON.run
		var y: float = lo + (i + 1) * r
		block("out/roof", "iron stair tread %d" % (i + 1), Vector3(x1 - IRON.run, y - 0.03, IRON.z0), Vector3(x1, y, IRON.z1), C.iron)
	var foot := Vector3(IRON.x0 + IRON.n * IRON.run + 0.1, lo, 0)
	var head := Vector3(IRON.x0, lo + UP, 0)
	for z in [IRON.z0, IRON.z1 - 0.04]:
		bar("out/roof", "iron stair stringer", Vector3(foot.x, lo, z + 0.02), Vector3(head.x, head.y - 0.03, z + 0.02), Vector2(0.04, 0.18), C.iron)
	block("out/roof", "iron stair landing", Vector3(IRON.land, lo + UP - 0.05, IRON.z0), Vector3(IRON.x0, lo + UP, 29.6), C.iron)
	for x in [IRON.land + 0.03, IRON.x0 - 0.03]:
		bar("out/roof", "iron stair leg", Vector3(x, lo, IRON.z0 + 0.03), Vector3(x, lo + UP - 0.05, IRON.z0 + 0.03), Vector2(0.06, 0.06), C.iron)
	var rz: float = IRON.z0 + 0.02
	bar("out/roof", "iron stair rail", Vector3(foot.x - 0.1, lo + r + 0.9, rz), Vector3(head.x, head.y + 0.9, rz), Vector2(0.04, 0.04), C.iron)
	bar("out/roof", "iron stair landing rail", Vector3(head.x, head.y + 0.9, rz), Vector3(IRON.land + 0.02, head.y + 0.9, rz), Vector2(0.04, 0.04), C.iron)
	bar("out/roof", "iron stair landing end rail", Vector3(IRON.land + 0.02, head.y + 0.9, rz), Vector3(IRON.land + 0.02, head.y + 0.9, 29.45), Vector2(0.04, 0.04), C.iron)
	for p in [[foot.x - 0.1, lo + r], [(foot.x + head.x) / 2.0, (lo + head.y) / 2.0], [head.x, head.y], [IRON.land + 0.02, head.y]]:
		bar("out/roof", "iron stair rail post", Vector3(p[0], p[1], rz), Vector3(p[0], p[1] + 0.9, rz), Vector2(0.04, 0.04), C.iron)

	# The back ladder: off the theater's side (a wall too tall for it now) to the back of house's back wall; the bed
	# out back clear of the wider theater.
	var was := Vector3(1.62, 0, 43.3)
	var now := Vector3(6.0, 0, 35.39)
	var swing := Transform3D(Basis(Vector3.UP, -PI / 2.0), now) * Transform3D(Basis(), -was)
	for p in ["between_rooms/group of 20", "out/group of 1112"]:
		_node(p).global_transform = swing * _node(p).global_transform
	_node("between_rooms/group of 20").set_meta("back_ladder", true)  # (fixtures.gd finds its sliding half by this)
	data.ladders.back.x = now.x
	data.ladders.back.z = now.z
	data.ladders.back.climb = { "x": now.x, "z": now.z + 0.42, "yaw": 0, "up": { "x": now.x, "z": now.z - 1.07 }, "down": { "x": now.x, "z": now.z + 0.53 } }
	_node("between_rooms/group of 74").global_position.x += 1.2
	data.things.bed.at[0] = 3.15

	var b: Dictionary = data.lights.boxes
	b.theater = [-7.79, 2.05, 35.05, 48.55]
	b.booth = [-7.79, 2.05, 29.7, 35.05]
	b.tall = [2.72, CEIL]  # the booth from here up (over the lobby's ceiling), the tall block's ceiling
	b.shaft = [SHAFT.x0 + 0.1, SHAFT.z0 + 0.1]  # the stairwell, in the lobby's corner from here: the booth's light


const WARM := 0xffb466  # an incandescent bulb's light

func _lamps() -> void:  # the booth's and the stairwell's lights: on the booth's switch, warm, from where they hang or sit (lights.gd's zoned scene lights; the bulbs glow with them, meta "glow")
	for at: Vector3 in [Vector3(1.3, 2.62, 30.35), Vector3(0.6, 3.75, 34.0)]:  # hanging in the stairwell: over the door's landing, over the turn
		bar("lobby", "lamp cord", Vector3(at.x, CEIL, at.z), at + Vector3(0, 0.16, 0), Vector2(0.012, 0.012), C.iron)
		var shade := CylinderMesh.new()
		shade.top_radius = 0.05
		shade.bottom_radius = 0.17
		shade.height = 0.15
		shade.radial_segments = 24
		shade.material = _mat(Color("2f4636"))
		_add("lobby", "lamp shade", shade).global_position = at + Vector3(0, 0.09, 0)
		var bulb := SphereMesh.new()
		bulb.radius = 0.045
		bulb.height = 0.1
		bulb.material = _glow(Color("ffd890"))
		var b := _add("lobby", "lamp bulb", bulb)
		b.global_position = at
		b.set_meta("glow", "stairwell")
		data.lights.scene.append({ "kind": "point", "p": [at.x, at.y - 0.05, at.z], "to": null, "color": WARM, "on": 2.4, "now": 2.4, "zone": "stairwell", "range": 5.5, "angle": null })
	for f: Array in [[Vector3(-6.2, 0, 29.8), Vector3.BACK], [Vector3(-3.4, 0, 29.8), Vector3.BACK], [Vector3(-7.64, 0, 33.9), Vector3.RIGHT], [Vector3(-6.6, 0, 34.86), Vector3.FORWARD], [Vector3(-2.4, 0, 34.86), Vector3.FORWARD]]:  # low on the booth's walls, shining down
		var at: Vector3 = f[0] + Vector3(0, BOOTH + 0.95, 0)
		var out: Vector3 = f[1]
		var side := Vector3(out.z, 0, -out.x)
		var size := (side * 0.26).abs() + (out * 0.11).abs() + Vector3(0, 0.1, 0)
		var housing := block("lobby", "booth wall lamp", -size / 2.0, size / 2.0, C.iron)
		housing.global_position = at + out * 0.055 + Vector3(0, 0.05, 0)
		var lens := BoxMesh.new()
		lens.size = Vector3(0.22, 0.006, 0.07) if out.x == 0.0 else Vector3(0.07, 0.006, 0.22)
		lens.material = _glow(Color("ffd890"))
		var l := _add("lobby", "booth wall lamp lens", lens)
		l.global_position = at + out * 0.06 - Vector3(0, 0.003, 0)
		l.set_meta("glow", "booth")
		var p := at + out * 0.06 - Vector3(0, 0.02, 0)
		var to := Vector3(p.x, BOOTH, p.z) + out * 0.7
		data.lights.scene.append({ "kind": "spot", "p": [p.x, p.y, p.z], "to": [to.x, to.y, to.z], "color": WARM, "on": 0.35, "now": 0.35, "zone": "booth", "range": 3.5, "angle": 1.1 })


func _ropes(pairs: Array) -> void:  # the lobby's four stanchions, two by two at those spots (each [one post, the other, how far its rope sags]): the rope a thick velvet one, hung as a rope hangs, brass at each end
	var posts := []  # each: the meshes of one stanchion (its foot, its post, its ball)
	for m: MeshInstance3D in _node("lobby").get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D):
		var b := m.global_transform * m.get_aabb()
		if b.end.y > 1.0 or b.position.z < 34.1 or b.end.z > 34.6:
			continue
		if String(m.name).begins_with("torus 1_28"):
			m.free()  # (the old ropes: a stiff arc each)
			continue
		var c := b.get_center()
		var kit = posts.filter(func(k: Array) -> bool: return absf(k[0].x - c.x) < 0.16)
		if kit.is_empty():
			posts.append([Vector3(c.x, 0, c.z), m])
		else:
			kit[0].append(m)
	assert(posts.size() == 4, "remodel: %d stanchions in the lobby, not 4" % posts.size())
	var velvet := StandardMaterial3D.new()
	velvet.albedo_color = Color("7a0f1a")
	velvet.roughness = 0.95
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("c9a227")
	brass.metallic = 0.7
	brass.roughness = 0.3
	for i in pairs.size():
		var ends := [pairs[i][0], pairs[i][1]]
		for k in 2:  # the stanchions there
			for m: MeshInstance3D in posts[i * 2 + k].slice(1):
				m.global_position += ends[k] - posts[i * 2 + k][0]
		var dir: Vector3 = (ends[1] - ends[0]).normalized()
		var hook := 0.82
		var a: Vector3 = ends[0] + dir * 0.05 + Vector3(0, hook, 0)
		var b: Vector3 = ends[1] - dir * 0.05 + Vector3(0, hook, 0)
		var half := a.distance_to(b) / 2.0
		var sag: float = pairs[i][2]
		var lo := 0.01
		var hi := 10.0
		for _n in 40:  # the catenary through both ends that sags that far: y = c (cosh(u / c) - cosh(half / c))
			var c := (lo + hi) / 2.0
			if c * (cosh(half / c) - 1.0) > sag:
				lo = c
			else:
				hi = c
		var cat := (lo + hi) / 2.0
		var pts := []
		for j in 25:
			var u := -half + 2.0 * half * j / 24.0
			pts.append(a.lerp(b, (u + half) / (2.0 * half)) + Vector3(0, cat * (cosh(u / cat) - cosh(half / cat)), 0))
		for j in 24:
			_tube(pts[j], pts[j + 1], 0.024, velvet, "velvet rope")
			if j > 0:
				_ball(pts[j], 0.024, velvet, "velvet rope")
		for e: Array in [[pts[0], pts[1], ends[0]], [pts[24], pts[23], ends[1]]]:  # brass at each end: the ferrule over the rope's end, the clip on the post's ring
			var along: Vector3 = (e[1] - e[0]).normalized()
			_tube(e[0] - along * 0.01, e[0] + along * 0.07, 0.033, brass, "rope end")
			var ring := TorusMesh.new()
			ring.inner_radius = 0.016
			ring.outer_radius = 0.026
			ring.material = brass
			var r := _add("lobby", "rope clip", ring)
			var post: Vector3 = e[2] + Vector3(0, hook, 0)
			r.global_transform = Transform3D(Basis.looking_at((post - e[0]).normalized()).rotated(Vector3.UP, 0.0) * Basis(Vector3.RIGHT, PI / 2.0), (post + e[0]) / 2.0)


func _tube(a: Vector3, b: Vector3, radius: float, mat: Material, name: String) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.radial_segments = 16
	cm.rings = 1
	cm.material = mat
	var m := _add("lobby", name, cm)
	m.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) / 2.0)


func _ball(at: Vector3, radius: float, mat: Material, name: String) -> void:  # (a rope's bend, smooth)
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	sm.material = mat
	_add("lobby", name, sm).global_position = at


func _glow(c: Color) -> StandardMaterial3D:  # a bulb, lit (drawn unlit: lights.gd dims it with its switch)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _booth_kit() -> void:  # what's in a booth of the time: the projector on its console, fed from a platter; the bench films are made up and broken down on; the cans, the sound rack, the extinguisher; red working lights for when the room's dark
	var B := BOOTH
	var k := { "cast": Color("3a3d42"), "head": Color("4a4f57"), "lamp": Color("2c2f34"), "duct": Color("9a9ea4"), "alu": Color("b8bcc2"), "film": Color("3b2a1e"),
		"rack": Color("141518"), "unit": Color("2a2c30"), "mat": Color("1a1b1d"), "cork": Color("8c6a46"), "paper": Color("e6e2d6"), "red": Color("b3201c"), "table": Color("6b5a44") }
	# The projector, at its port: cast pedestal, console, the head with its lens through the port, the xenon lamp house behind, its exhaust up through the ceiling
	var px := -1.42
	block("lobby", "projector mat", Vector3(-2.15, B, 33.25), Vector3(-0.72, B + 0.008, 34.84), k.mat)
	block("lobby", "projector pedestal foot", Vector3(px - 0.42, B, 33.65), Vector3(px + 0.42, B + 0.09, 34.65), k.cast)
	block("lobby", "projector pedestal", Vector3(px - 0.2, B + 0.09, 33.85), Vector3(px + 0.2, B + 0.92, 34.45), k.cast)
	block("lobby", "projector console", Vector3(px - 0.34, B + 0.92, 33.45), Vector3(px + 0.34, B + 0.99, 34.7), k.cast)
	block("lobby", "projector head", Vector3(px - 0.2, B + 0.99, 34.08), Vector3(px + 0.2, B + 1.42, 34.6), k.head)
	block("lobby", "projector soundhead", Vector3(px - 0.17, B + 0.99, 34.0), Vector3(px + 0.17, B + 1.2, 34.08), k.head)
	cylinder("lobby", "projector lens", Vector3(px, PORT_Y, 34.72), 0.065, 0.24, Vector3.BACK, C.iron)
	for y in [B + 1.06, B + 1.32]:  # the sprockets either side of the gate
		cylinder("lobby", "projector sprocket", Vector3(px - 0.21, y, 34.3), 0.055, 0.03, Vector3.RIGHT, C.metal)
	block("lobby", "projector lamp house", Vector3(px - 0.24, B + 0.99, 33.48), Vector3(px + 0.24, B + 1.62, 34.08), k.lamp)
	for i in 4:  # its cooling fins
		block("lobby", "lamp house fin", Vector3(px - 0.25, B + 1.08 + i * 0.12, 33.5), Vector3(px - 0.24, B + 1.12 + i * 0.12, 34.06), C.metal)
	cylinder("lobby", "lamp house exhaust", Vector3(px, (B + 1.62 + CEIL) / 2.0, 33.78), 0.1, CEIL - B - 1.62, Vector3.UP, k.duct)
	block("lobby", "lamp house power supply", Vector3(-3.05, B, 33.95), Vector3(-2.65, B + 0.95, 34.6), k.unit)
	# The platter: three decks on a mast, a film wound on the top two, the brain on top; the film over a roller to the projector
	var pl := Vector3(-4.3, B, 31.9)
	block("lobby", "platter base", pl + Vector3(-0.35, 0, -0.35), pl + Vector3(0.35, 0.12, 0.35), k.cast)
	cylinder("lobby", "platter mast", pl + Vector3(0, 0.8, 0), 0.05, 1.6, Vector3.UP, C.metal)
	for i in 3:
		var y: float = 0.55 + i * 0.4
		cylinder("lobby", "platter", pl + Vector3(0, y, 0), 0.68, 0.025, Vector3.UP, k.alu)
		if i > 0:
			cylinder("lobby", "film on the platter", pl + Vector3(0, y + 0.03, 0), 0.47, 0.035, Vector3.UP, k.film)
	cylinder("lobby", "platter brain", pl + Vector3(0, 1.68, 0), 0.11, 0.16, Vector3.UP, k.head)
	block("lobby", "platter controls", pl + Vector3(0.36, 0, -0.12), pl + Vector3(0.52, 0.9, 0.12), k.unit)
	var post := Vector3(-2.45, B, 33.35)
	cylinder("lobby", "film roller post", post + Vector3(0, 0.82, 0), 0.025, 1.64, Vector3.UP, C.metal)
	cylinder("lobby", "film roller", post + Vector3(0, 1.62, 0), 0.04, 0.06, Vector3.RIGHT, k.alu)
	for leg: Array in [[pl + Vector3(0.06, 1.62, 0.04), post + Vector3(0, 1.66, 0)], [post + Vector3(0, 1.66, 0), Vector3(px, B + 1.44, 34.2)]]:
		bar("lobby", "film", leg[0], leg[1], Vector2(0.035, 0.003), k.film)
	# The make-up bench along the side wall: rewinds at each end, the splicer, cans waiting
	var bx := [-7.62, -6.92]
	block("lobby", "make-up bench top", Vector3(bx[0], B + 0.85, 30.4), Vector3(bx[1], B + 0.9, 32.7), k.table)
	for z in [30.45, 32.6]:
		for x in [bx[0] + 0.05, bx[1] - 0.05]:
			block("lobby", "make-up bench leg", Vector3(x - 0.025, B, z - 0.025), Vector3(x + 0.025, B + 0.85, z + 0.025), C.iron)
	block("lobby", "make-up bench shelf", Vector3(bx[0], B + 0.25, 30.45), Vector3(bx[1], B + 0.28, 32.65), k.table)
	for z in [30.75, 32.35]:
		block("lobby", "rewind stand", Vector3(-7.32, B + 0.9, z - 0.05), Vector3(-7.22, B + 1.05, z + 0.05), C.iron)
		cylinder("lobby", "rewind reel", Vector3(-7.27, B + 1.24, z), 0.19, 0.03, Vector3.RIGHT, k.alu)
		cylinder("lobby", "rewind crank", Vector3(-7.2, B + 1.24, z), 0.015, 0.12, Vector3.RIGHT, C.iron)
	block("lobby", "splicer", Vector3(-7.4, B + 0.9, 31.45), Vector3(-7.12, B + 0.97, 31.7), C.metal)
	for i in 4:
		cylinder("lobby", "film can", Vector3(-7.27, B + 0.29 + 0.045 * i + 0.02, 31.2 + (i % 2) * 0.06), 0.2, 0.04, Vector3.UP, C.metal)
	# The can rack on the front wall
	var rx := [-7.55, -6.6]
	for x in rx:
		block("lobby", "can rack upright", Vector3(x, B, 29.82), Vector3(x + 0.04, B + 1.9, 30.27), C.iron)
	for i in 4:
		var y: float = B + 0.25 + i * 0.52
		block("lobby", "can rack shelf", Vector3(rx[0], y, 29.82), Vector3(rx[1] + 0.04, y + 0.025, 30.27), C.iron)
		for j in (3 if i < 3 else 2):
			cylinder("lobby", "film can", Vector3(rx[0] + 0.22 + j * 0.3, y + 0.05 + (j % 2) * 0.045, 30.04), 0.19, 0.045, Vector3.UP, C.metal if (i + j) % 3 else Color("8a6d2a"))
	# The sound rack, on the stairwell's wall: black, its units, their lights (always on: it's powered whatever the room's lights)
	var sr := [SHAFT.x0 - 0.62, SHAFT.x0]
	block("lobby", "sound rack", Vector3(sr[0], B, 32.15), Vector3(sr[1], B + 1.9, 32.95), k.rack)
	for i in 6:
		var y: float = B + 0.2 + i * 0.26
		block("lobby", "rack unit", Vector3(sr[0] - 0.012, y, 32.2), Vector3(sr[0], y + 0.2, 32.9), k.unit)
		for j in (i % 3) + 2:
			var led := BoxMesh.new()
			led.size = Vector3(0.006, 0.012, 0.012)
			led.material = _glow([Color("33ff66"), Color("ffb020"), Color("33ff66"), Color("ff4030")][(i + j) % 4])
			_add("lobby", "rack light", led).global_position = Vector3(sr[0] - 0.015, y + 0.15, 32.3 + j * 0.06)
	# The rest: the extinguisher by the stairs, the clock over the window, the schedule board, a bin
	cylinder("lobby", "fire extinguisher", Vector3(SHAFT.x0 - 0.1, B + 0.6, 31.05), 0.08, 0.5, Vector3.UP, k.red)
	cylinder("lobby", "fire extinguisher top", Vector3(SHAFT.x0 - 0.1, B + 0.9, 31.05), 0.03, 0.1, Vector3.UP, C.iron)
	block("lobby", "fire extinguisher bracket", Vector3(SHAFT.x0 - 0.03, B + 0.5, 30.98), Vector3(SHAFT.x0, B + 0.75, 31.12), C.iron)
	cylinder("lobby", "clock", Vector3(-4.4, B + 2.35, 34.83), 0.16, 0.04, Vector3.FORWARD, k.paper)
	cylinder("lobby", "clock rim", Vector3(-4.4, B + 2.35, 34.845), 0.175, 0.03, Vector3.FORWARD, C.iron)
	block("lobby", "schedule board", Vector3(-4.0, B + 1.35, 29.8), Vector3(-2.8, B + 2.05, 29.83), k.cork)
	for i in 5:
		block("lobby", "schedule sheet", Vector3(-3.92 + (i % 3) * 0.38, B + 1.42 + (i / 3) * 0.3, 29.83), Vector3(-3.66 + (i % 3) * 0.38, B + 1.68 + (i / 3) * 0.3, 29.835), k.paper)
	cylinder("lobby", "bin", Vector3(-6.3, B + 0.22, 30.55), 0.17, 0.44, Vector3.UP, C.iron)
	# Red working lights, low: on only while the room's lights are off, to find the way by
	for f: Array in [[Vector3(SHAFT.x0, 0, 31.35), Vector3.LEFT], [Vector3(SHAFT.x0, 0, 33.6), Vector3.LEFT], [Vector3(-2.2, 0, 34.86), Vector3.FORWARD],
			[Vector3(-5.6, 0, 34.86), Vector3.FORWARD], [Vector3(-3.4, 0, 29.8), Vector3.BACK], [Vector3(-5.6, 0, 29.8), Vector3.BACK], [Vector3(-7.64, 0, 33.5), Vector3.RIGHT]]:
		var out: Vector3 = f[1]
		var lens := BoxMesh.new()
		lens.size = Vector3(0.14, 0.035, 0.02) if out.x == 0.0 else Vector3(0.02, 0.035, 0.14)
		lens.material = _glow(Color("ff2a1a"))
		var l := _add("lobby", "red working light", lens)
		l.global_position = f[0] + Vector3(0, B + 0.18, 0) + out * 0.012
		l.set_meta("glow", "booth")
		l.set_meta("dark", true)
	for at: Vector3 in [Vector3(-1.3, B + 0.3, 30.5), Vector3(-2.9, B + 0.3, 33.0), Vector3(-5.8, B + 0.3, 31.2), Vector3(-5.0, B + 0.3, 33.9)]:
		data.lights.scene.append({ "kind": "point", "p": [at.x, at.y, at.z], "to": null, "color": 0xff2414, "on": 0.6, "now": 0.6, "zone": "booth", "dark": true, "range": 3.0, "angle": null })


# ---- building things

func _own(n: Node) -> void:  # (a copy put in the level: it and all in it saved with it)
	n.owner = w
	for c in n.find_children("*", "", true, false):
		c.owner = w


func _switch(at: Vector3, facing: Vector3, zone: String) -> void:  # a light switch on the wall there (the restroom's, again)
	var src := _node("boh/group of 3189")  # (turned to face +x when it went onto the restroom's side wall: boh)
	var sw: Node3D = src.duplicate()
	sw.name = "%s light switch" % zone
	src.get_parent().add_child(sw, true)
	_own(sw)
	sw.global_basis = Basis(Vector3.UP, atan2(facing.x, facing.z) - PI / 2.0) * src.global_basis
	var b := _bounds(sw)
	sw.global_position += at + facing * 0.02 - b.get_center()
	data.lights.switches.append({ "zone": zone, "p": [snappedf(at.x + facing.x * 0.009, 0.001), at.y, snappedf(at.z + facing.z * 0.009, 0.001)] })


func _plate(at: Vector3, facing: Vector3, zones: Array, toward: Vector3) -> void:  # a two-switch plate on the wall there (the lobby's, again): the rocker nearer toward for zones[0], the other for zones[1]
	var src := _node("lobby/group of 535")  # (on the lobby's side of the theater's wall, facing -z: its rockers the lobby's, then the theater's)
	var rockers: Array = data.lights.switches.filter(func(s: Dictionary) -> bool: return s.zone in ["lobby", "theater"])
	var pl: Node3D = src.duplicate()
	pl.name = "booth light switches"
	src.get_parent().add_child(pl, true)
	_own(pl)
	pl.global_basis = Basis(Vector3.UP, atan2(facing.x, facing.z) - PI) * src.global_basis
	pl.global_position += at + facing * 0.02 - _bounds(pl).get_center()
	var move := pl.global_transform * src.global_transform.affine_inverse()  # (where the lobby's plate's rockers are, there on this one)
	for m: MeshInstance3D in pl.find_children("*", "MeshInstance3D", true, false):  # its LOBBY / HOUSE (its face's own material), off: its own words under its rockers instead
		for i in m.mesh.get_surface_count():
			var mat = m.mesh.surface_get_material(i)
			if mat is BaseMaterial3D and mat.albedo_texture != null:
				m.mesh = m.mesh.duplicate()
				m.mesh.surface_set_material(i, m.mesh.surface_get_material(0 if i else 1))
	var at_: Array = rockers.map(func(r: Dictionary) -> Vector3: return move * Vector3(r.p[0], r.p[1], r.p[2]))
	if at_[1].distance_to(toward) < at_[0].distance_to(toward):
		at_.reverse()
	for i in 2:
		var p: Vector3 = at_[i]
		data.lights.switches.append({ "zone": zones[i], "p": [snappedf(p.x, 0.001), snappedf(p.y, 0.0001), snappedf(p.z, 0.001)] })
		var lab := Label3D.new()
		lab.name = "label"
		lab.text = { "booth": "ROOM", "stairwell": "STAIRS" }[zones[i]]
		lab.font_size = 22
		lab.outline_size = 0
		lab.pixel_size = 0.0005
		lab.modulate = Color(0.12, 0.12, 0.12)
		lab.double_sided = false
		pl.add_child(lab)
		lab.owner = w
		lab.global_transform = Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), p + Vector3(0, -0.036, 0) + facing * 0.004)


func fit(n: MeshInstance3D, lo: Vector3, hi: Vector3) -> MeshInstance3D:  # moved and stretched to fill lo..hi (an INF there: as it is on that axis; flat: just put at lo), its texture carried on rather than pulled
	var b := n.global_transform * n.get_aabb()
	var shift := Vector3.ZERO
	for i in 3:
		if is_finite(lo[i]):
			shift[i] = lo[i] - b.position[i]
	n.global_position += shift
	for i in 3:
		if is_finite(hi[i]) and b.size[i] > 0.001 and absf(hi[i] - (b.position[i] + shift[i]) - b.size[i]) > 0.0005:
			_extend(n, i, 1, hi[i])
	return n


func _dup(src: MeshInstance3D, name: String) -> MeshInstance3D:
	var n: MeshInstance3D = src.duplicate()
	n.name = name
	src.get_parent().add_child(n, true)
	n.owner = w
	n.global_transform = src.global_transform
	return n


var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		m.metallic = 0.4 if c in [C.metal, C.iron, C.tread] else 0.0
		_mats[c] = m
	return _mats[c]


func _add(parent: String, name: String, mesh: Mesh) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.name = name
	_node(parent).add_child(m, true)
	m.owner = w
	return m


func block(parent: String, name: String, lo: Vector3, hi: Vector3, c: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = hi - lo
	bm.material = _mat(c)
	var m := _add(parent, name, bm)
	m.global_position = (lo + hi) / 2.0
	return m


func bar(parent: String, name: String, a: Vector3, b: Vector3, t: Vector2, c: Color) -> MeshInstance3D:  # a beam t thick from a to b
	var bm := BoxMesh.new()
	bm.size = Vector3(t.x, t.y, a.distance_to(b))
	bm.material = _mat(c)
	var m := _add(parent, name, bm)
	var d := (b - a).normalized()
	m.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.BACK), (a + b) / 2.0)
	return m


func cylinder(parent: String, name: String, at: Vector3, radius: float, length: float, axis: Vector3, c: Color) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 24
	cm.material = _mat(c)
	var m := _add(parent, name, cm)
	m.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axis.normalized())) if absf(axis.normalized().y) < 0.99 else Basis(), at)
	return m


func _faces_up(m: MeshInstance3D) -> bool:  # which way the level winds an upward face (the roof's first triangle)
	var a := m.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array([0, 1, 2])
	return (vs[idx[1]] - vs[idx[0]]).cross(vs[idx[2]] - vs[idx[0]]).y > 0.0


func _roof(layers: Array, rects: Array, y: float, name: String) -> void:  # flat roof over those [x0, x1, z0, z1], each layer of the old one's (its material, how far over the gravel, its winding); textured by where it is, as the old one was
	for k in layers.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in rects:
			var c := [Vector3(r[0], 0, r[2]), Vector3(r[1], 0, r[2]), Vector3(r[1], 0, r[3]), Vector3(r[0], 0, r[3])]
			for i in ([0, 2, 1, 0, 3, 2] if layers[k][2] else [0, 1, 2, 0, 2, 3]):
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(c[i].x, -c[i].z))
				st.add_vertex(c[i])
		st.generate_tangents()
		var mesh := st.commit()
		mesh.surface_set_material(0, layers[k][0])
		var m := _add("out/roof", "%s %d" % [name, k], mesh)
		m.global_position = Vector3(0, y + layers[k][1], 0)


func _copy_rows(m: MeshInstance3D, z0: float, z1: float, by: Vector3, what: String) -> void:  # the triangles wholly between z0 and z1, again, moved by
	var xf := m.global_transform
	var mesh := ArrayMesh.new()
	for s in m.mesh.get_surface_count():
		var a := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var tri: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		var keep := PackedInt32Array()
		for k in range(0, tri.size() - 2, 3):
			if [0, 1, 2].all(func(j: int) -> bool: var z := (xf * vs[tri[k + j]]).z; return z >= z0 and z <= z1):
				keep.append_array([tri[k], tri[k + 1], tri[k + 2]])
		if keep.is_empty():
			continue
		a[Mesh.ARRAY_INDEX] = keep
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
	if mesh.get_surface_count() == 0:
		return
	var c := MeshInstance3D.new()
	c.mesh = mesh
	c.name = "%s, %s" % [m.name, what]
	m.get_parent().add_child(c, true)
	c.owner = w
	c.global_transform = xf.translated(by)
	c.set_meta("walk_through", true)


func _cut_box(m: MeshInstance3D, lo: Vector3, hi: Vector3) -> void:  # its triangles wholly inside lo..hi, gone
	var xf := m.global_transform
	var box := AABB(lo, hi - lo)
	var mesh := ArrayMesh.new()
	for s in m.mesh.get_surface_count():
		var a := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var tri: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		var keep := PackedInt32Array()
		for k in range(0, tri.size() - 2, 3):
			if not [0, 1, 2].all(func(j: int) -> bool: var p := xf * vs[tri[k + j]]; return p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z):
				keep.append_array([tri[k], tri[k + 1], tri[k + 2]])
		if keep.is_empty():
			continue
		a[Mesh.ARRAY_INDEX] = keep
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
	m.mesh = mesh


func _copy_column(m: MeshInstance3D, x0: float, x1: float, dx: float) -> void:  # the triangles wholly between x0 and x1, again, dx along (a row's end seat, one more)
	var xf := m.global_transform
	var mesh := ArrayMesh.new()
	for s in m.mesh.get_surface_count():
		var a := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var tri: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		var keep := PackedInt32Array()
		for k in range(0, tri.size() - 2, 3):
			if [0, 1, 2].all(func(j: int) -> bool: var x := (xf * vs[tri[k + j]]).x; return x >= x0 and x <= x1):
				keep.append_array([tri[k], tri[k + 1], tri[k + 2]])
		if keep.is_empty():
			continue
		a[Mesh.ARRAY_INDEX] = keep
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
	var c := MeshInstance3D.new()
	c.mesh = mesh
	c.name = "%s, %s end seat" % [m.name, "left" if dx < 0 else "right"]
	m.get_parent().add_child(c, true)
	c.owner = w
	c.global_transform = xf.translated(Vector3(dx, 0, 0))
	c.set_meta("walk_through", true)  # (the seat backs' own colliders: theater/seat backs)


# ---- moving things

class Region:
	var lo: Vector3
	var hi: Vector3
	func has(p: Vector3) -> bool:
		return p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
	func holds(b: AABB) -> bool:
		return has(b.position) and has(b.end)
	func meets(b: AABB) -> bool:
		return b.end.x >= lo.x and b.position.x <= hi.x and b.end.y >= lo.y and b.position.y <= hi.y and b.end.z >= lo.z and b.position.z <= hi.z


static func R(x0: float, x1: float, z0: float, z1: float, y0 := -INF, y1 := INF) -> Region:
	var r := Region.new()
	r.lo = Vector3(x0, y0, z0)
	r.hi = Vector3(x1, y1, z1)
	return r


var _skip: Array = []

func move(r: Region, by: Vector3, stretch := true, under: Array = [], skip: Array = []) -> void:  # what's in r moves by; what crosses its edge stretches (unless not stretch). Only what's under those paths, if any; never what's at skip's
	var tops: Array = w.get_children() if under.is_empty() else under.map(func(p: String) -> Node: return _node(p))
	_skip = skip.map(func(p: String) -> Node: return _node(p))
	for c in tops:
		if c is Node3D:
			_mv(c, r, by, stretch)
	_skip = []
	_mv_data(data, r, by)


func _mv(n: Node3D, r: Region, by: Vector3, stretch: bool) -> void:
	if n in _skip:
		return
	var box := _bounds(n)
	if box.size == Vector3.ZERO:  # nothing to see: by where it is
		if r.has(n.global_position):
			n.global_position += by
		return
	if r.holds(box):
		n.global_position += by
		return
	if not r.meets(box):
		return
	if absf(box.size.dot(by.normalized())) < WHOLE and box.size.length() < 30.0:  # a thing: whole, by its middle
		if r.has(box.get_center()):
			n.global_position += by
		return
	if n is MeshInstance3D and stretch:
		_warp(n, r.has, by)
	for c in n.get_children():
		if c is Node3D:
			_mv(c, r, by, stretch)


func extend(path: String, axis: int, side: int, to: float) -> void:  # one end of a wall (the near end, side -1; the far, 1) out or in to there
	_extend(_node(path), axis, side, to)


func _extend(m: MeshInstance3D, axis: int, side: int, to: float) -> void:
	var b := m.global_transform * m.get_aabb()
	var at: float = b.position[axis] if side < 0 else b.end[axis]
	var by := Vector3.ZERO
	by[axis] = to - at
	_warp(m, func(p: Vector3) -> bool: return absf(p[axis] - at) < 0.3 * b.size[axis], by)


func _warp(m: MeshInstance3D, inside: Callable, by: Vector3) -> void:  # its vertices that are inside move by, the texture carried on along the way they went
	var xf := m.global_transform
	var inv := xf.affine_inverse()
	var dir := by.normalized()
	var mesh := ArrayMesh.new()
	for s in m.mesh.get_surface_count():
		var a := m.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uvs = a[Mesh.ARRAY_TEX_UV]
		var idx = a[Mesh.ARRAY_INDEX]
		var grad := PackedVector2Array()  # how its texture runs along dir at each vertex, from a triangle it's in
		grad.resize(vs.size())
		if uvs != null:
			var tri: PackedInt32Array = idx if idx != null else PackedInt32Array(range(vs.size()))
			var seen := {}
			for k in range(0, tri.size() - 2, 3):
				var g := _uv_per(xf * vs[tri[k]], xf * vs[tri[k + 1]], xf * vs[tri[k + 2]], uvs[tri[k]], uvs[tri[k + 1]], uvs[tri[k + 2]], dir)
				for j in 3:
					if not seen.has(tri[k + j]):
						seen[tri[k + j]] = true
						grad[tri[k + j]] = g
		for i in vs.size():
			var p := xf * vs[i]
			if inside.call(p):
				vs[i] = inv * (p + by)
				if uvs != null:
					uvs[i] += grad[i] * by.length()
		a[Mesh.ARRAY_VERTEX] = vs
		if uvs != null:
			a[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(s, m.mesh.surface_get_material(s))
	mesh.resource_name = m.mesh.resource_name
	m.mesh = mesh


static func _uv_per(p0: Vector3, p1: Vector3, p2: Vector3, t0: Vector2, t1: Vector2, t2: Vector2, dir: Vector3) -> Vector2:  # d(uv) along dir, across the triangle's face
	var e1 := p1 - p0
	var e2 := p2 - p0
	var n := e1.cross(e2)
	if n.length_squared() < 1e-12:
		return Vector2.ZERO
	var c := Basis(e1, e2, n).inverse() * dir  # dir, in the triangle's edges (and its normal, which the texture doesn't follow)
	return (t1 - t0) * c.x + (t2 - t0) * c.y


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


func _node(path: String) -> Node3D:
	var n := w.get_node_or_null(path)
	assert(n != null, "remodel: no %s in the level" % path)
	return n


func _all(r: Region, prefixes: Array) -> Array:  # the meshes wholly in r, under any of those paths
	var out := []
	for m: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		var p := str(w.get_path_to(m))
		if prefixes.any(func(x: String) -> bool: return p.begins_with(x)) and r.holds(m.global_transform * m.get_aabb()):
			out.append(m)
	return out


# ---- the same, in data/interact.json: a spot [x, y, z] or {x, z}; a box {x0, x1, z0, z1} or [x0, x1, z0, z1]; a door

const BOXES := ["boh", "lobby", "theater", "colliders"]

func _mv_data(v, r: Region, by: Vector3, key := "") -> void:
	if v is Dictionary:
		if v.has("alongX"):  # a door: all of it with its hinge
			if r.has(Vector3(v.x, 0, v.z)):
				_shift_all(v, by)
				v.at += by.z if v.alongX else by.x
				v.c += by.x if v.alongX else by.z
			return
		if v.has("x0") and v.has("z1"):
			_mv_box(v, ["x0", "x1", "z0", "z1"], r, by)
		elif v.has("x") and v.has("z") and (v.x is float) and r.has(Vector3(v.x, v.get("y", 0.0) if v.get("y") is float else 0.0, v.z)):
			v.x += by.x
			v.z += by.z
		for k: String in v:
			if v[k] is Dictionary or v[k] is Array:
				_mv_data(v[k], r, by, k)
	elif v is Array:
		var nums: bool = not v.is_empty() and v.all(func(e) -> bool: return e is float)
		if nums and v.size() == 3 and key != "size" and key != "q":
			if r.has(Vector3(v[0], v[1], v[2])):
				v[0] += by.x
				v[1] += by.y
				v[2] += by.z
		elif nums and v.size() == 4 and (key in BOXES or key == ""):
			_mv_box(v, [0, 1, 2, 3], r, by)
		elif not nums:
			for e in v:
				_mv_data(e, r, by, "" if key == "colliders" else key)


func _mv_box(b, k: Array, r: Region, by: Vector3) -> void:  # small: whole, by its middle; big: each side by where it is
	var mid := Vector3((b[k[0]] + b[k[1]]) / 2.0, 0, (b[k[2]] + b[k[3]]) / 2.0)
	var along: float = (b[k[1]] - b[k[0]]) if by.x != 0.0 else (b[k[3]] - b[k[2]])
	if along < WHOLE:
		if r.has(mid):
			for i in 2:
				b[k[i]] += by.x
				b[k[i + 2]] += by.z
		return
	for i in 2:
		if r.has(Vector3(b[k[i]], 0, mid.z)):
			b[k[i]] += by.x
		if r.has(Vector3(mid.x, 0, b[k[i + 2]])):
			b[k[i + 2]] += by.z


func _shift_all(v, by: Vector3) -> void:  # every x and z in it
	for k in (v.keys() if v is Dictionary else range(v.size())):
		var e = v[k]
		if e is Dictionary or e is Array:
			_shift_all(e, by)
		elif e is float and v is Dictionary:
			if k in ["x", "x0", "x1"]:
				v[k] += by.x
			elif k in ["z", "z0", "z1"]:
				v[k] += by.z


# ---- written back the way it came: one space a level, whole numbers whole, the rest as short as they'll go

func _json(v, ind := "") -> String:
	if v is Dictionary:
		if v.is_empty():
			return "{}"
		var parts := PackedStringArray()
		for k in v:
			parts.append(ind + " " + JSON.stringify(str(k)) + ": " + _json(v[k], ind + " "))
		return "{\n" + ",\n".join(parts) + "\n" + ind + "}"
	if v is Array:
		if v.is_empty():
			return "[]"
		var parts := PackedStringArray()
		for e in v:
			parts.append(ind + " " + _json(e, ind + " "))
		return "[\n" + ",\n".join(parts) + "\n" + ind + "]"
	if v is float:
		return _num(v)
	if v is bool:
		return "true" if v else "false"
	if v == null:
		return "null"
	return JSON.stringify(v)


static func _num(x: float) -> String:
	if x == floorf(x) and absf(x) < 1e15:
		return str(int(x))
	for d in range(1, 18):
		var s := String.num(x, d)
		if s.to_float() == x:
			return s
	return String.num(x, 17)
