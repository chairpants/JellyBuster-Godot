extends CanvasLayer
## The TV's picture menu (the web game's SETTINGS, on the TV): brightness, contrast, colour, tint, sharpen, volume, and
## B&W, scanlines, pixelated. P (or right-click, sat down or with a tape playing) opens it, the mouse free; P, right-click, Esc or a click off
## it closes it. The same settings on every screen, the theater's and full screen too; kept in user://picture.cfg.

const ROWS := [  # [key, label, min, max, step] (no min: a toggle)
	["brightness", "BRIGHTNESS", 50, 150, 5], ["contrast", "CONTRAST", 50, 150, 5], ["saturate", "COLOR", 0, 200, 5],
	["hue", "TINT", 0, 360, 10], ["sharpen", "SHARPEN", 0, 100, 5], ["volume", "VOLUME", 0, 200, 5],
	["bw", "B&W"], ["scanlines", "SCANLINES"], ["pixelated", "PIXELATED"],
]
const DEFAULTS := { "brightness": 100, "contrast": 100, "saturate": 100, "hue": 0, "sharpen": 0, "volume": 100, "bw": false, "scanlines": false, "pixelated": false }
const FILE := "user://picture.cfg"
const PIC := """
uniform float uFx = 1.0; uniform float uK = 1.0;
uniform float uBright = 1.0; uniform float uContrast = 1.0; uniform float uSat = 1.0; uniform float uHue = 0.0;
uniform float uSharp = 0.0; uniform float uScan = 0.0; uniform float uPix = 0.0;

vec3 cubic(sampler2D t, vec2 uv, vec2 sz) {   // Catmull-Rom, in nine bilinear taps: crisper than bilinear where the picture's blown up (close, zoomed, full screen)
	vec2 tc = floor(uv * sz - 0.5) + 0.5;
	vec2 f = uv * sz - tc;
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 a = (tc - 1.0) / sz, b = (tc + w2 / w12) / sz, d = (tc + 2.0) / sz;
	vec3 c = (texture(t, vec2(a.x, a.y)).rgb * w0.x + texture(t, vec2(b.x, a.y)).rgb * w12.x + texture(t, vec2(d.x, a.y)).rgb * w3.x) * w0.y
		+ (texture(t, vec2(a.x, b.y)).rgb * w0.x + texture(t, vec2(b.x, b.y)).rgb * w12.x + texture(t, vec2(d.x, b.y)).rgb * w3.x) * w12.y
		+ (texture(t, vec2(a.x, d.y)).rgb * w0.x + texture(t, vec2(b.x, d.y)).rgb * w12.x + texture(t, vec2(d.x, d.y)).rgb * w3.x) * w3.y;
	return max(c, 0.0);
}

vec3 look(sampler2D t, vec2 uv, vec2 sz) {   // the picture at uv: blown up, cubic; seen from further back (more texels than pixels: no mipmaps to fall back on), four taps across the pixel, else it shimmers
	vec2 dx = dFdx(uv), dy = dFdy(uv);
	float texels = max(length(dx * sz), length(dy * sz));
	vec3 far = (texture(t, uv + 0.125 * dx + 0.375 * dy).rgb + texture(t, uv - 0.125 * dx - 0.375 * dy).rgb
		+ texture(t, uv + 0.375 * dx - 0.125 * dy).rgb + texture(t, uv - 0.375 * dx + 0.125 * dy).rgb) * 0.25;
	return mix(cubic(t, uv, sz), far, smoothstep(0.8, 1.3, texels));
}

vec3 pic(sampler2D t, vec2 uv) {   // as the web game's CSS filters: in sRGB, brightness, contrast, saturate, hue-rotate, then an unsharp mask
	vec2 sz = vec2(textureSize(t, 0));
	if (uFx < 0.5) return texture(t, uv).rgb * uK;
	if (uPix > 0.5) uv = (floor(uv * sz) + 0.5) / sz;
	vec3 c = uPix > 0.5 ? texture(t, uv).rgb : look(t, uv, sz);
	if (uSharp > 0.0) {
		vec2 px = 1.0 / sz;
		vec3 n = texture(t, uv + vec2(px.x, 0)).rgb + texture(t, uv - vec2(px.x, 0)).rgb + texture(t, uv + vec2(0, px.y)).rgb + texture(t, uv - vec2(0, px.y)).rgb;
		c = c * (1.0 + 4.0 * uSharp) - uSharp * n;
	}
	c = (c * uBright - 0.5) * uContrast + 0.5;
	c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, uSat);
	vec3 k = vec3(0.57735);   // the hue, turned round grey
	c = c * cos(uHue) + cross(k, c) * sin(uHue) + k * dot(k, c) * (1.0 - cos(uHue));
	if (uScan > 0.5) c *= mod(floor(uv.y * 240.0), 2.0) < 1.0 ? vec3(1.035) : vec3(0.66, 0.67, 0.7);
	return clamp(c, 0.0, 1.0) * uK;
}
"""
const SPATIAL := "shader_type spatial;\nrender_mode unshaded;\nuniform sampler2D uTex : filter_linear;\n" + PIC + """
void fragment() { vec3 c = pic(uTex, UV); ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045))); }
"""
const CANVAS := "shader_type canvas_item;\n" + PIC + "void fragment() { COLOR.rgb = pic(TEXTURE, UV); }\n"

