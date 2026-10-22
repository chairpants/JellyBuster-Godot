extends Node
## A night at the theater. A film put in the theater's VCR from the top gets the works before it: the house lights go
## down, the curtains part, a card asks you to silence your pager, then whatever the server plays before a film (its
## Cinema Mode's trailers and pre-rolls; failing that, the trailers it has for a few films picked at random), then
## OUR FEATURE PRESENTATION, and the film. E at the screen skips to the film. When it ends, the lights come up slowly
## and the curtains close. The picture menu's PRE-SHOW turns it off.
## The curtains: a pair of red velvet travellers hung in front of the proscenium, open whenever a film's on in here
## (lights.gd's house down: you're hearing it from this screen) or the pre-show's running; drawn to the sides, their
## folds bunch up. Lit by the room as the rest of it is (room.gd).

const CURTAIN := { "x": [-6.75, 1.0], "y": [-0.9, 3.86], "z": 47.45, "overlap": 0.12, "gathered": 0.16, "fold": 0.3, "cols": 72, "rows": 10, "color": "#8a1420", "speed": 0.22 }  # (the opening: -6.57..0.83 by -0.9..3.84; the pillars' fronts at 47.64)
const CARD := { "pagers": 6.0, "feature": 6.5, "fade": 1.0 }  # seconds each card's up, and how long each fades in and out
const TRAILERS := 2  # at most, before the feature

var busy := false  # the pre-show's running (tapes.gd: the VCR's E skips it; an intro's end is ours, not the tape's)
var preshow := false  # lights.gd: the house down for it
var _tape := {}
var _queue: Array = []  # the intros still to play (item ids)
var _step := ""  # "dim" | "pagers" | "intro" | "feature"
var _t := 0.0
var _open := 0.0  # the curtains: 0 shut, 1 drawn
var _panels: Array = []  # [the mesh instance, which way it opens (-1 left, 1 right), its material (the room's, once it's been made over)]
var _card := SubViewport.new()
var _cards := {}  # name -> its Control
var _shown := ""  # the card on the screens ("" none)

@onready var tapes: Node = $"../Tapes"
@onready var video: Node = $"../Video"
@onready var lights: Node = $"../Lights"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	_build_cards()
	await get_tree().physics_frame  # (the room's light's made by then: room.gd)
	for side in [-1, 1]:
		var mi := MeshInstance3D.new()
		mi.mesh = ArrayMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_panels.append([mi, side, null])
		_hang(_panels[-1], true)
	var room := get_node_or_null("../Room")
	if room:
		room.light(self)
	for p: Array in _panels:
		p[2] = p[0].mesh.surface_get_material(0)


func wants(tape: Dictionary) -> bool:  # into the theater's VCR: the works, if it's a film from the top
	return $"../Picture".tv.get("preshow", true) and tape.get("kind", "") == "movie" and tape.get("ep", 0) == 0 and tape.get("at", 0.0) < 60.0


func begin(tape: Dictionary) -> void:
	if tapes.playing != null:  # (what was in: out, where it had got to kept)
		Library.report(tapes.playing.tape.e[tapes.playing.idx][2], video.position)
		video.stop()
		tapes.playing = null
	_tape = tape
	busy = true
	preshow = true
	_queue = []
	_go("dim")
	hud.toast("Tonight: %s · E skips the pre-show" % tape.t)
	var id: String = tape.e[0][2]
	if await Library.resume_at(id) > 60.0:  # (part watched, in some app: straight to where they were)
		_feature()
		return
	var q: Array = await Library.intros(id)
	if q.is_empty():
		q = await Library.trailers(TRAILERS, id)
	if busy and _tape == tape:
		_queue = q.slice(0, TRAILERS + 2)


func skip() -> void:  # E at the screen: on with the film
	if busy:
		_feature()


func next() -> void:  # an intro's run out (or wouldn't play): the next, or the feature's card
	if not busy:
		return
	if _queue.is_empty():
		video.stop()
		_go("feature")
	else:
		var id: String = _queue.pop_front()
		_go("intro")
		video.play_url(Library.stream_url(id))
		tapes._screens_show(true)


func _feature() -> void:
	busy = false
	preshow = false
	_card_up("")
	if video.url != "":
		video.stop()
	var tape := _tape
	_tape = {}
	tapes.play_episode(0, tape)


func _go(step: String) -> void:
	_step = step
	_t = 0.0
	_card_up("pagers" if step == "pagers" else "feature" if step == "feature" else "")


