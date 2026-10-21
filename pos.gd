extends CanvasLayer
## The register's terminal: VaultBuster's POS/NET (VaultBusterGodot's pos.gd), cut down to finding a tape. E on the
## register logs you in. Type a selection or a command and ENTER; ESC (or a right-click) goes back a screen, and off
## from the main menu; F10 logs off. The store keeps running while you're at it.
## Inventory: the title search, the sections, what's in the VCR, what you're carrying. A title's own screen says where
## it is; S (or a click on the line) lights its slot on the shelf and logs you off to go and get it (tapes.gd: guide).
## The arrows walk a list's records or the menu's lines (ENTER opens the highlighted one), and the mouse does the same:
## what it's over is highlighted, a click picks it or presses a key on the bar, the wheel turns pages.
## Painted as VaultBuster paints it: the blue screen, its colours, the frame, the logo, the key bar, scanlines (the
## font's VT323, in fonts/), on a screen over the game; and on the register's own monitor on the counter.
## Not here: VaultBuster's members, rentals, the sale window, supplies, staff, the gates (there's none of it here).

const COLS := 80
const BODY := 22  # body rows under the header

var open := false

var _screen := {}  # { title, lines: Callable -> Array[String], prompt, submit: Callable(String), pager, pick, menu, bar, acts }
var _stack: Array = []
var _input := ""
var _msg := ""
var _blink := 0.0
var _over := Vector2i(-1, -1)  # the cell the mouse is over
var _dim := ColorRect.new()

@onready var tapes: Node = $"../Tapes"
@onready var player: CharacterBody3D = $"../Player"
@onready var _at: Vector3 = Vector3(Level.data().things.register.pos[0], Level.data().things.register.pos[1], Level.data().things.register.pos[2])


func _ready() -> void:
	layer = 7  # (over the picture menu and the cover search, both on 6)
	visible = false
	_dim.color = Color(0, 0, 0, 0.6)  # the store, dimmed behind it
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE  # (the clicks come to _unhandled_input)
	add_child(_view)
	_view.draw.connect(func() -> void: _paint(_view, _cell))
	_mon_build.call_deferred()
	_font = load(FONT) if ResourceLoader.exists(FONT) else null
	if _font == null:  # (not imported yet: straight off the disk; and with no file at all, whatever monospace there is)
		_font = FontFile.new()
		if _font.load_dynamic_font(FONT) != OK:
			_font = SystemFont.new()
			_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	if _font is FontFile:  # (what VT323 hasn't got, the title bar's arrow for one: from whatever monospace there is)
		var more := SystemFont.new()
		more.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		_font.fallbacks = [more]
	var grad := Gradient.new()  # the tube's falloff toward its corners
	grad.offsets = PackedFloat32Array([0.337, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)])
	_vignette.gradient = grad
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(0.5, 1.45)
	for k: String in MARKS:
		_re[k] = RegEx.create_from_string(MARKS[k])


# ---- formatting, and the store's tapes

func L(s, n: int) -> String:
	return str(s).rpad(n).left(n)


func R(s, n: int) -> String:
	return str(s).lpad(n).right(n)


func _date() -> String:
	var d := Clock.date()
	return "%02d/%02d/%s" % [d.month, d.day, str(d.year).right(2)]


func _library() -> String:
	return "DEMO LIBRARY" if Library.demo else "JELLYFIN"


func _status(t: Dictionary) -> String:
	if tapes.playing != null and is_same(tapes.playing.tape, t):
		return "IN THE VCR"
	if tapes.inv.any(func(x: Dictionary) -> bool: return is_same(x, t)):
		return "IN YOUR HANDS"
	return "OFF THE SHELF" if t.get("off", false) else "ON SHELF"


func _on_shelf() -> int:
	return tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.get("off", false)).size()


func _year(t: Dictionary) -> String:
	return str(int(t.get("year", 0))) if int(t.get("year", 0)) > 0 else "-"


func _hm(secs: float) -> String:
	return "%dH %02dM" % [int(secs) / 3600, int(secs) / 60 % 60] if secs >= 3600.0 else "%dM" % (int(secs) / 60)


func _sections() -> Array:  # the store's, in its order, those with tapes on them
	var out: Array = []
	for s: String in Library.shelves("movie") + Library.shelves("series"):
		if not s in out and tapes.tapes.any(func(t: Dictionary) -> bool: return t.c == s):
			out.append(s)
	return out


# ---- screens

func _go(s: Dictionary) -> void:
	if not _screen.is_empty():
		_stack.append(_screen)
	_screen = s
	_input = ""
	_msg = ""
	_hits.clear()  # (what was clickable on the last screen isn't, till this one's drawn)


func _back() -> void:
	_input = ""
	_msg = ""
	_hits.clear()
	if _stack.is_empty():
		log_off()
	else:
		_screen = _stack.pop_back()


