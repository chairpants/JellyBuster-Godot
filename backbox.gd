extends Node
## The back of a tape's box: laid out like a rental's, from what Jellyfin knows (Library.details), drawn once into a
## SubViewport and kept as a texture. The title's backdrop (a season: its series') behind it all, darkened so the words
## read; the logo (else the title), the tagline, the top-billed faces, the blurb, the run time and rating, a season's
## episodes, the billing block, a barcode. The demo library: the same box, with what little a made-up tape has.
## build(tape) -> Texture2D, cached for the last few tapes looked at, and on disk (user://backs) once drawn, so it's
## there at once next time. Its pictures all come at once, not one after another. tapes.gd asks for it as the crosshair
## settles on a tape, before it's even picked up, and turns the box over with R.

const SIZE := Vector2i(640, 1170)  # the box's back, 0.105 x 0.192 m (store.gd TAPE): laid out at this size...
const SCALE := 2  # ...drawn at this many times it (turned over, it fills most of a 1600-tall screen)
const PAD := 34
const KEEP := 24  # backs kept in memory, most recent
const LOOK := "b3"  # the layout's version: change it when the box's look changes, and the backs kept on disk are drawn afresh
const EPS_LISTED := 10
const BLURB := { "movie": 520, "series": 300 }  # characters: about what fits, cut back to a whole sentence
const GOLD := Color("#ffd400")
const RATINGS := { "G": "GENERAL AUDIENCES", "PG": "PARENTAL GUIDANCE SUGGESTED", "PG-13": "PARENTS STRONGLY CAUTIONED", "R": "RESTRICTED", "NC-17": "NO ONE 17 AND UNDER ADMITTED", "NR": "NOT RATED" }

var _done := {}  # tape id -> its back
var _order: Array = []
var _making := {}  # tape id -> true while it's being drawn
var _saving: Array[int] = []  # backs being written to disk (WorkerThreadPool tasks): finished before the game closes


func _exit_tree() -> void:
	for task in _saving:
		WorkerThreadPool.wait_for_task_completion(task)


func build(t: Dictionary) -> Texture2D:
	if _done.has(t.id):
		_order.erase(t.id)
		_order.append(t.id)
		return _done[t.id]
	while _making.has(t.id):  # (asked again while it's still coming: wait for that one)
		await get_tree().process_frame
		if _done.has(t.id):
			return _done[t.id]
	_making[t.id] = true
	var path := "user://backs/%s_%s.jpg" % [LOOK, t.id]
	var tex: Texture2D
	if not Library.demo and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	else:
		var d: Dictionary = await Library.details(t)
		var cast: Array = d.get("people", []).filter(func(p: Dictionary) -> bool: return p.type == "Actor" and p.img).slice(0, 4)
		var calls: Array[Callable] = [  # every picture at once
			func() -> Image: return await Library.image(d.get("backdrop", ""), "Backdrop", 1280),
			func() -> Image: return await Library.image(d.get("logo", ""), "Logo", 1000),
		]
		for p: Dictionary in cast:
			calls.append(func() -> Image: return await Library.image(p.id, "Primary", 300))
		var got: Array = await _all(calls)
		var faces := []
		for i in cast.size():
			faces.append([cast[i], got[2 + i]])
		tex = await _draw(t, d, { "backdrop": got[0], "logo": got[1], "faces": faces })
		if not Library.demo:
			DirAccess.make_dir_recursive_absolute("user://backs")
			var img := tex.get_image()
			_saving.append(WorkerThreadPool.add_task(func() -> void: img.save_jpg(path, 0.9)))  # (off the main thread: no hitch)
	_making.erase(t.id)
	_done[t.id] = tex
	_order.append(t.id)
	while _order.size() > KEEP:
		_done.erase(_order.pop_front())
	return tex


signal _one_done