func _process(dt: float) -> void:
	_t += dt
	match _step if busy else "":
		"dim":  # the lights going down, the curtains parting: the card's up as they do
			if _t > 0.5:
				_go("pagers")
		"pagers":
			if _t > CARD.pagers:
				next()
		"feature":
			if _t > CARD.feature:
				_feature()
	if _shown != "":  # the card in and out, and its light on the house
		var k := clampf(minf(_t, (CARD[_shown] - _t)) / CARD.fade, 0.0, 1.0)
		_cards[_shown].modulate.a = k
		var title: Control = _cards[_shown].get_node("Title")
		title.scale = Vector2.ONE * (1.0 + 0.03 * _t / CARD[_shown])
		video.tint = Color(0.32, 0.24, 0.12) * k
	var want := 1.0 if preshow or (not video.url.is_empty() and (lights.house < 0.6 or tapes.in_theater)) else 0.0
	if want > _open and lights.house > 0.35:
		want = _open  # (the lights go first, then the curtains)
	var was := _open
	_open = move_toward(_open, want, dt * CURTAIN.speed)
	if _open != was:
		for p: Array in _panels:
			_hang(p)


func _hang(p: Array, first := false) -> void:  # a panel, as far drawn as _open says: velvet in folds from its outer edge, bunching as it gathers
	var side: int = p[1]
	var x0: float = CURTAIN.x[0] if side < 0 else CURTAIN.x[1]  # its outer edge
	var mid := (CURTAIN.x[0] + CURTAIN.x[1]) / 2.0
	var w := absf(mid - x0) + CURTAIN.overlap
	var o := smoothstep(0.0, 1.0, _open)
	var span := w * lerpf(1.0, CURTAIN.gathered, o)
	var amp := lerpf(0.035, 0.09, o)
	var k := TAU / CURTAIN.fold
	var cols: int = CURTAIN.cols
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols_c := PackedColorArray()
	var idx := PackedInt32Array()
	var base := Color(CURTAIN.color)
	for i in cols + 1:
		var s := float(i) / cols  # (along the cloth, from the outer edge)
		var x := x0 - side * s * span
		var ph := s * w * k
		var z: float = CURTAIN.z - amp * sin(ph)
		var slope := -amp * cos(ph) * k * w / span  # dz/dx, along the gathered cloth
		var n := Vector3(slope * -side, 0.0, -1.0).normalized()
		var shade := 0.72 + 0.28 * (0.5 + 0.5 * sin(ph))  # (deeper in the valleys)
		for j in 2:
			var y: float = CURTAIN.y[0] if j == 0 else CURTAIN.y[1]
			verts.append(Vector3(x, y, z))
			norms.append(n)
			cols_c.append(Color(shade, shade, shade))
	for i in cols:
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2] if side > 0 else [a, a + 2, a + 1, a + 1, a + 2, a + 3])  # (facing the house: lit from it)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols_c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = p[0].mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if first:
		var m := StandardMaterial3D.new()
		m.albedo_color = base
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, m)
	elif p[2] != null:
		mesh.surface_set_material(0, p[2])


func _build_cards() -> void:  # the cards, drawn in a viewport of the picture's own shape: dark, a glow behind, the words
	_card.size = Vector2i(1080, 720)
	_card.disable_3d = true
	_card.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_card)
	var black := ColorRect.new()  # (under the cards as they fade: dark between them, not the viewport's grey)
	black.color = Color.BLACK
	black.size = Vector2(_card.size)
	_card.add_child(black)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "serif"])
	for c: Array in [["pagers", "JELLYVAULT THEATER", "PLEASE SILENCE\nYOUR PAGERS", "and enjoy the show", Color(0.95, 0.9, 0.82)],
			["feature", "TONIGHT", "OUR FEATURE\nPRESENTATION", "", Color(1.0, 0.8, 0.35)]]:
		var root := Control.new()
		root.size = Vector2(_card.size)
		root.visible = false
		_card.add_child(root)
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.012, 0.02)
		bg.size = root.size
		root.add_child(bg)
		var glow := TextureRect.new()
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color(0.45, 0.12, 0.08, 0.6))
		g.gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		glow.texture = g
		glow.size = root.size
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		root.add_child(glow)
		for line: Array in [["Over", c[1], 34, 150.0, Color(0.85, 0.7, 0.45)], ["Title", c[2], 96, 230.0, c[4]], ["Under", c[3], 40, 520.0, Color(0.9, 0.88, 0.85)]]:
			var l := Label.new()
			l.name = line[0]
			l.text = line[1]
			var ls := LabelSettings.new()
			ls.font = serif
			ls.font_size = line[2]
			ls.font_color = line[4]
			ls.line_spacing = -6.0
			ls.shadow_color = Color(0, 0, 0, 0.6)
			ls.shadow_size = 6
			l.label_settings = ls
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(root.size.x, 240)
			l.position = Vector2(0, line[3])
			l.pivot_offset = l.size / 2.0
			root.add_child(l)
		_cards[c[0]] = root


func _card_up(which: String) -> void:  # that card on the screens ("": off them, back to whatever's playing)
	for k in _cards:
		_cards[k].visible = k == which
	_shown = which
	if which == "":
		_card.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if which == "feature":
		_cards.feature.get_node("Under").text = "%s%s" % [_tape.get("t", ""), " (%d)" % _tape.year if _tape.get("year", 0) else ""]
	_card.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tapes._screens_show(true, _card.get_texture())