func _list(title: String, head: String, items: Array, row: Callable, on_pick: Callable, empty := "NO RECORDS FOUND.") -> Dictionary:  # a paged, numbered pick list
	var per := BODY - 2
	var page := [0]
	var pages := maxi(1, ceili(float(items.size()) / per))
	var pick := { "cur": 0, "n": items.size() if on_pick.is_valid() else 0, "per": per, "page": page }  # the arrows walk the records (turning pages as needed); ENTER opens the highlighted one
	return { "title": "%s  (%d RECORD%s)" % [title, items.size(), "" if items.size() == 1 else "S"], "pager": true, "prompt": "RECORD # OR N/P" if on_pick.is_valid() else "N/P OR ESC", "pick": pick,
		"lines": func() -> Array:
			if items.is_empty():
				return ["", " " + empty]
			var out: Array = [HEAD + head]
			for i in range(page[0] * per, mini(items.size(), page[0] * per + per)):
				out.append(row.call(items[i], i + 1))
			while out.size() < per + 1:
				out.append("")
			out.append(R("PAGE %d OF %d " % [page[0] + 1, pages], COLS - 1))
			return out,
		"submit": func(v: String) -> void:
			if v == "N":
				if page[0] < pages - 1:
					page[0] += 1
					pick.cur = page[0] * per
				else:
					_msg = "LAST PAGE."
			elif v == "P":
				if page[0] > 0:
					page[0] -= 1
					pick.cur = page[0] * per
				else:
					_msg = "FIRST PAGE."
			elif on_pick.is_valid() and v.is_valid_int() and int(v) >= 1 and int(v) <= items.size():
				on_pick.call(items[int(v) - 1])
			else:
				_msg = "INVALID SELECTION." }


func _ask(title: String, label: String, help: String, on_value: Callable) -> Dictionary:
	return { "title": title, "prompt": label, "lines": func() -> Array: return ["", " " + help],
		"submit": func(v: String) -> void:
			if v != "":
				on_value.call(v)
			else:
				_msg = "ENTRY REQUIRED." }


func _info(title: String, lines: Callable) -> Dictionary:
	return { "title": title, "prompt": "ESC TO RETURN", "lines": lines, "submit": func(_v: String) -> void: _back() }


var TITLE_HEAD := "      %s%s%s" % [L("TITLE", 34), L("SECTION", 19), "YEAR  STATUS"]


func _title_row(t: Dictionary, n: int) -> String:
	return " %s  %s %s %s  %s" % [R(n, 3), L(t.t.to_upper(), 33), L(t.c.to_upper(), 18), R(_year(t), 4), L(_status(t), 13)]


func _titles(title: String, items: Array, empty := "NO RECORDS FOUND.") -> Dictionary:
	return _list(title, TITLE_HEAD, items, _title_row, _title_detail, empty)


func _find(q: String) -> Array:
	var out: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return q in t.t.to_upper())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("sort", a.t)).naturalnocasecmp_to(str(b.get("sort", b.t))) < 0)
	return out


func _title_detail(t: Dictionary) -> void:
	var on: Array = tapes.tapes.filter(func(x: Dictionary) -> bool: return x.c == t.c)  # (its shelf, in the store's order: A to Z)
	var nth := on.find(t) + 1
	var series: bool = t.get("kind", "movie") == "series"
	var eps: Array = t.get("e", [])
	_go({ "title": ("TITLE INQUIRY - %s" % t.t.to_upper()).left(COLS - 6), "prompt": "S TO SHOW ON THE SHELF, ESC",
		"bar": [["S", "SHOW ME", _show_me.bind(t)]], "acts": { 10: _show_me.bind(t) },
		"lines": func() -> Array:
			var st := _status(t)
			var out: Array = ["", (" TITLE....: %s" % t.t.to_upper()).left(COLS - 2), " SECTION..: %s" % t.c.to_upper(), " YEAR.....: %s" % _year(t),
				" KIND.....: %s" % ("TV SEASON" if series else "MOVIE")]
			if series:
				out.append(" EPISODES.: %d%s" % [eps.size(), "  (ABOUT %s EACH)" % _hm(eps[0][3]) if not eps.is_empty() and float(eps[0][3]) > 0.0 else ""])
			else:
				out.append(" RUNNING..: %s" % (_hm(eps[0][3]) if not eps.is_empty() and float(eps[0][3]) > 0.0 else "-"))
			out.append(" SHELF....: %s, %d OF %d ON IT, A TO Z" % [t.c.to_upper(), nth, on.size()])
			out.append(" STATUS...: %s" % st)
			while out.size() < 10:
				out.append("")
			if st == "ON SHELF":
				out.append_array(["  S  SHOW ME ON THE SHELF", "", " ITS SLOT LIGHTS UP AMBER TILL YOU TAKE IT DOWN."])
			elif st == "IN YOUR HANDS":
				out.append_array([" YOU'VE GOT IT: 1-9 PICKS WHICH OF YOUR TAPES IS IN HAND."])
			elif st == "IN THE VCR":
				out.append_array([" IT'S IN THE VCR, PLAYING. E ON THE SCREEN TAKES IT OUT."])
			else:
				out.append_array([" IT'S OFF THE SHELF."])
			return out,
		"submit": func(v: String) -> void:
			if v == "S":
				_show_me(t)
			else:
				_msg = "INVALID SELECTION." })


func _show_me(t: Dictionary) -> void:  # its slot lit, and off you go to it
	var st := _status(t)
	if st != "ON SHELF":
		_msg = "NOT ON THE SHELF: %s." % st
		return
	tapes.guide(t)
	$"../Ambience".beep(_at, 1320.0)
	$"../Ambience".beep(_at, 1760.0, 0.12)
	log_off()


