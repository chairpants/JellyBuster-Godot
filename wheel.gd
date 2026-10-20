extends CanvasLayer
## The time and weather wheel (hold F, player.gd): a ring of choices round the middle of the screen, the mouse moving a
## pointer of its own round it (the real one stays captured: no window scaling or DPI between the hand and the pick), the
## way it points what's picked. Click one and it's so (the clock jumps to that hour; the weather's that, now), and the wheel's gone.
## Right-click or Esc: gone, nothing changed.

const OPTIONS := [  # [label, kind, value]
	["8 AM", "time", 8.0], ["NOON", "time", 12.0], ["4 PM", "time", 16.0], ["8 PM", "time", 20.0], ["MIDNIGHT", "time", 24.0],
	["CLEAR", "sky", "clear"], ["RAIN", "sky", "rain"], ["STORM", "sky", "storm"], ["SNOW", "sky", "snow"], ["FOG", "sky", "fog"],
]
const R_IN := 80.0
const R_OUT := 250.0
const SKY := { 8.0: Color("#f4a259"), 12.0: Color("#5aa9e6"), 16.0: Color("#e9c46a"), 20.0: Color("#6d4c8f"), 24.0: Color("#1b2a4a") }  # each hour's sky, behind its picture

var _ring := Control.new()
var _hover := -1
var _aim := Vector2.ZERO  # the pointer, from the middle (held to the ring's edge)


func _ready() -> void:
	layer = 5
	visible = false
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


func open() -> void:
	visible = true
	_hover = -1
	_aim = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ring.queue_redraw()


func close() -> void:
	visible = false


func _input(e: InputEvent) -> void:  # (before anything else gets it, while it's up)
	if not visible:
		return
	if e is InputEventMouseMotion:
		_aim = (_aim + e.relative).limit_length(R_OUT)
		_hover = -1 if _aim.length() < R_IN * 0.5 else int(fposmod(_aim.angle() + PI / 2.0 + _step() / 2.0, TAU) / _step())  # (past a little dead zone, any distance out: the direction)
		_ring.queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and _hover >= 0:
			_pick(OPTIONS[_hover])
		close()
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()


func _pick(o: Array) -> void:
	if o[1] == "time":
		Clock.warp = 0.0
		Clock.h = o[2]
		return
	var w: Node = get_node("../Weather")
	match o[2]:
		"clear": w.set_now("clear")
		"rain": w.set_now("rain", 0.6)
		"storm": w.set_now("rain", 1.0, 0.25)
		"snow": w.set_now("snow", 0.8)
		"fog": w.set_now("clear", 0.0, 0.85)


func _step() -> float:
	return TAU / OPTIONS.size()


