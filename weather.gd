extends Node3D
## The weather. Each day has its own, worked out from the date (sky.gd's wx_plan): mostly clear, sometimes a spell of
## rain, snow in the winter months, fog some mornings. Rain streaks down outside and the lot goes dark and wet, drying
## slowly after; snow drifts down and settles on the lot and the grass; the wind slants it all and gusts.
## From the web game: exterior/sky.js (weatherTick; wxFall, the rain and snow falling in their shaders; WX_GROUND).
## And rain on the storefront glass, and snow drifting against the kerbs (both at the bottom). What it does to people
## is people.gd's (env, pace) and person.gd's.

const FALL := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;
// A box of particles that wraps round on itself, held in the world: one fixed over the lot and the road, one carried
// round with you. UV.x: which end of a streak (0 head, 1 tail); UV.y: this one's own number. Nothing falls indoors.
uniform float uT; uniform float uK; uniform float uNight; uniform float uH; uniform float uY0; uniform float uFollow;
uniform vec2 uC; uniform vec2 uS; uniform vec2 uWind; uniform vec2 uDrift;
varying float vE;

vec3 place(vec3 q, float fall, vec2 drift, vec3 cam) {
	vec2 c0 = mix(uC, cam.xz, uFollow) - uS * 0.5;
	float y0 = mix(uY0, max(uY0, cam.y - 5.5), uFollow);
	vec3 p;
	p.y = y0 + mod(q.y * uH - fall, uH);
	p.xz = c0 + mod(vec2(q.x, -q.z) * uS + drift - c0, uS);
	return p;
}

bool indoors(vec3 p) {   // under the store's roof (its footprint, the closet's bump, the theater)
	return p.y < 4.05 && ((p.x > -7.84 && p.x < 11.1 && p.z > -0.1 && p.z < 33.1) || (p.x > 11.1 && p.x < 12.7 && p.z > 27.9 && p.z < 29.9) || (p.x > -7.07 && p.x < 1.33 && p.z > 33.1 && p.z < 46.6));
}