func _vcr() -> Array:  # what's playing, and how far in
	var p = tapes.playing
	if p == null:
		return ["", " VCR......: EMPTY", "", " PUT A TAPE IN AT THE THEATER'S SCREEN OR THE LOUNGE TV (E)."]
	var t: Dictionary = p.tape
	var v: Node = $"../Video"
	var out: Array = ["", " VCR......: %s" % ("PAUSED" if v.paused else "PLAYING"), (" TAPE.....: %s" % t.t.to_upper()).left(COLS - 2), " SECTION..: %s" % t.c.to_upper()]
	if t.get("e", []).size() > 1:
		out.append(" EPISODE..: %d OF %d" % [int(p.idx) + 1, t.e.size()])
	out.append(" AT.......: %s%s" % [_clock(v.position), " OF %s" % _clock(v.duration) if v.duration > 0.0 else ""])
	return out


func _clock(secs: float) -> String:
	return "%d:%02d:%02d" % [int(secs) / 3600, int(secs) / 60 % 60, int(secs) % 60]


func _pick(key: String) -> bool:  # a menu selection. -> false if there's no such thing
	match key:
		"1": _go(_ask("INVENTORY - TITLE SEARCH", "TITLE (OR PART)", "ENTER ANY PART OF A TITLE.  EXAMPLE: ALIEN", func(q: String) -> void: _go(_titles("TITLE SEARCH: %s" % q, _find(q)))))
		"2":
			var names := _sections()
			_go(_list("SECTIONS", "      %s%s%s" % [L("SECTION", 36), L("KIND", 12), "TITLES  ON SHELF"], names,
				func(c: String, n: int) -> String:
					var on: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return t.c == c)
					var kinds := { "movie": 0, "series": 0 }
					for t: Dictionary in on:
						kinds[t.get("kind", "movie")] += 1
					var kind := "MOVIES" if kinds.series == 0 else "TV" if kinds.movie == 0 else "BOTH"
					return " %s  %s %s %s  %s" % [R(n, 3), L(c.to_upper(), 35), L(kind, 10), R(on.size(), 7), R(on.filter(func(t: Dictionary) -> bool: return not t.get("off", false)).size(), 8)],
				func(c: String) -> void: _go(_titles(c.to_upper(), tapes.tapes.filter(func(t: Dictionary) -> bool: return t.c == c)))))
		"3": _go(_info("WHAT'S IN THE VCR", _vcr))
		"4": _go(_titles("TAPES YOU'RE CARRYING", tapes.inv.duplicate(), "YOU'RE NOT CARRYING ANY."))
		"H": _go(_info("HELP", func() -> Array: return [" FROM THE MAIN MENU YOU CAN TYPE A NUMBER, OR A COMMAND:", "",
				"   FIND <TITLE>     TITLE SEARCH            VCR               WHAT'S IN IT",
				"   VER              VERSION                 LOGOFF / EXIT     END SESSION", "",
				" THE ARROWS AND ENTER, OR THE MOUSE: A CLICK PICKS, THE WHEEL TURNS PAGES.",
				" ESC OR A RIGHT-CLICK GOES BACK ONE SCREEN. F10 LOGS OFF FROM ANYWHERE.", "",
				" A TITLE'S SCREEN: S LIGHTS ITS SLOT ON THE SHELF, TILL YOU TAKE IT DOWN.", "",
				" SYSTEM PROBLEMS? CALL DENNIS (DISTRICT) - DO NOT REBOOT THE SERVER."]))
		"0": log_off()
		_: return false
	return true


func _main_menu() -> Dictionary:
	return { "title": "MAIN MENU", "prompt": "SELECTION OR COMMAND", "menu": true,
		"lines": func() -> Array:
			var left := [" INVENTORY", "  1  TITLE SEARCH", "  2  BROWSE BY SECTION", "  3  WHAT'S IN THE VCR", "  4  TAPES YOU'RE CARRYING"]
			var right := [" SYSTEM", "  H  HELP / COMMANDS", "  0  LOG OFF"]
			var out: Array = [""]
			for i in left.size():
				out.append(L(left[i], 40) + (right[i] if i < right.size() else ""))
			out.append_array(["", " %d TITLES · %d ON SHELF · %d SECTIONS · %s" % [tapes.tapes.size(), _on_shelf(), _sections().size(), _library()]])
			return out,
		"submit": func(v: String) -> void:
			var cmd := v.get_slice(" ", 0)
			var arg := v.substr(cmd.length()).strip_edges()
			if _pick(v):
				return
			if cmd in ["FIND", "INV"] and arg != "":
				_go(_titles("TITLE SEARCH: %s" % arg, _find(arg)))
			elif cmd == "VER":
				_msg = "POS/NET 2.3 (C) 1993 VIDEOTRAK SYSTEMS INC.  LICENSED TO VAULTBUSTER VIDEO #0417"
			else:
				var alias: String = { "VCR": "3", "PLAYING": "3", "MINE": "4", "HELP": "H", "?": "H", "LOGOFF": "0", "EXIT": "0", "LOGOUT": "0" }.get(cmd, "")
				if alias == "" or not _pick(alias):
					_msg = "UNKNOWN COMMAND: %s.  TYPE H FOR HELP." % v }


# ---- on and off, the keyboard and the mouse, the screen

func log_in() -> void:
	open = true
	visible = true
	_stack.clear()
	_screen = _main_menu()
	_input = ""
	_msg = ""
	_login = 0.0
	_menu_cur = 0
	if not "--shot" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # the screen takes clicks
	player.set_physics_process(false)


func log_off() -> void:
	open = false
	visible = false
	_screen = {}
	_stack.clear()
	if not "--shot" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_physics_process(true)


func type(v: String) -> void:  # a line typed and ENTER
	_msg = ""
	_input = ""
	_screen.submit.call(v.to_upper().strip_edges())