func _draw_ring() -> void:
	var c := _ring.get_viewport_rect().size / 2.0
	var font := ThemeDB.fallback_font
	for i in OPTIONS.size():
		var a0 := -PI / 2.0 + (i - 0.5) * _step()  # (the first at the top, round clockwise)
		var a1 := a0 + _step()
		var pts := PackedVector2Array()
		for k in 13:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 12.0)) * R_OUT)
		for k in 13:
			pts.append(c + Vector2.from_angle(lerpf(a1, a0, k / 12.0)) * R_IN)
		var o: Array = OPTIONS[i]
		var base := Color(0.08, 0.1, 0.16, 0.82) if o[1] == "time" else Color(0.12, 0.08, 0.06, 0.82)
		_ring.draw_colored_polygon(pts, base.lightened(0.35) if i == _hover else base)
		pts.append(pts[0])
		_ring.draw_polyline(pts, Color(1, 0.83, 0, 0.9) if i == _hover else Color(1, 1, 1, 0.25), 3.0 if i == _hover else 1.5, true)
		var mid := c + Vector2.from_angle((a0 + a1) / 2.0) * (R_IN + R_OUT) / 2.0
		_icon(o, mid + Vector2(0, -14), 1.25 if i == _hover else 1.0)
		var tw := font.get_string_size(o[0], HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		_ring.draw_string_outline(font, mid + Vector2(-tw / 2.0, 46), o[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		_ring.draw_string(font, mid + Vector2(-tw / 2.0, 46), o[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.83, 0) if i == _hover else Color.WHITE)
	_ring.draw_circle(c + _aim, 7.0, Color(1, 0.83, 0))
	_ring.draw_arc(c + _aim, 7.0, 0, TAU, 16, Color.BLACK, 2.0, true)
	var title := "TIME  ·  WEATHER"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
	_ring.draw_string_outline(font, c + Vector2(-tw / 2.0, 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
	_ring.draw_string(font, c + Vector2(-tw / 2.0, 6), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.83, 0))


func _icon(o: Array, at: Vector2, s: float) -> void:  # each option's picture, drawn: the hour's sky with the sun or moon where it'd be; the weather's own
	var sun := Color("#ffd23f")
	var cloud := Color("#dfe6ee")
	if o[1] == "time":
		var h: float = o[2]
		_ring.draw_circle(at, 30.0 * s, SKY[h])
		_ring.draw_arc(at, 30.0 * s, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)
		_ring.draw_line(at + Vector2(-30, 10) * s, at + Vector2(30, 10) * s, Color(0, 0, 0, 0.35), 2.0)  # (the horizon)
		var day := h >= 6.0 and h <= 18.0
		var up := sin((h - 6.0) / 12.0 * PI) if day else sin((h - 18.0) / 12.0 * PI)  # how high: from the horizon to overhead and back
		var across := cos((h - 6.0) / 12.0 * PI) if day else cos((h - 18.0) / 12.0 * PI)
		var p := at + Vector2(-across * 18.0, 10.0 - up * 24.0) * s
		if day:
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				_ring.draw_line(p + d * 10.0 * s, p + d * 15.0 * s, sun, 2.0, true)
			_ring.draw_circle(p, 8.0 * s, sun)
		else:
			_ring.draw_circle(p, 9.0 * s, Color("#f1f0e0"))
			_ring.draw_circle(p + Vector2(4, -3) * s, 8.0 * s, SKY[h])  # (a crescent)
			for star: Vector2 in [Vector2(-14, -14), Vector2(12, -18), Vector2(16, -2), Vector2(-20, 0)]:
				_ring.draw_circle(at + star * s, 1.4 * s, Color.WHITE)
		return
	match o[2]:
		"clear":
			for k in 12:
				var d := Vector2.from_angle(k * TAU / 12.0)
				_ring.draw_line(at + d * 16.0 * s, at + d * 25.0 * s, sun, 3.0, true)
			_ring.draw_circle(at, 13.0 * s, sun)
		"rain", "storm", "snow":
			var dark: bool = o[2] == "storm"
			var cc := cloud.darkened(0.45) if dark else cloud
			for b: Vector3 in [Vector3(-12, -4, 10), Vector3(0, -10, 13), Vector3(13, -4, 10), Vector3(0, 0, 11)]:
				_ring.draw_circle(at + Vector2(b.x, b.y) * s, b.z * s, cc)
			_ring.draw_rect(Rect2(at + Vector2(-22, -4) * s, Vector2(44, 12) * s), cc)
			if o[2] == "snow":
				for f: Vector2 in [Vector2(-14, 18), Vector2(0, 24), Vector2(14, 18), Vector2(-7, 30), Vector2(8, 32)]:
					for k in 3:
						var d := Vector2.from_angle(k * PI / 3.0) * 4.0 * s
						_ring.draw_line(at + f * s - d, at + f * s + d, Color.WHITE, 1.5, true)
			else:
				for x: float in [-14.0, -4.0, 6.0, 16.0]:
					_ring.draw_line(at + Vector2(x, 14) * s, at + Vector2(x - 5, 28) * s, Color("#6fb7ff"), 2.5, true)
			if dark:
				var bolt := PackedVector2Array([Vector2(2, 8), Vector2(-6, 22), Vector2(0, 22), Vector2(-4, 34), Vector2(9, 17), Vector2(2, 17), Vector2(7, 8)])
				for k in bolt.size():
					bolt[k] = at + bolt[k] * s
				_ring.draw_colored_polygon(bolt, sun)
		"fog":
			for k in 4:
				var y := (-14.0 + k * 9.0) * s
				var off := (6.0 if k % 2 else -6.0) * s
				_ring.draw_line(at + Vector2(-22 * s + off, y), at + Vector2(22 * s + off, y), Color(0.85, 0.88, 0.92, 0.9 - k * 0.12), 4.0, true)