var tv := DEFAULTS.duplicate()
var _mats: Array[ShaderMaterial] = []
var _panel := PanelContainer.new()
var _rows := {}  # key -> its slider or toggle


func _ready() -> void:
	layer = 6
	var cf := ConfigFile.new()
	if cf.load(FILE) == OK:
		for k in DEFAULTS:
			tv[k] = cf.get_value("tv", k, DEFAULTS[k])
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # (out from the right edge, and both ways from the middle, as big as it needs)
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_right = -24
	_panel.custom_minimum_size.x = 380
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0.03, 0.12, 0.78)
	style.border_color = Color("#7dff9a")
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for r: Array in ROWS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := Label.new()
		l.text = r[1]
		l.custom_minimum_size.x = 120
		row.add_child(l)
		if r.size() == 2:
			var cb := CheckBox.new()
			cb.toggled.connect(func(on: bool) -> void: _put(r[0], on))
			row.add_child(cb)
			_rows[r[0]] = cb
			continue
		var s := HSlider.new()
		s.min_value = r[2]
		s.max_value = r[3]
		s.step = r[4]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := Label.new()
		v.custom_minimum_size.x = 40
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.value_changed.connect(func(x: float) -> void:
			v.text = str(int(x))
			_put(r[0], int(x)))
		row.add_child(s)
		row.add_child(v)
		_rows[r[0]] = s
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	for b: Array in [["RESET", func() -> void: _show(DEFAULTS)], ["CLOSE", close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size.x = 110
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	_show(tv)


func material(spatial: bool) -> ShaderMaterial:  # one for each screen (and the full-screen picture): kept in step with the settings
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SPATIAL if spatial else CANVAS
	_mats.append(m)
	_apply()
	return m


func _show(s: Dictionary) -> void:  # the controls to these (each one's signal sets it)
	for k in s:
		if _rows[k] is CheckBox:
			_rows[k].set_pressed_no_signal(s[k])
		else:
			_rows[k].set_value_no_signal(s[k])
		_rows[k].emit_signal("toggled" if _rows[k] is CheckBox else "value_changed", s[k] if _rows[k] is CheckBox else _rows[k].value)  # (the slider's: a saved one past its range comes back in it)


func _put(k: String, v: Variant) -> void:
	tv[k] = v
	_apply()
	var cf := ConfigFile.new()
	for key in tv:
		cf.set_value("tv", key, tv[key])
	cf.save(FILE)


func _apply() -> void:
	for m in _mats:
		m.set_shader_parameter("uBright", tv.brightness / 100.0)
		m.set_shader_parameter("uContrast", tv.contrast / 100.0)
		m.set_shader_parameter("uSat", 0.0 if tv.bw else tv.saturate / 100.0)
		m.set_shader_parameter("uHue", deg_to_rad(tv.hue))
		m.set_shader_parameter("uSharp", tv.sharpen / 100.0 * 1.5)
		m.set_shader_parameter("uScan", 1.0 if tv.scanlines else 0.0)
		m.set_shader_parameter("uPix", 1.0 if tv.pixelated else 0.0)
	# the Film bus's fader, not the player's volume (the player's is capped by its max_db, so up close 200 did nothing)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Film"), 10.0 * log(maxf(tv.volume, 1.0) / 100.0) / log(2.0))  # (as loud as it sounds: twice as loud, +10 dB, at 200; half, -10, at 50)


func open() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:  # (the panel's own clicks never get here: its controls take them)
	var p_key: bool = e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_P
	var right: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT
	var tapes: Node = $"../Tapes"
	var putting_back: bool = tapes.held != null and tapes.held == tapes.peek  # (right-click's that, then: tapes.gd)
	if _panel.visible:
		if p_key or right or e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE or e is InputEventMouseButton and e.pressed:
			close()
			get_viewport().set_input_as_handled()
	elif p_key or right and ($"../Player".seat != null or tapes.playing != null and not putting_back) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		open()
		get_viewport().set_input_as_handled()