func _unhandled_input(e: InputEvent) -> void:
	if not open:
		return
	get_viewport().set_input_as_handled()  # (the terminal has the keyboard, and the mouse)
	if e is InputEventMouse:  # the mouse: what it's over is highlighted, a click's as good as typing it, the wheel turns a list's pages, a right-click goes back
		_over = Vector2i(((e.position - _view.position) / _cell).floor())
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_back()
			return
		if _login >= 0.0:
			return
		var over: Array = _hits.filter(func(h: Dictionary) -> bool: return h.r == _over.y and _over.x >= h.c0 and _over.x <= h.c1)
		if e is InputEventMouseMotion and not over.is_empty() and over[0].has("pick"):
			if _screen.get("menu", false):
				_menu_cur = over[0].pick
			else:
				_screen.pick.cur = over[0].pick
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not over.is_empty():
			over[0].act.call()
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP] and _screen.get("pager", false):
			type("N" if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else "P")
		return
	if not (e is InputEventKey and e.pressed) or (_login >= 0.0 and e.keycode != KEY_F10):
		return
	match e.keycode:
		KEY_F10: log_off()
		KEY_ESCAPE: _back()
		KEY_ENTER, KEY_KP_ENTER: _enter()
		KEY_BACKSPACE: _input = _input.left(-1)
		KEY_UP, KEY_DOWN: _arrow(1 if e.keycode == KEY_DOWN else -1, 0)
		KEY_PAGEDOWN, KEY_RIGHT:
			if _screen.get("pager", false):
				type("N")
			else:
				_arrow(0, 1)
		KEY_PAGEUP, KEY_LEFT:
			if _screen.get("pager", false):
				type("P")
			else:
				_arrow(0, -1)
		_:
			var hot: Array = _screen.get("bar", []).filter(func(k: Array) -> bool: return e.unicode > 0 and k[0] == char(e.unicode).to_upper())
			if _input == "" and not hot.is_empty():  # (a screen's own key on the bar, a title's S: pressed, no ENTER wanted)
				hot[0][2].call()
			elif e.unicode >= 32 and e.unicode < 127 and _input.length() < 40:
				_input += char(e.unicode).to_upper()


func _enter() -> void:  # ENTER: what's typed; or, with nothing typed, whatever's highlighted
	if _input == "" and _screen.get("menu", false) and _menu_cur < _menu_items.size():
		type(_menu_items[_menu_cur].key)
	elif _input == "" and _screen.get("pick", {}).get("n", 0) > 0:
		type(str(_screen.pick.cur + 1))
	else:
		type(_input)


func _arrow(down: int, across: int) -> void:  # the arrows: up and down the records or the menu, across to the menu's other column (about level)
	if _screen.get("menu", false) and not _menu_items.is_empty():
		var here: Dictionary = _menu_items[mini(_menu_cur, _menu_items.size() - 1)]
		if down != 0:
			_menu_cur = posmod(_menu_cur + down, _menu_items.size())
		elif (across > 0) != (here.side == 1):
			var best := _menu_cur
			for i in _menu_items.size():
				if _menu_items[i].side != here.side and (best == _menu_cur or absi(_menu_items[i].r - here.r) < absi(_menu_items[best].r - here.r)):
					best = i
			_menu_cur = best
	elif down != 0 and _screen.get("pick", {}).get("n", 0) > 0:
		var pk: Dictionary = _screen.pick
		pk.cur = clampi(pk.cur + down, 0, pk.n - 1)
		pk.page[0] = pk.cur / pk.per


func _process(dt: float) -> void:
	_mon_tick(dt)
	if not open or _screen.is_empty():
		return
	_blink += dt
	if _login >= 0.0:  # the badge, the password, a beat to verify, and in
		_login += dt
		if _login >= 1.25:
			_login = -1.0
			_msg = "BADGE ACCEPTED. WELCOME BACK. %d TITLES ON FILE." % tapes.tapes.size()
	var vp := get_viewport().get_visible_rect().size  # 80 x 30 cells, twice as tall as wide: the monitor's 4:3, as big as the window has room for
	var h := maxi(12, int(minf(vp.y * 0.92 / ROWS, vp.x * 0.92 / COLS * 2.0)) / 2 * 2)
	_cell = Vector2(h / 2.0, h)
	_dim.size = vp  # (anchors don't take under a CanvasLayer that's hidden when it's made: sized here, with the window)
	_view.position = ((vp - Vector2(COLS, ROWS) * _cell) / 2.0).floor()
	_frame()
	_view.queue_redraw()


# ---- the screen itself, as VaultBuster's pos.gd draws it: a grid of cells, each a character with its own colours,
# painted with the frame's lines as strokes, scanlines and the tube's dark corners

const ROWS := 30
const FONT := "res://fonts/VT323-Regular.ttf"
const P := {  # the DOS-app palette: blue screen, light grey text, bright white values, cyan labels and frames, yellow headings, green good news, red warnings
	"bg": Color("#0000aa"), "fg": Color("#c8c8d8"), "hi": Color("#ffffff"), "yel": Color("#ffff55"), "cyan": Color("#55ffff"), "dcyan": Color("#00aaaa"), "grn": Color("#55ff55"),
	"red": Color("#ff5555"), "gray": Color("#8a8ad0"), "blk": Color("#000000"), "deep": Color("#000077"), "shadow": Color("#000044") }
