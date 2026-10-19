extends Node3D
## The day going by overhead: the sky's colors and the sun for the hour, night, the day's clouds drifting.
## From the web game: store/shift.js (SKY_KEYS, todTick) and exterior/sky.js (wxPlan, wxSky, wxClouds). The numbers
## are its numbers. What the weather's doing (cloud, wind, rain, fog) is weather.gd's, handed in here each frame.
##
## The light it throws is room.gd's business (the sun's direction and colour, and the daylight through the glass, are
## worked out here for it).

const GLASS := {  # daylight's colour through the storefront glass (linear)
	"day": [0.95, 0.97, 1.0], "morning": [1.0, 0.9, 0.8], "gold": [1.0, 0.74, 0.45], "sunset": [1.0, 0.55, 0.34], "blue": [0.55, 0.65, 1.0],
}
const SKY_KEYS := [  # [hour, daylight 0..1, sky, daylight through the glass]: everything eases between neighbours
	[0.0, 0.0, 0x0e1a38, "blue"], [4.8, 0.0, 0x0e1a38, "blue"],
	[5.6, 0.12, 0x2d3564, "blue"],  # first light
	[6.3, 0.45, 0x9b8cb4, "sunset"],  # dawn
	[7.4, 0.85, 0x8fb0d8, "morning"], [8.6, 1.0, 0x4f8fd6, "day"], [17.4, 1.0, 0x4f8fd6, "day"],
	[18.8, 0.8, 0x9ea9bd, "gold"],  # golden hour
	[19.6, 0.45, 0xc9794f, "sunset"],  # sunset
	[20.3, 0.12, 0x39406e, "blue"],  # the blue hour
	[21.1, 0.0, 0x0e1a38, "blue"], [24.0, 0.0, 0x0e1a38, "blue"],  # night
]
const SUN_C := Color(0.95, 0.8539, 0.6584)  # noon sun: the web game's lin(0xfff3d9, 0.95)
const SUN_LOW := Color(0.95, 0.475, 0.209)  # sun on the horizon
const CITY := Color(0.035, 0.024, 0.012)  # the town's glow on the low sky at night
const CLOUD_LOW := Color(0.5, 0.52, 0.56)
const GLOWS := [0xff6f9a, 0xff8a3c, 0xff7466]
const INDOORS := [[-7.84, 11.1, -0.1, 33.1, 4.05], [11.1, 12.7, 27.9, 29.9, 4.05], [-7.07, 1.33, 33.1, 46.6, 4.05], [13.0, 21.0, 0.0, 14.0, 4.39]]  # under a roof: the store, its closet, the theater, next door (x0, x1, z0, z1, the ceiling)
const N := 56  # clouds; they wrap round inside this box
const X0 := -110.0
const X1 := 120.0
const Z0 := -95.0
const Z1 := 135.0

var level := 1.0  # daylight, 0..1 (tod.level)
var sky_color := Color()  # tod.sky
var sun_dir := Vector3.UP  # where the sun's light comes from (room.gd)
var sun_c := SUN_C
var day_c := Vector3.ONE
var plan := {}
var clouds := 0.0  # WX.clouds: these five are the weather's, set by weather.gd
var wind := 0.0  # WX.wind
var wx_k := 0.0  # WX.k: how hard it's raining or snowing
var fog := 0.0  # WX.fog
var _inside := 0.0  # 1: you're indoors
var snowing := false

var _mat := ShaderMaterial.new()
var _clouds: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []
var _mm := MultiMesh.new()
var _cloud_mat := StandardMaterial3D.new()
var _t := 0.0

@onready var env: Environment = $"../WorldEnvironment".environment


