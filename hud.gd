extends CanvasLayer
## What's on the screen: the day and the time top left (the first line of the web game's HUD, and whether the store's
## open), a crosshair, the line for whatever you're aiming at, toasts, and the day's log bottom left (the web
## game's logAct: here every toast goes in it; J folds it away).

var _clock := _label(26)
var _status := _label(14, Color(1, 0.83, 0))
var _cross := _label(18)
var _tip := _label(18)
var _toast := _label(20)
var _toast_t := 0.0
var _now := _label(14, Color(0.8, 0.9, 1.0))  # what's in the VCR and how far through, top right
var _call := _label(18, Color(1, 0.83, 0))
var _log := _label(13, Color(0.86, 0.9, 0.86))  # the day's log, bottom left: the last few things that happened (J folds it away)
var _rows: Array[String] = []
var _log_open := true

var _inv := _label(15)
var _bar := HBoxContainer.new()  # what you're carrying: nine slots
var _slots: Array = []
var _fade := ColorRect.new()
var _fade_text := _label(40)


func _label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _ready() -> void:
	_cross.text = "+"
	_fade.color = Color.BLACK
	_fade.visible = false
	add_child(_fade)
	move_child(_fade_text, -1)
	Clock.toast.connect(toast)
	_bar.add_theme_constant_override("separation", 6)
	_bar.visible = false
	add_child(_bar)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_J:
		_log_open = not _log_open


func tip(text: String) -> void:
	_tip.text = text


func fade(text: String) -> void:  # the screen gone black with a word on it ("" brings it back)
	_fade.visible = text != ""
	_fade_text.text = text


func inventory(slots: Array, sel: int) -> void:  # what you're carrying: a bar of nine slots, numbered, the one in hand lit (shown with two or more, or something stashed and your hand empty) (chores.js: invRender)
	_bar.visible = slots.size() > 1 or (slots.size() == 1 and sel < 0)
	if not _bar.visible:
		return
	if _slots.is_empty():
		for i in 9:
			var p := Panel.new()
			p.custom_minimum_size = Vector2(92, 62)
			var n := Label.new()
			n.position = Vector2(5, 1)
			n.add_theme_font_size_override("font_size", 12)
			p.add_child(n)
			var t := Label.new()
			t.position = Vector2(4, 17)
			t.size = Vector2(84, 32)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.clip_text = true
			t.add_theme_font_size_override("font_size", 11)
			p.add_child(t)
			var w := ColorRect.new()  # how far it's wound on / eaten: green left, red gone
			w.position = Vector2(4, 53)
			w.size = Vector2(84, 4)
			p.add_child(w)
			var used := ColorRect.new()
			used.position = Vector2(4, 53)
			used.color = Color("#d33")
			p.add_child(used)
			_bar.add_child(p)
			_slots.append(p)
	for i in 9:
		var p: Panel = _slots[i]
		var e: Dictionary = slots[i] if i < slots.size() else {}
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.55 if i == sel else 0.38)
		box.border_color = Color("#ffd400") if i == sel else Color(1, 1, 1, 0.25)
		box.set_border_width_all(3 if i == sel else 2)
		box.set_corner_radius_all(4)
		p.add_theme_stylebox_override("panel", box)
		p.position.y = -4.0 if i == sel else 0.0
		(p.get_child(0) as Label).text = str(i + 1)
		(p.get_child(1) as Label).text = ("%s%s" % ["▭ ", e.name]) if not e.is_empty() else ""
		var u: float = e.get("used", -1.0) if not e.is_empty() else -1.0
		(p.get_child(2) as ColorRect).visible = u >= 0.0
		(p.get_child(2) as ColorRect).color = Color("#3c3")
		(p.get_child(3) as ColorRect).visible = u > 0.0
		(p.get_child(3) as ColorRect).size = Vector2(84.0 * clampf(u, 0.0, 1.0), 4)


func call_box(text: String) -> void:  # a decision waiting on you ("" clears it)
	_call.text = text


func now_playing(text: String) -> void:
	_now.text = text


func toast(text: String) -> void:  # up top for a moment, and into the log
	_rows.append("%s  %s" % [Clock.fmt_clock(Clock.h), text.replace("\n", " ")])
	if _rows.size() > 60:
		_rows.pop_front()
	_log.text = "\n".join(_rows.slice(-7))
	_toast.text = text
	_toast_t = 4.0


func _process(dt: float) -> void:
	var s := get_viewport().get_visible_rect().size
	_clock.text = "%s %s" % [Clock.weekday(), Clock.fmt_clock(Clock.h)]
	_status.text = $"../Jellyfin".status
	_clock.position = Vector2(16, 8)
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_now.reset_size()
	_now.position = Vector2(s.x - _now.size.x - 16.0, 10.0)
	_status.position = Vector2(16, 44)
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0
	for l: Label in [_cross, _tip, _toast, _fade_text, _inv, _call]:
		l.reset_size()
	_call.position = Vector2((s.x - _call.size.x) / 2.0, s.y * 0.2)
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_log.visible = _log_open
	_log.reset_size()
	_log.position = Vector2(16.0, s.y - _log.size.y - 16.0)
	_fade.size = s
	_fade_text.visible = _fade.visible
	_fade_text.position = (s - _fade_text.size) / 2.0
	_cross.position = (s - _cross.size) / 2.0
	_inv.position = Vector2((s.x - _inv.size.x) / 2.0, s.y - 44.0)
	_bar.position = Vector2((s.x - (9 * 92 + 8 * 6)) / 2.0, s.y - 80.0)
	_tip.position = Vector2((s.x - _tip.size.x) / 2.0, s.y * 0.78)
	_toast.position = Vector2((s.x - _toast.size.x) / 2.0, s.y * 0.12)