const FONT5 := {  # the logo's 5x7 letters
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"], "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"] }
const LOGO := "VAULTBUSTER"
const RAMP := ["#ffff88", "#ffff55", "#ffee33", "#ffcc22", "#ffaa11", "#ff8800", "#ff6600"]  # yellow running to orange
const TAG := "·  V I D E O   ·   P O S / N E T   2 . 3  ·"
const HEAD := "\a"  # (in front of a body line: it's a column heading)
const MARKS := {  # what a body line's coloured by
	"label": "^(\\s*[A-Z#][A-Z #/.'-]*?\\.{2,}:)", "page": "PAGE \\d+ OF \\d+", "good": "\\bON SHELF\\b|\\bPLAYING\\b", "where": "IN YOUR HANDS|IN THE VCR|\\bPAUSED\\b",
	"bad": "OFF THE SHELF|\\bEMPTY\\b|\\*\\*\\*[^*]*\\*\\*\\*", "num": "\\d+",
	"msg_bad": "INVALID|UNKNOWN|REQUIRED|NOT |NO SUCH|FIRST|LAST PAGE|CAN'T", "msg_good": "ACCEPTED|WELCOME|LIT" }

var _view := Control.new()
var _font: Font
var _vignette := GradientTexture2D.new()
var _re := {}
var _cell := Vector2(10, 20)
var _login := -1.0  # seconds into the login's show (-1: logged in)
var _ch := PackedStringArray()  # the grid, row by row
var _fg := PackedColorArray()
var _bg := PackedColorArray()
var _px := {}  # cell -> [top half, bottom half]: the logo's pixels
var _hits: Array = []  # what a click lands on: { r, c0, c1, act, pick (which record or menu line it is) }
var _menu_items: Array = []  # the main menu's lines, in order: { key, r, c0, c1, side }
var _menu_cur := 0  # ...and the one that's highlighted


func _put(r: int, c: int, text: String, fg = null, bg = null) -> void:
	for i in text.length():
		if r < 0 or r >= ROWS or c + i < 0 or c + i >= COLS:
			continue
		var k := r * COLS + c + i
		_ch[k] = text[i]
		_px.erase(k)
		if fg != null:
			_fg[k] = fg
		if bg != null:
			_bg[k] = bg


func _tint(r: int, c0: int, c1: int, fg = null, bg = null) -> void:
	for c in range(maxi(0, c0), mini(COLS - 1, c1) + 1):
		if fg != null:
			_fg[r * COLS + c] = fg
		if bg != null:
			_bg[r * COLS + c] = bg


func _center(r: int, text: String, fg = null, bg = null, c0 := 0, c1 := COLS - 1) -> void:
	_put(r, c0 + (c1 - c0 + 1 - text.length()) / 2, text, fg, bg)


func _box(r0: int, c0: int, r1: int, c1: int, dbl: bool, fg: Color) -> void:  # an outline
	var b := "═║╔╗╚╝" if dbl else "─│┌┐└┘"
	_put(r0, c0, b[2] + b[0].repeat(c1 - c0 - 1) + b[3], fg)
	_put(r1, c0, b[4] + b[0].repeat(c1 - c0 - 1) + b[5], fg)
	for r in range(r0 + 1, r1):
		_put(r, c0, b[1], fg)
		_put(r, c1, b[1], fg)


func _rule(r: int, c0: int, c1: int, kind: String, fg: Color) -> void:  # a divider across a box: "dbl" ╠═╣ · "mid" ╟─╢ · "single" ├─┤
	var b := "╠═╣" if kind == "dbl" else "╟─╢" if kind == "mid" else "├─┤"
	_put(r, c0, b[0] + b[1].repeat(c1 - c0 - 1) + b[2], fg)


func _logo(r0: int, c0: int) -> void:  # VAULTBUSTER in 5x7 pixel letters with a drop shadow: 8 pixel rows = 4 rows of half-block cells
	var on := func(x: int, y: int) -> bool: return y >= 0 and y < 7 and x >= 0 and x / 6 < LOGO.length() and x % 6 < 5 and FONT5[LOGO[x / 6]][y][x % 6] == "1"
	for row in 4:
		for x in LOGO.length() * 6:
			var px: Array = [P.bg, P.bg]
			for half in 2:
				var y := row * 2 + half
				px[half] = Color(RAMP[y]) if on.call(x, y) else P.shadow if on.call(x - 1, y - 1) else P.bg
			if px[0] != P.bg or px[1] != P.bg:
				_px[(r0 + row) * COLS + c0 + x] = px


func _status_bar(r: int) -> void:  # where, when, what's on file: split by bars
	var c := 2
	for part: Array in [["TERM 01", P.hi], ["%s %s" % [Clock.weekday(), _date()], P.yel], [Clock.fmt_clock(Clock.h), P.yel],
			["%d TITLES" % tapes.tapes.size(), P.hi], ["%d ON SHELF" % _on_shelf(), P.grn], [_library(), P.gray if Library.demo else P.cyan]]:
		if c > 2:
			_put(r, c, "│", P.dcyan)
			c += 2
		_put(r, c, part[0], part[1])
		c += part[0].length() + 1


func _hovered(h: Dictionary) -> bool:
	return h.r == _over.y and _over.x >= h.c0 and _over.x <= h.c1


func _key_bar(r: int, keys: Array) -> void:  # [cap, label, what a click on it does]: a black strip under the frame, cyan key caps (yellow under the mouse)
	_tint(r, 0, COLS - 1, P.fg, P.blk)
	var c := 1
	for k: Array in keys:
		var hit := { "r": r, "c0": c, "c1": c + k[0].length() + k[1].length() + 2, "act": k[2] }
		var lit := open and _hovered(hit)
		_put(r, c, " %s " % k[0], P.blk, P.yel if lit else P.dcyan)
		_put(r, c + k[0].length() + 2, " " + k[1], P.yel if lit else P.hi, P.blk)
		_hits.append(hit)
		c += k[0].length() + k[1].length() + 5


func _color_line(r: int, l: String) -> void:  # a body line: plain text, coloured by what it looks like
	if l.begins_with(HEAD):  # a column heading
		_tint(r, 1, COLS - 2, P.yel, P.deep)
		_put(r, 1, l.substr(1).left(COLS - 2), P.yel)
		return
	var t := l.left(COLS - 2)
	_put(r, 1, t, P.fg)
	var lab: RegExMatch = _re.label.search(t)  # " TITLE....: value"
	if lab != null:
		_tint(r, 1, lab.get_end(), P.cyan)
		_tint(r, 1 + lab.get_end(), COLS - 2, P.hi)
	for mark: Array in [["page", P.gray], ["good", P.grn], ["where", P.yel], ["bad", P.red]]:
		for m: RegExMatch in _re[mark[0]].search_all(t):
			_tint(r, 1 + m.get_start(), m.get_end(), mark[1])


func _menu(top: int, lines: Array) -> void:  # the main menu: two boxed columns of what there is, the store's numbers under them
	_menu_items.clear()
	var bottom := top
	for side in 2:
		var c0 := 41 if side == 1 else 2
		var c1 := 77 if side == 1 else 38
		var r := top
		for l: String in lines.slice(1, lines.size() - 2):
			var t := (l.substr(40) if side == 1 else l.left(40)).strip_edges(false, true)
			if t == "":
				continue
			if not t.begins_with("  "):  # a group's name, on the box's own line
				_put(r, c0, ("┌" if r == top else "├") + "─".repeat(c1 - c0 - 1) + ("┐" if r == top else "┤"), P.dcyan)
				_put(r, c0 + 2, " %s " % t.strip_edges(), P.yel)
			else:
				_put(r, c0, "│", P.dcyan)
				_put(r, c1, "│", P.dcyan)
				_put(r, c0 + 2, t.substr(2, 1), P.yel)
				_put(r, c0 + 5, t.substr(5).strip_edges(), P.hi)
				_menu_items.append({ "key": t.substr(2, 1), "r": r, "c0": c0 + 1, "c1": c1 - 1, "side": side })
			r += 1
		_put(r, c0, "└" + "─".repeat(c1 - c0 - 1) + "┘", P.dcyan)
		bottom = maxi(bottom, r)
	_menu_cur = mini(_menu_cur, _menu_items.size() - 1)
	for i in _menu_items.size():  # the highlighted one on a grey bar; any of them takes a click
		var it: Dictionary = _menu_items[i]
		if i == _menu_cur:
			_tint(it.r, it.c0, it.c1, P.bg, P.fg)
		_hits.append({ "r": it.r, "c0": it.c0, "c1": it.c1, "act": type.bind(it.key), "pick": i })
	var facts: String = lines[-1].strip_edges()
	_put(bottom + 2, 2, facts, P.cyan)
	for m: RegExMatch in _re.num.search_all(facts):
		_tint(bottom + 2, 2 + m.get_start(), 1 + m.get_end(), P.hi)


func _login_screen() -> void:  # what the monitor shows till you're in
	var step := 0
	for at: float in [0.0, 0.16, 0.23, 0.3, 0.37, 0.44, 0.51, 0.58, 0.95]:
		step += int(_login >= at)
	_logo(2, (COLS - LOGO.length() * 6) / 2)
	_center(6, TAG, P.cyan)
	var x0 := 19
	var x1 := 60
	_box(8, x0, 14, x1, false, P.dcyan)
	_center(8, " SECURE LOGIN ", P.yel, null, x0, x1)
	var fields := [["STORE.....:", "#0417  ELM ST PLAZA", P.hi], ["TERMINAL..:", "REGISTER 01", P.hi], ["EMPLOYEE..:", "0042  (BADGE)" if step >= 1 else "____", P.hi if step >= 1 else P.gray],
		["PASSWORD..:", "*".repeat(mini(6, step - 1)).rpad(6, "_") if step >= 2 else "______", P.hi if step >= 2 else P.gray],
		["STATUS....:", "ACCESS GRANTED" if step >= 9 else "VERIFYING..." if step >= 8 else "READY", P.grn if step >= 9 else P.yel if step >= 8 else P.fg]]
	for i in fields.size():
		_put(9 + i, x0 + 3, fields[i][0], P.cyan)
		_put(9 + i, x0 + 4 + fields[i][0].length(), fields[i][1], fields[i][2])
	_rule(20, 0, COLS - 1, "mid", P.dcyan)
	var on := _on_shelf()
	var p = tapes.playing
	var rows := [[21, 2, "TITLES.....", R(tapes.tapes.size(), 5), P.hi], [22, 2, "ON SHELF...", R(on, 5), P.grn], [23, 2, "OFF SHELF..", R(tapes.tapes.size() - on, 5), P.red if tapes.tapes.size() > on else P.hi],
		[24, 2, "CARRYING...", R(tapes.inv.size(), 5), P.hi], [21, 24, "VCR.......", p.tape.t.to_upper().left(30) if p != null else "EMPTY", P.hi if p != null else P.gray],
		[22, 24, "LIBRARY...", _library(), P.gray if Library.demo else P.cyan]]
	for f: Array in rows:
		_put(f[0], f[1], f[2], P.cyan)
		_put(f[0], f[1] + f[2].length() + 1, f[3], f[4])
	var when := "%s %s" % [Clock.weekday(), _date()]
	_put(21, COLS - 3 - when.length(), when, P.yel)
	_put(22, COLS - 3 - Clock.fmt_clock(Clock.h).length(), Clock.fmt_clock(Clock.h), P.yel)
	_put(23, COLS - 21, "SCO UNIX 3.2 · TTY01", P.gray)
	_put(ROWS - 3, 2, "PRESS E AT THE REGISTER TO LOG IN" if not open else "LOGGING IN...", P.gray)
	_key_bar(ROWS - 1, [])


# ---- the register's own monitor, on the counter: whatever the terminal's showing, or (nobody at it) the login
# screen. Painted into a picture of its own, a few times a second

const MON_CELL := Vector2(10, 20)

var _mon := SubViewport.new()
var _mon_view := Control.new()
var _mon_t := 0.0
var _mon_glass: MeshInstance3D


func _mon_build() -> void:
	_mon.size = Vector2i(COLS * 10, ROWS * 20)
	_mon.disable_3d = true
	_mon.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_mon)
	_mon.add_child(_mon_view)
	_mon_view.draw.connect(_paint.bind(_mon_view, MON_CELL))
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):  # the level's: the monitor's glass
		var size := mi.get_aabb().size
		if absf(size.x - 0.3) < 0.01 and absf(size.y - 0.235) < 0.01 and size.z < 0.005 and mi.global_position.distance_to(_at) < 0.8:
			_mon_glass = mi
	if _mon_glass == null:
		push_warning("the register's monitor isn't where VaultBuster has it: its screen stays as the level has it")
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mon.get_texture()
	m.uv1_scale = Vector3(1, -1, 1)  # (the level's pictures are the other way up)
	m.uv1_offset = Vector3(0, 1, 0)
	_mon_glass.material_override = m