void vertex() {
	float seed = UV.y;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p;
	BODY
	vE = UV.x;
	VERTEX = indoors(p) ? vec3(0.0, 0.0, 1000.0) : (VIEW_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	FRAG
}
"""
const RAIN_BODY := "float sp = 9.0 + seed * 3.0; p = place(VERTEX, uT * sp, uDrift, cam); p += UV.x * 0.45 * vec3(-uWind.x / sp, 1.0, -uWind.y / sp);"  # the tail: where it was a moment ago, up and upwind
const RAIN_FRAG := "ALBEDO = vec3(0.78, 0.82, 0.9) * (1.0 - 0.55 * uNight); ALPHA = (0.12 + 0.3 * vE) * uK;"
const SNOW_BODY := "float t = uT * (0.7 + seed * 0.5); p = place(VERTEX, t, uDrift * (0.8 + seed * 0.4), cam); p.x += sin(t * 0.9 + seed * 40.0) * 0.35; p.z += cos(t * 0.7 + seed * 30.0) * 0.25; POINT_SIZE = clamp((2.0 + seed * 3.0) * 40.0 / max(0.1, distance(p, cam)), 1.0, 7.0);"
const SNOW_FRAG := "ALBEDO = vec3(1.0 - 0.5 * uNight); ALPHA = (1.0 - smoothstep(0.2, 0.5, length(POINT_COORD - 0.5))) * 0.85 * uK;"
const FAR := [4.0, -16.2, 68.0, 31.5, 12.0, 0.0, 0.0]  # centre x z, size x z, height, floor, carried with you?
const NEAR := [0.0, 0.0, 26.0, 26.0, 9.5, -0.5, 1.0]
const GROUND := [[0x55595e, 0x2e3237, 1.0], [0x2b2d31, 0x1b1d20, 0.6], [0x9a9d9f, 0x6a6e72, 1.0], [0xb9bcc0, 0x8c9094, 1.0], [0x3f7d3a, 0x2f5f2c, 1.0]]  # pavement, road, sidewalk, curb, grass: dry, wet, how much snow settles
const SNOW := 0xe6ebf0

var kind := "clear"  # what's falling: "rain" | "snow" (kept after it stops, till the next spell)
var k := 0.0  # how hard, 0..1
var wet := 0.0  # how wet the ground is
var cover := 0.0  # how much snow's lying
var wind := 0.0
var gust := 0.0
var blow := Vector2.ZERO  # the wind, m/s along x and z (the way the air's going)
var fog := 0.0
var clouds := 0.0

var _settled := false
var _forced := false
var _said = null
var _t := 0.0
var _drift := Vector2.ZERO
var _rain: Array[MeshInstance3D] = []
var _snow: Array[MeshInstance3D] = []
var _ground: Array = []  # [material, dry, wet, snow]

@onready var sky: Node3D = $"../Sky"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	_glass_build()
	_drifts_build.call_deferred()
	_rain = [_fall(4500, true, FAR), _fall(16000, true, NEAR)]
	_snow = [_fall(3500, false, FAR), _fall(9000, false, NEAR)]
	var seen := {}
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):  # the ground's materials, by their dry colours
		for s in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.mesh.surface_get_material(s)
			if not m is ShaderMaterial or seen.has(m) or m.get_shader_parameter("albedo") == null:
				continue
			seen[m] = true
			var a: Color = m.get_shader_parameter("albedo")
			for g: Array in GROUND:
				var dry := Color.hex((g[0] << 8) | 0xff)
				if absf(a.r - dry.r) + absf(a.g - dry.g) + absf(a.b - dry.b) < 0.03 and mi.global_position.y < 1.0:
					_ground.append([m, dry.srgb_to_linear(), Color.hex((g[1] << 8) | 0xff).srgb_to_linear(), g[2]])


func _fall(n: int, lines: bool, box: Array) -> MeshInstance3D:
	var per := 2 if lines else 1
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in n:
		var p := Vector3(randf(), randf(), -randf())
		var r := randf()
		for v in per:
			pts.append(p)
			uvs.append(Vector2(v, r))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if lines else Mesh.PRIMITIVE_POINTS, arrays)
	var sh := Shader.new()
	sh.code = FALL.replace("BODY", RAIN_BODY if lines else SNOW_BODY).replace("FRAG", RAIN_FRAG if lines else SNOW_FRAG)
	for zv in ["27.9", "29.9", "33.1", "46.6"]:  # (the roofs' far ends, as deep as the store is: level.gd)
		sh.code = sh.code.replace(zv, str(Level.z(zv.to_float())))
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("uC", Vector2(box[0], box[1]))
	m.set_shader_parameter("uS", Vector2(box[2], box[3]))
	m.set_shader_parameter("uH", box[4])
	m.set_shader_parameter("uY0", box[5])
	m.set_shader_parameter("uFollow", box[6])
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 200, 1000))  # (it's wherever the shader puts it)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func set_now(what: String, hard := 0.9, fogged := 0.0) -> void:  # straight to it, the ground already soaked / snowed over (the web game's test kit)
	_forced = true
	kind = what if what != "clear" else kind
	k = hard if what != "clear" else 0.0
	wet = 1.0 if what == "rain" else 0.0
	cover = 1.0 if what == "snow" else 0.0
	drift = 1.0 if what == "snow" else 0.0
	fog = fogged
	clouds = 0.97 if what != "clear" else clouds


func _process(dt: float) -> void:  # weatherTick
	var plan: Dictionary = sky.plan
	if plan.is_empty():
		return
	var h := Clock.h
	if not _forced:
		var want: float = 0.0 if plan.kind == "clear" else plan.k * clampf(minf((h - plan.from) / 0.4, (plan.to - h) / 0.4), 0.0, 1.0)
		if kind != plan.kind and k < 0.02 and plan.kind != "clear":
			kind = plan.kind
		k += (want - k) * minf(1.0, dt / 6.0)
		if k < 0.001:
			k = 0.0
	var raining := k if kind == "rain" else 0.0
	var snowing := k if kind == "snow" else 0.0
	if not _forced:
		var hrs := dt / Clock.HOUR
		wet = clampf(wet + (hrs * 2.5 if raining > 0.15 else -hrs * 0.25) + (hrs * 0.5 if snowing > 0.15 and cover < 0.1 else 0.0), 0.0, 1.0)  # soaks in fast, dries over hours
		cover = clampf(cover + (hrs * 0.6 * snowing if snowing > 0.15 else -hrs * (0.6 if kind == "rain" else 0.12)), 0.0, 1.0)
		# fog (mornings, some nights, a little with rain), clouds (building ahead of a spell), and the wind, drifting through the day
		var fog_want: float = maxf(plan.fogAM * clampf((plan.fogEnd + 1.2 - h) / 1.2, 0.0, 1.0) if h < 12.0 else 0.0, plan.fogPM * clampf((h - plan.fogFrom) / 1.5, 0.0, 1.0))
		if not _settled:  # (coming in: the sky's already the day's, not filling in)
			_settled = true
			fog = fog_want
			clouds = plan.clouds
			wind = plan.wind
		fog += (minf(1.0, fog_want + 0.12 * raining) - fog) * minf(1.0, dt / 20.0)
		clouds += (maxf(plan.clouds, 0.97 if plan.kind != "clear" and h > plan.from - 1.5 and h < plan.to + 1.0 else 0.0) - clouds) * minf(1.0, dt / 30.0)
	for g: Array in _ground:
		var c: Color = g[1].lerp(g[2], wet).lerp(Color.hex((SNOW << 8) | 0xff).srgb_to_linear(), cover * g[3] * 0.85)
		g[0].set_shader_parameter("albedo", c.linear_to_srgb())
	_t += dt
	wind += (plan.wind * (0.75 + 0.25 * sin(h * 0.9 + plan.day)) + 0.2 * k - wind) * minf(1.0, dt / 8.0)
	var gn := 0.5 + 0.25 * sin(_t * 0.31) + 0.15 * sin(_t * 0.83 + 1.3) + 0.1 * sin(_t * 2.1 + 2.1)
	gust = minf(1.0, wind * maxf(0.0, gn - 0.35) * 2.2)
	var wv := wind * 5.0 + gust * 4.0
	blow = Vector2(cos(plan.windDir), sin(plan.windDir)) * wv
	_drift += blow * dt
	for mi in _rain + _snow:
		var m: ShaderMaterial = mi.mesh.surface_get_material(0)
		m.set_shader_parameter("uT", _t)
		m.set_shader_parameter("uK", k)
		m.set_shader_parameter("uNight", 1.0 - sky.level)
		m.set_shader_parameter("uWind", blow)
		m.set_shader_parameter("uDrift", _drift)
	for mi in _rain:
		mi.visible = raining > 0.01
	for mi in _snow:
		mi.visible = snowing > 0.01
	sky.clouds = clouds  # what the sky's turned by (see sky.gd)
	sky.wind = wind
	sky.wx_k = k
	sky.fog = fog
	sky.snowing = kind == "snow"
	_glass_tick(dt, raining)
	_drifts_tick(dt, snowing)
	var now := kind if k > 0.15 else "clear"  # what to say about it
	if _said != null and now != _said:
		hud.toast("It's started raining" if now == "rain" else "It's snowing!" if now == "snow" else "The rain's let up" if _said == "rain" else "It's stopped snowing")
	_said = now


# ---- rain on the outside of the storefront glass (either side of the doors): drops clinging all over it (as wet as
# the glass is), and drops that grow heavy and run down, leaving a trail and a few beads behind them; two sets of
# those, running at different speeds, so they don't move as one sheet (sky.js: wxGlass). The level has the three
# sheets on each pane already; the pictures on them are the web game's own (world/glass_N.png: tests/export-glb.mjs --cars)

const RUN := [0.0, 0.05, 0.11]  # how fast each sheet runs down

var _glass: Array[StandardMaterial3D] = []


func _glass_build() -> void:
	for i in 3:
		var path := "res://world/glass_%d.png" % i
		if not ResourceLoader.exists(path):
			push_warning("world/glass_N.png aren't there: no rain on the glass")
			_glass = []
			return
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = load(path)
		m.texture_repeat = true
		m.albedo_color.a = 0.0
		_glass.append(m)
	var found := 0
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		var at := mi.global_position
		if absf(at.y - 1.55) < 0.02 and at.z < -0.04 and at.z > -0.055 and mi.get_aabb().size.z < 0.001:
			mi.material_override = _glass[clampi(roundi((-0.045 - at.z) / 0.002), 0, 2)]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			found += 1
	if found != 6:
		push_warning("the storefront's rain sheets: %d of 6 found in the level" % found)


func _glass_tick(dt: float, raining: float) -> void:  # beads: as wet as the glass is; runners: while it's actually coming down
	for i in _glass.size():
		_glass[i].albedo_color.a = minf(0.95, wet if kind == "rain" or wet > 0.3 else 0.0) if i == 0 else minf(1.0, raining * 1.6)
		_glass[i].uv1_offset.y -= dt * RUN[i] * (0.5 + raining)


# ---- snow drifting where it would: banked against both sides of the lot's curb, along the far edge of the road, at
# the foot of the storefront, round the lamp footings and up against the roof's parapet. Lumps, not a strip: each
# starts at its own point (the shelter gets it first) and they grow over hours of snowing, then slump away slowly
# once it stops (faster in rain) (sky.js: wxDrifts)

var ROOFS: Array = [[-7.84, 11.1, -0.1, 33.1], [11.1, 12.7, 27.9, 29.9], [-7.07, 1.33, 33.1, 46.6]].map(func(r: Array) -> Array: return [r[0], r[1], Level.z(r[2]), Level.z(r[3])])  # (as deep as the store is: level.gd)

var drift := 0.0  # how deep they are, 0..1

var _lumps: Array = []  # [x, y, z, rx, rz, h, at, ry]
var _drifts := MultiMeshInstance3D.new()
var _drift_shown := -1.0


func _lump(x: float, z: float, rx: float, rz: float, h: float, y := -0.01, ry := 0.0) -> void:
	_lumps.append([x, y, z,  # ponytail: VaultBuster sank lumps on the road 12 cm (People.floor_y); needs a road-height check if they float
		 rx, rz, h, randf() * 0.55, ry + (randf() - 0.5) * 0.3])


func _lump_run(xa: float, xb: float, z: float, side: float, rz: float, h: float) -> void:
	var x := xa
	while x < xb:
		_lump(x, z + side * rz * 0.5 * randf(), 0.35 + randf() * 0.45, rz * (0.6 + randf() * 0.6), h * (0.4 + randf() * 0.6))
		x += 0.35 + randf() * 0.5


func _drifts_build() -> void:
	_lump_run(-27.74, 31.0, -12.3 + 0.09, 1.0, 0.22, 0.1)  # the lot side of the curb
	_lump_run(-27.74, 31.0, -12.3 - 0.09, -1.0, 0.18, 0.07)  # the road side, in the gutter
	_lump_run(-27.74, 31.0, -20.4 + 0.05, 1.0, 0.3, 0.06)  # the road's far edge, against the grass
	_lump_run(-7.74, -2.1, -0.06, -1.0, 0.2, 0.09)  # the foot of the storefront, not across the doors
	_lump_run(2.1, 11.0, -0.06, -1.0, 0.2, 0.09)
	for lx: float in [-14.74, -1.74, 11.26, 21.96]:  # round the lamp footings
		for a in 7:
			var t := a / 7.0 * TAU + randf() * 0.4
			_lump(lx + cos(t) * 0.36, -13.05 + sin(t) * 0.36, 0.16 + randf() * 0.08, 0.12, 0.08 + randf() * 0.06)
	var in_foot := func(x: float, z: float) -> bool: return ROOFS.any(func(r: Array) -> bool: return x > r[0] and x < r[1] and z > r[2] and z < r[3])
	for r: Array in ROOFS:  # up on the roof, against the inside of the parapet (not where one part of the roof runs on into the next)
		for s: Array in [[r[0], r[2], r[1], r[2], 0.0, 1.0], [r[0], r[3], r[1], r[3], 0.0, -1.0], [r[0], r[2], r[0], r[3], 1.0, 0.0], [r[1], r[2], r[1], r[3], -1.0, 0.0]]:  # each side, the last two pointing in
			var length := Vector2(s[2] - s[0], s[3] - s[1]).length()
			var t := 0.35
			while t < length - 0.35:
				var x: float = s[0] + (s[2] - s[0]) * t / length
				var z: float = s[1] + (s[3] - s[1]) * t / length
				if not in_foot.call(x - s[4] * 0.05, z - s[5] * 0.05):
					_lump(x + s[4] * 0.26, z + s[5] * 0.26, 0.3 + randf() * 0.45, 0.14 + randf() * 0.1, 0.05 + randf() * 0.07, 4.0 - 0.01, PI / 2.0 if s[4] != 0.0 else 0.0)
				t += 0.35 + randf() * 0.5
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 1.0
	dome.is_hemisphere = true
	dome.radial_segments = 12
	dome.rings = 5
	dome.material = StandardMaterial3D.new()
	dome.material.albedo_color = Color("#e9eef3")
	var tmp := MeshInstance3D.new()  # (onto the room's light, as the ground it lies on is)
	tmp.mesh = dome
	add_child(tmp)
	$"../Room".light(self)
	tmp.free()
	_drifts.multimesh = MultiMesh.new()
	_drifts.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_drifts.multimesh.mesh = dome
	_drifts.multimesh.instance_count = _lumps.size()
	_drifts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drifts.custom_aabb = AABB(Vector3(-40, -1, -30), Vector3(80, 8, 90))
	add_child(_drifts)


func _drifts_tick(dt: float, snowing: float) -> void:  # ~3 hours of hard snow to full; a day or so to go (a few hours in rain)
	var hrs := dt / Clock.HOUR
	if not _forced:
		drift = clampf(drift + (hrs * 0.33 * snowing if snowing > 0.15 else -hrs * (0.5 if kind == "rain" and k > 0.1 else 0.06)), 0.0, 1.0)
	if absf(drift - _drift_shown) < 0.004 and not (drift == 0.0 and _drift_shown > 0.0):
		return
	_drift_shown = drift
	_drifts.visible = drift > 0.0
	for i in _lumps.size():
		var s: Array = _lumps[i]
		var g := clampf((drift - s[6]) / (1.0 - s[6]), 0.0, 1.0)  # this lump's own share: none until the snow's been at it a while
		var w := 0.3 + 0.7 * sqrt(g)
		_drifts.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, s[7]) * Basis.from_scale(Vector3(s[3] * w, s[5] * g + 1e-4, s[4] * w)), Vector3(s[0], s[1], s[2])))