func _ready() -> void:
	_mat.shader = load("res://sky.gdshader")
	env.sky.sky_material = _mat
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED  # (or the sky's re-filtered every frame it changes)
	for i in N:
		var n := 5 + randi() % 3
		_clouds.append({ "x": randf_range(X0, X1), "y": 15.0 + randf() * 9.0, "z": randf_range(Z0, Z1), "s": 3.5 + randf() * 4.5, "p0": _puffs.size(), "n": n })
		for j in n:
			var t := j / float(n) * 6.28 + randf()
			var r := 0.5 + randf() * 0.6 if j else 0.0
			_puffs.append({ "ox": cos(t) * r * 1.2, "oy": randf() * 0.3, "oz": sin(t) * r * 0.8, "r": 0.45 + randf() * 0.35 if j else 0.9 })
	var puff := SphereMesh.new()  # (the web game's is an icosahedron: about this)
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 6
	puff.rings = 3
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # (lit as room.gd lights the outdoors: worked out in _sky)
	_cloud_mat.disable_fog = true
	puff.material = _cloud_mat
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = puff
	_mm.instance_count = _puffs.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(X0 - 20, 0, Z0 - 20), Vector3(X1 - X0 + 40, 50, Z1 - Z0 + 40))
	add_child(mmi)
	_tick(0.0)


func _process(dt: float) -> void:
	_tick(dt)


func _tick(dt: float) -> void:
	if plan.get("day") != Clock.day:
		plan = wx_plan(Clock.day)
	_tod()
	_sky(dt)
	_drift(dt)


func _over() -> float:  # overcast: under rain or snow, or a sky nearly full of cloud
	return maxf(minf(1.0, wx_k * 1.6), maxf(0.0, clouds - 0.65) / 0.35)


func _lin(hex: int) -> Color:  # a web colour, as the light it stands for
	return Color.hex((hex << 8) | 0xff).srgb_to_linear()