func _mon_tick(dt: float) -> void:
	_mon_t -= dt
	if _mon_t > 0.0 or _mon_glass == null:
		return
	_mon_t = 0.1 if open else 0.3
	if not open:  # (at the keyboard the grid's this frame's already)
		_frame()
	_mon_view.queue_redraw()
	_mon.render_target_update_mode = SubViewport.UPDATE_ONCE


func _frame() -> void:  # the grid for this moment
	_ch.resize(COLS * ROWS)
	_fg.resize(COLS * ROWS)
	_bg.resize(COLS * ROWS)
	_ch.fill(" ")
	_fg.fill(P.fg)
	_bg.fill(P.bg)
	_px.clear()
	_hits.clear()
	_box(0, 0, ROWS - 2, COLS - 1, true, P.dcyan)
	if _login >= 0.0 or not open:
		_login_screen()
		return
	var lines: Array = _screen.lines.call()
	var big: bool = _screen.get("menu", false)
	var top := 9 if big else 3
	if big:  # the main menu: the logo up top
		_logo(1, (COLS - LOGO.length() * 6) / 2)
		_center(5, TAG, P.cyan)
		_rule(6, 0, COLS - 1, "dbl", P.dcyan)
		_status_bar(7)
		_rule(8, 0, COLS - 1, "mid", P.dcyan)
		_menu(top, lines)
	else:  # everywhere else: the name in the top border, the screen's title on a bar
		_put(0, 2, " VAULTBUSTER ", P.yel)
		_put(0, 15, " POS/NET 2.3 ", P.cyan)
		var right := " TERM 01 │ %s %s │ %s " % [_date(), Clock.fmt_clock(Clock.h), _library()]
		_put(0, COLS - 2 - right.length(), right, P.fg)
		_tint(1, 1, COLS - 2, P.blk, P.dcyan)
		_put(1, 2, "► " + str(_screen.title).left(COLS - 6), P.blk, P.dcyan)
		_rule(2, 0, COLS - 1, "mid", P.dcyan)
		for i in mini(lines.size(), ROWS - 5 - top):  # the body runs down to the footer's divider
			_color_line(top + i, str(lines[i]))
		var pk: Dictionary = _screen.get("pick", {})
		for i in range(pk.page[0] * pk.per, mini(pk.n, (pk.page[0] + 1) * pk.per)) if pk.get("n", 0) > 0 else []:  # a list's records: the highlighted one on a grey bar; any of them takes a click
			var r: int = top + 1 + i - pk.page[0] * pk.per
			if i == pk.cur:
				_tint(r, 1, COLS - 2, P.bg, P.fg)
			_hits.append({ "r": r, "c0": 1, "c1": COLS - 2, "act": type.bind(str(i + 1)), "pick": i })
		var acts: Dictionary = _screen.get("acts", {})
		for i: int in acts:  # a line that does something (a title's S): its key in yellow, a grey bar under the mouse
			if i < lines.size() and str(lines[i]).begins_with("  ") and str(lines[i]).strip_edges() != "":
				var hit := { "r": top + i, "c0": 1, "c1": COLS - 2, "act": acts[i] }
				_tint(top + i, 3, 3, P.yel)
				if _hovered(hit):
					_tint(top + i, 1, COLS - 2, P.bg, P.fg)
				_hits.append(hit)
	_rule(ROWS - 5, 0, COLS - 1, "mid", P.dcyan)
	if _msg != "":
		_put(ROWS - 4, 2, _msg.left(COLS - 4), P.red if _re.msg_bad.search(_msg) != null else P.grn if _re.msg_good.search(_msg) != null else P.yel)
	var label := "%s: " % _screen.get("prompt", "SELECTION")
	_put(ROWS - 3, 2, label, P.cyan)
	_put(ROWS - 3, 2 + label.length(), _input + ("█" if fmod(_blink, 1.06) < 0.53 else " "), P.hi)
	var bar: Array = ([["N", "NEXT", type.bind("N")], ["P", "PREV", type.bind("P")]] if _screen.get("pager", false) else []) + _screen.get("bar", [])
	_key_bar(ROWS - 1, bar + [["ENTER", "OK", _enter], ["ESC", "BACK", _back], ["F10", "LOG OFF", log_off]])
	_put(ROWS - 1, COLS - 17, "RIGHT-CLICK BACK", P.gray, P.blk)