func _all(calls: Array[Callable]) -> Array:  # each call's result, in order, all of them running at once
	var out := []
	out.resize(calls.size())
	var left := [calls.size()]
	for i in calls.size():
		(func() -> void:
			out[i] = await calls[i].call()
			left[0] -= 1
			_one_done.emit()).call()
	while left[0] > 0:
		await _one_done
	return out


func _draw(t: Dictionary, d: Dictionary, art: Dictionary) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = SIZE * SCALE
	vp.size_2d_override = SIZE
	vp.size_2d_override_stretch = true
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var root := Control.new()
	root.size = SIZE
	vp.add_child(root)
	var bg := ColorRect.new()  # (no backdrop: the section's colour, darkened)
	bg.color = Color.from_hsv(float(hash(t.c) % 360) / 360.0, 0.5, 0.25)
	bg.size = SIZE
	root.add_child(bg)
	if art.backdrop != null:
		var b := TextureRect.new()
		b.texture = ImageTexture.create_from_image(art.backdrop)
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		b.size = SIZE
		root.add_child(b)
	var shade := TextureRect.new()  # the overlay: see-through at the top, where the picture shows, near black where the small print is
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.45))
	g.set_color(1, Color(0, 0, 0, 0.9))
	g.add_point(0.35, Color(0, 0, 0, 0.72))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.size = SIZE
	root.add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(PAD, PAD)
	col.size = Vector2(SIZE.x - PAD * 2, SIZE.y - PAD * 2)
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	var year := int(d.get("year", t.get("year", 0)))
	var title: String = d.get("title", t.t.get_slice(":", 0) if t.kind == "series" else t.t)
	if art.logo != null:
		var l := TextureRect.new()
		l.texture = ImageTexture.create_from_image(art.logo)
		l.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		l.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		l.custom_minimum_size = Vector2(0, 150)
		col.add_child(l)
	else:
		col.add_child(_label(title.to_upper(), 58, Color.WHITE, _font(900), HORIZONTAL_ALIGNMENT_CENTER, 2))
	var season: String = d.get("season", t.t.get_slice(": ", 1) if t.kind == "series" else "")
	if season != "":
		col.add_child(_label(season.to_upper(), 30, GOLD, _font(800), HORIZONTAL_ALIGNMENT_CENTER))
	if d.get("tagline", "") != "":
		col.add_child(_label(d.tagline, 26, GOLD, _font(600, true), HORIZONTAL_ALIGNMENT_CENTER, 2))

	if not art.faces.is_empty():  # the top of the bill, faces and names
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		for f: Array in art.faces:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(128, 0)
			cell.add_theme_constant_override("separation", 3)
			var frame := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.1, 0.1, 0.1)
			sb.border_color = Color(1, 1, 1, 0.9)
			sb.set_border_width_all(3)
			sb.set_content_margin_all(3)
			frame.add_theme_stylebox_override("panel", sb)
			var face := TextureRect.new()
			face.custom_minimum_size = Vector2(122, 146)
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			face.clip_contents = true
			if f[1] != null:
				face.texture = ImageTexture.create_from_image(f[1])
			frame.add_child(face)
			cell.add_child(frame)
			cell.add_child(_label(f[0].name.to_upper(), 17, Color.WHITE, _font(800), HORIZONTAL_ALIGNMENT_CENTER, 2))
			if f[0].role != "":
				cell.add_child(_label(f[0].role.get_slice(" / ", 0), 15, Color(0.8, 0.8, 0.8), _font(400, true), HORIZONTAL_ALIGNMENT_CENTER, 1))
			row.add_child(cell)
		col.add_child(row)

	var blurb: String = d.get("overview", "")
	if blurb == "":
		blurb = "%s. Rewind before returning." % ", ".join(t.get("genres", [t.c]))
	var b := _label(_fit(blurb, BLURB[t.kind]), 22, Color.WHITE, _font(500), HORIZONTAL_ALIGNMENT_FILL)
	col.add_child(b)

	if t.kind == "series":  # what's on the tape
		var eps: Array = t.e
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 1)
		for i in mini(eps.size(), EPS_LISTED):
			var parts: PackedStringArray = eps[i][1].split(" - ")
			var name: String = " - ".join(parts.slice(2)) if parts.size() > 2 else eps[i][1]
			var e := _label("%d. %s" % [i + 1, name], 15, Color(0.9, 0.9, 0.9), _font(500), HORIZONTAL_ALIGNMENT_LEFT, 1)
			e.custom_minimum_size = Vector2((SIZE.x - PAD * 2 - 18) / 2.0, 0)
			grid.add_child(e)
		col.add_child(_label("%d EPISODES ON THIS TAPE" % eps.size() + ("  ·  FIRST %d LISTED" % EPS_LISTED if eps.size() > EPS_LISTED else ""), 16, GOLD, _font(800), HORIZONTAL_ALIGNMENT_LEFT))
		col.add_child(grid)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var facts := HBoxContainer.new()  # rating, then the run of facts
	facts.add_theme_constant_override("separation", 14)
	var rating := _rating(d.get("rating", ""))
	if rating != "":
		facts.add_child(_rating_badge(rating))
	var minutes: int = d.get("minutes", 0)
	if minutes == 0:
		for e: Array in t.e:
			minutes += roundi(e[3] / 60.0)
	var bits := []
	if year > 0:
		bits.append(str(year))
	if minutes > 0:
		bits.append("%d MIN" % minutes)
	bits.append_array(d.get("genres", []).slice(0, 2).map(func(s: String) -> String: return s.to_upper()))
	bits.append("STEREO")
	var fl := _label("  ·  ".join(bits), 17, Color.WHITE, _font(700), HORIZONTAL_ALIGNMENT_LEFT, 2)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	facts.add_child(fl)
	col.add_child(facts)
	var scores := []
	if d.get("stars", 0.0) > 0.0:
		var s: float = d.stars / 2.0
		scores.append("★".repeat(roundi(s)) + "☆".repeat(5 - roundi(s)) + "  %.1f/10" % d.stars)
	if d.get("critics", 0) > 0:
		scores.append("CRITICS %d%%" % d.critics)
	if not scores.is_empty():
		col.add_child(_label("     ".join(scores), 20, GOLD, _font(800), HORIZONTAL_ALIGNMENT_LEFT))

	var billing := _billing(title, d)  # the credits, small and condensed, as every box had them
	if billing != "":
		var bl := _label(billing, 13, Color(0.85, 0.85, 0.85), _narrow(), HORIZONTAL_ALIGNMENT_CENTER, 5)
		bl.add_theme_constant_override("line_spacing", -2)
		col.add_child(bl)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	var bar := TextureRect.new()
	bar.texture = ImageTexture.create_from_image(_barcode(t.id))
	foot.add_child(bar)
	var studio: String = (d.get("studios", []) + ["JellyVault Home Video"])[0]
	var fine := _label("© %s %s. All rights reserved. Licensed for home viewing only. Any public performance, copying or other use is strictly prohibited. Be kind, please rewind." % [str(year) if year > 0 else "", studio], 11, Color(0.7, 0.7, 0.7), _font(400), HORIZONTAL_ALIGNMENT_LEFT, 5)
	fine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fine)
	var vhs := _label("VHS", 30, Color.WHITE, _font(900, true), HORIZONTAL_ALIGNMENT_CENTER, -1)
	var vb := PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0)
	sb2.border_color = Color.WHITE
	sb2.set_border_width_all(3)
	sb2.content_margin_left = 10
	sb2.content_margin_right = 10
	vb.add_theme_stylebox_override("panel", sb2)
	vb.add_child(vhs)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(vb)
	col.add_child(foot)

	await RenderingServer.frame_post_draw  # (laid out, then drawn: twice, so the containers have settled first)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _fit(text: String, n: int) -> String:  # no more than n characters, ending on a sentence if one ends late enough (else on a word, and …)
	text = text.strip_edges()
	if text.length() <= n:
		return text
	var cut := text.left(n)
	var end := maxi(cut.rfind(". "), maxi(cut.rfind("! "), cut.rfind("? ")))
	return cut.left(end + 1) if end > n / 2 else cut.left(cut.rfind(" ")) + "…"