func _tod() -> void:  # sample the sky for the clock's hour (todTick)
	var h := fmod(Clock.h, 24.0)
	var i := 0
	while i < SKY_KEYS.size() - 2 and SKY_KEYS[i + 1][0] <= h:
		i += 1
	var a: Array = SKY_KEYS[i]
	var b: Array = SKY_KEYS[i + 1]
	var t := clampf((h - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var k := t * t * (3.0 - 2.0 * t)
	level = lerpf(a[1], b[1], k)
	sky_color = _lin(a[2]).lerp(_lin(b[2]), k)
	if wx_k > 0.0:  # overcast
		sky_color = sky_color.lerp(Color(0.42 * level + 0.07, 0.45 * level + 0.08, 0.5 * level + 0.1), wx_k * 0.8)
	var ga: Array = GLASS[a[3]]
	var gb: Array = GLASS[b[3]]
	day_c = Vector3(lerpf(ga[0], gb[0], k), lerpf(ga[1], gb[1], k), lerpf(ga[2], gb[2], k))  # daylight through the glass
	var arc := clampf((h - 5.9) / 14.2, 0.0, 1.0) * PI  # the sun: up in the east about 6, across, down in the west about 8
	var up := sin(arc)
	sun_dir = Vector3(-16.0 * cos(arc), 3.0 + 30.0 * up, -8.0).normalized()
	sun_c = SUN_C.lerp(SUN_LOW, pow(1.0 - up, 3.0)) * (1.0 - (0.45 if snowing else 0.7) * wx_k)  # warm and low at either end of the day; no sun through the clouds
	day_c *= 1.0 - 0.4 * wx_k  # ...and a duller light through the glass


func _bump(h: float, a: float, b: float, c: float, d: float) -> float:  # 0 up to a, 1 from b to c, 0 again by d (wxBump)
	return maxf(0.0, minf(1.0, minf((h - a) / (b - a), (d - h) / (d - c))))


func _v(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _sky(dt: float) -> void:  # wxSky.tick
	var h := fmod(Clock.h, 24.0)
	var L := level
	var c := clouds
	var over := maxf(0.0, c - 0.65) / 0.35
	var a := (h - 5.9) / 14.2 * PI  # the sun on its light's arc, carried on below the horizon at night
	var up := maxf(0.0, sin(a))
	var sun_dir := Vector3(-16.0 * cos(a), 30.0 * sin(a), -8.0).normalized()
	var grey := Color(0.36 * L + 0.02, 0.38 * L + 0.025, 0.42 * L + 0.04)
	var hor := sky_color.lerp(Color.WHITE, 0.2 * L).lerp(grey, c * 0.3) + CITY * (1.0 - L)  # paler down low by day; the town's glow on it at night
	var zen := (sky_color * (0.55 + 0.3 * (1.0 - L))).lerp(grey, over * 0.85)
	var g := maxf(plan.glowAM * _bump(h, 5.2, 6.0, 6.7, 7.6), plan.glowPM * _bump(h, 18.6, 19.4, 20.0, 20.8))
	var glow := g * (0.45 + 2.2 * c * (1.0 - c)) * (1.0 - over) * (1.0 - fog * 0.8)
	var glow_hue := _lin(GLOWS[plan.glowHue])
	var glow_c := glow_hue * 0.55
	_t += dt
	_mat.set_shader_parameter("uSun", sun_dir)
	_mat.set_shader_parameter("uSunUp", clampf(sun_dir.y * 14.0 + 0.25, 0.0, 1.0) * (1.0 - over) * (1.0 - fog * 0.85))
	var fog_c := Color(0.5 * L + 0.035, 0.53 * L + 0.04, 0.56 * L + 0.05).lerp(hor, 0.25)
	_mat.set_shader_parameter("uFogC", _v(fog_c))
	_mat.set_shader_parameter("uFog", minf(1.0, fog + wx_k * 0.3))
	var density := pow(fog, 1.3) * 0.11 + wx_k * (0.025 if snowing else 0.01)  # the air itself: the weather's fog, and a little with whatever's falling
	# no fog indoors (ours, or next door): from inside, the engine's is off (it's by distance alone, and would fill the
	# room), and what's out past the glass is fogged by the room's own shader instead (room.gd: uFog)
	var cam := get_viewport().get_camera_3d()
	var at := cam.global_position if cam != null else Vector3.ZERO
	var inside := INDOORS.any(func(b: Array) -> bool: return at.x > b[0] and at.x < b[1] and at.z > b[2] and at.z < b[3] and at.y < b[4])
	_inside += ((1.0 if inside else 0.0) - _inside) * minf(1.0, dt * 4.0)  # (eased through the doorway)
	RenderingServer.global_shader_parameter_set("uFog", Vector4(fog_c.r, fog_c.g, fog_c.b, density * _inside))
	env.fog_enabled = density * (1.0 - _inside) > 0.0005
	env.fog_light_color = fog_c.linear_to_srgb()
	env.fog_density = density * (1.0 - _inside)
	env.fog_sky_affect = 0.0  # (the sky does its own)
	_mat.set_shader_parameter("uSunC", _v(SUN_C.lerp(SUN_LOW, pow(1.0 - up, 3.0))))
	_mat.set_shader_parameter("uHor", _v(hor))
	_mat.set_shader_parameter("uZen", _v(zen))
	_mat.set_shader_parameter("uGlow", glow)
	_mat.set_shader_parameter("uGlowC", _v(glow_c))
	_mat.set_shader_parameter("uStar", pow(1.0 - L, 2.0) * (1.0 - minf(1.0, c * 1.1 + over)) * (1.0 - fog))
	_mat.set_shader_parameter("uMoonK", pow(1.0 - L, 1.5) * (1.0 - over * 0.9) * (1.0 - fog * 0.85))
	_mat.set_shader_parameter("uT", _t)
	# the clouds: greyer under overcast, catching the glow; their own light the sky's, all round them
	var cloud := Color.WHITE.lerp(CLOUD_LOW, over * 0.8).lerp(glow_c, minf(0.6, glow * 0.8))
	var em := Color(0.3 * L + 0.03, 0.31 * L + 0.035, 0.34 * L + 0.05) * (1.0 - 0.35 * over)
	var lit := Color(0.036, 0.047, 0.076).lerp(Color(0.21, 0.23, 0.22), L)  # the moon's light on them, or the sun's (half sky, half ground, half the lamp, over pi)
	var shown := cloud * lit + em.lerp(glow_hue, minf(1.0, glow * 1.4) * 0.6)
	_cloud_mat.albedo_color = Color(shown.r, shown.g, shown.b).linear_to_srgb()


func _drift(dt: float) -> void:  # wxClouds.tick: a few to a sky full, as the day has them, drifting with the wind up there
	var over := _over()
	var v: float = plan.cloudV * (0.4 + 1.8 * wind) * dt
	var dx: float = cos(plan.windDir) * v
	var dz: float = sin(plan.windDir) * v
	var show := roundi(N * minf(1.0, 0.04 + clouds * 0.96))
	var grow := 1.0 + 0.35 * over
	var k := 0
	for i in show:
		var cl := _clouds[i]
		cl.x = wrapf(cl.x + dx, X0, X1)
		cl.z = wrapf(cl.z + dz, Z0, Z1)
		for j in cl.n:
			var f := _puffs[cl.p0 + j]
			var r: float = f.r * cl.s * grow
			var at := Vector3(cl.x + f.ox * cl.s * grow, cl.y - 1.5 * over + f.oy * cl.s, cl.z + f.oz * cl.s * grow)
			_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(r, r * (0.55 - 0.15 * over), r)), at))
			k += 1
	_mm.visible_instance_count = k