func _strokes(ch: String, l: float, t: float, w: float, h: float, d: float) -> Array:  # a box-drawing character as lines: [x0, y0, x1, y1]... ([] if it isn't one)
	var r := l + w
	var b := t + h
	var cx := roundf(l + w / 2.0)
	var cy := roundf(t + h / 2.0)
	match ch:
		"─": return [[l, cy, r, cy]]
		"│": return [[cx, t, cx, b]]
		"┌": return [[cx, cy, r, cy], [cx, cy, cx, b]]
		"┐": return [[l, cy, cx, cy], [cx, cy, cx, b]]
		"└": return [[cx, t, cx, cy], [cx, cy, r, cy]]
		"┘": return [[cx, t, cx, cy], [l, cy, cx, cy]]
		"├": return [[cx, t, cx, b], [cx, cy, r, cy]]
		"┤": return [[cx, t, cx, b], [l, cy, cx, cy]]
		"═": return [[l, cy - d, r, cy - d], [l, cy + d, r, cy + d]]
		"║": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b]]
		"╔": return [[cx - d, cy - d, r, cy - d], [cx - d, cy - d, cx - d, b], [cx + d, cy + d, r, cy + d], [cx + d, cy + d, cx + d, b]]
		"╗": return [[l, cy - d, cx + d, cy - d], [cx + d, cy - d, cx + d, b], [l, cy + d, cx - d, cy + d], [cx - d, cy + d, cx - d, b]]
		"╚": return [[cx - d, t, cx - d, cy + d], [cx - d, cy + d, r, cy + d], [cx + d, t, cx + d, cy - d], [cx + d, cy - d, r, cy - d]]
		"╝": return [[cx + d, t, cx + d, cy + d], [l, cy + d, cx + d, cy + d], [cx - d, t, cx - d, cy - d], [l, cy - d, cx - d, cy - d]]
		"╠": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, cy - d], [cx + d, cy - d, r, cy - d], [cx + d, b, cx + d, cy + d], [cx + d, cy + d, r, cy + d]]
		"╣": return [[cx + d, t, cx + d, b], [cx - d, t, cx - d, cy - d], [l, cy - d, cx - d, cy - d], [cx - d, b, cx - d, cy + d], [l, cy + d, cx - d, cy + d]]
		"╟": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b], [cx + d, cy, r, cy]]
		"╢": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b], [l, cy, cx - d, cy]]
	return []