func _billing(title: String, d: Dictionary) -> String:  # "STUDIO presents A DIRECTOR film TITLE  ACTORS  music by ..." from Jellyfin's people
	var of := func(kind: String, n: int) -> String: return "  ".join(d.get("people", []).filter(func(p: Dictionary) -> bool: return p.type == kind).slice(0, n).map(func(p: Dictionary) -> String: return p.name.to_upper()))
	var parts := []
	if not d.get("studios", []).is_empty():
		parts.append("%s PRESENTS" % d.studios[0].to_upper())
	var dir: String = of.call("Director", 1)
	if dir != "":
		parts.append("A %s FILM" % dir)
	parts.append("\"%s\"" % title.to_upper())
	for p: Array in [["", "Actor", 8], ["MUSIC BY", "Composer", 1], ["WRITTEN BY", "Writer", 3], ["PRODUCED BY", "Producer", 3], ["DIRECTED BY", "Director", 2]]:
		var who: String = of.call(p[1], p[2])
		if who != "":
			parts.append((p[0] + " " + who).strip_edges())
	return "  ·  ".join(parts) if parts.size() > 1 else ""


static func _rating(r: String) -> String:  # Jellyfin's rating, tidied: "US:PG-13 / US:Rated PG-13" -> "PG-13", "Not Rated" / "Unrated" -> "NR"
	r = r.get_slice(" / ", 0).strip_edges()
	if ":" in r:
		r = r.get_slice(":", 1)  # (the country)
	r = r.trim_prefix("Rated ").strip_edges().to_upper()
	return "NR" if r in ["NOT RATED", "UNRATED"] else r