func wx_plan(day: int) -> Dictionary:  # the day's weather, worked out from the date so it's the same every time (wxPlan)
	var s := [7907 * day + 101]
	var rnd := func() -> float:
		s[0] = (s[0] * 16807) % 2147483647
		return s[0] / 2147483647.0
	rnd.call()
	rnd.call()
	var month: int = Clock.date().month
	var winter := month == 12 or month <= 2
	var summer := month >= 6 and month <= 8
	var p := { "day": day, "kind": "clear", "from": 0.0, "to": 0.0, "k": 0.0 }
	if rnd.call() < (0.4 if winter else 0.25 if summer else 0.33):
		p.kind = "snow" if winter and rnd.call() < 0.65 else "rain"
		var all_day: bool = rnd.call() < 0.25
		if all_day:
			p.from = 0.0
		elif summer and p.kind == "rain":
			p.from = 14.0 + rnd.call() * 4.0
		else:
			p.from = 8.0 + rnd.call() * 13.0
		if all_day:
			p.to = 25.0
		else:
			p.to = p.from + (1.0 + rnd.call() * 2.0 if summer else 2.0 + rnd.call() * 6.0)
		p.k = 0.45 + rnd.call() * 0.55
	var s2 := [4111 * day + 977]
	var r2 := func() -> float:
		s2[0] = (s2[0] * 16807) % 2147483647
		return s2[0] / 2147483647.0
	r2.call()
	var shoulder := not winter and not summer
	var c: float = r2.call()
	if c < 0.3:  # clear, a few about, mostly cloudy
		p.clouds = r2.call() * 0.15
	elif c < 0.7:
		p.clouds = 0.2 + r2.call() * 0.4
	else:
		p.clouds = 0.6 + r2.call() * 0.35
	p.wind = 0.06 + pow(r2.call(), 1.6) * 0.6 + (0.08 if shoulder or winter else 0.0) + (0.15 if p.kind != "clear" else 0.0)
	p.windDir = (r2.call() - 0.5) * 1.6  # mostly out of the west (blowing toward +x), give or take
	p.cloudV = 0.4 + r2.call() * 1.4  # m/s up there, before the wind
	p.fogAM = 0.45 + r2.call() * 0.55 if r2.call() < (0.25 if shoulder else 0.15 if winter else 0.08) else 0.0
	p.fogEnd = 8.5 + r2.call() * 2.5
	p.fogPM = 0.3 + r2.call() * 0.4 if r2.call() < 0.07 else 0.0
	p.fogFrom = 20.5 + r2.call() * 2.0
	p.glowAM = 0.4 + r2.call() * 0.6 if r2.call() < 0.35 else r2.call() * 0.25
	p.glowPM = 0.4 + r2.call() * 0.6 if r2.call() < 0.4 else r2.call() * 0.25
	p.glowHue = int(floor(r2.call() * 3.0))
	return p