func _paint(view: Control, cell: Vector2) -> void:  # onto the screen over the game, or the monitor's own picture
	if _ch.size() != COLS * ROWS:
		return  # (shown before its first frame's been laid out)
	var w := cell.x
	var h := cell.y
	var size := Vector2(COLS * w, ROWS * h)
	var lw := maxf(1.0, roundf(h / 13.0))
	var d := maxf(2.0, roundf(w * 0.2))
	var px := int(h)
	var base := (h - _font.get_height(px)) / 2.0 + _font.get_ascent(px)
	view.draw_rect(Rect2(Vector2(-14, -14), size + Vector2(28, 28)), Color("#111114"))  # the monitor's bezel
	view.draw_rect(Rect2(Vector2.ZERO, size), P.bg)
	for r in ROWS:
		for c in COLS:
			var k := r * COLS + c
			var at := Vector2(c * w, r * h)
			if _px.has(k):
				view.draw_rect(Rect2(at, Vector2(w, h / 2.0)), _px[k][0])
				view.draw_rect(Rect2(at + Vector2(0, h / 2.0), Vector2(w, h / 2.0)), _px[k][1])
				continue
			if _bg[k] != P.bg:
				view.draw_rect(Rect2(at, cell), _bg[k])
			var ch := _ch[k]
			if ch == " ":
				continue
			if ch == "█":
				view.draw_rect(Rect2(at, cell), _fg[k])
				continue
			var segs := _strokes(ch, at.x, at.y, w, h, d)
			for s: Array in segs:  # (square ends, so corners meet)
				var horiz: bool = s[1] == s[3]
				view.draw_rect(Rect2(minf(s[0], s[2]) - (0.0 if horiz else lw / 2.0), minf(s[1], s[3]) - (lw / 2.0 if horiz else 0.0), absf(s[2] - s[0]) + (0.0 if horiz else lw), absf(s[3] - s[1]) + (lw if horiz else 0.0)), _fg[k])
			if segs.is_empty():
				view.draw_char(_font, at + Vector2((w - _font.get_char_size(ch.unicode_at(0), px).x) / 2.0, base), ch, px, _fg[k])
	for y in range(2, int(size.y), 3):  # scanlines
		view.draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.13))
	view.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false)