func _rating_badge(r: String) -> Control:  # the MPAA box (a TV rating: the same box, its own words)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(5)
	box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_label(r, 34 if r.length() <= 5 else 24, Color.WHITE, _font(900), HORIZONTAL_ALIGNMENT_CENTER, -1))
	var words: String = RATINGS.get(r, "TV PARENTAL GUIDELINES" if r.begins_with("TV") else "")
	if words != "":
		var w := _label(words, 9, Color.WHITE, _font(700), HORIZONTAL_ALIGNMENT_CENTER, 3)
		w.custom_minimum_size = Vector2(96, 0)
		v.add_child(w)
	box.add_child(v)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return box


func _barcode(seed_text: String) -> Image:  # a UPC-looking barcode, the same every time for the same tape
	var img := Image.create(150, 70, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var x := 8
	while x < 142:
		var w := rng.randi_range(1, 3)
		var tall := x < 12 or x > 136 or absi(x - 75) < 3
		img.fill_rect(Rect2i(x, 6, w, 52 if tall else 46), Color.BLACK)
		x += w + rng.randi_range(1, 3)
	return img


func _label(text: String, px: int, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, lines := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	if lines == 0 or lines > 1:  # (-1: one line, never squeezed)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if lines > 0:
		l.max_lines_visible = lines
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if lines == 1:
			l.clip_text = true
	return l


func _font(weight: int, italic := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Liberation Sans", "Arial", "DejaVu Sans", "sans-serif"])
	f.font_weight = weight
	f.font_italic = italic
	return f


func _narrow() -> SystemFont:  # the billing block's tall, squeezed letters
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Liberation Sans Narrow", "Nimbus Sans Narrow", "Arial Narrow", "DejaVu Sans Condensed", "sans-serif"])
	f.font_weight = 700
	return f
